#!/usr/bin/env bash
# Copyright (c) 2024 Alibaba Group Holding Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Semi-automatic upstream tag sync for the internal-otelsdk branch.
#
# Usage: ./scripts/sync_upstream.sh <upstream-tag> [options]
#   e.g.: ./scripts/sync_upstream.sh v1.15.0
#
# Options:
#   --tag    also create the local vX.Y.Z-fork annotated tag at the end
#
# Design: idempotent, checkpoint-style stages. Re-run the same command after
# resolving a conflict or fixing a reported leak; the script resumes at the
# first incomplete stage. It never pushes and never rewrites imports on its
# own: leaky real go.opentelemetry.io imports must be rewritten to the
# vendored fork (pkg/go-sdk/...) by hand, then the script is re-run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

UPSTREAM_REMOTE=upstream
INTEGRATION_BRANCH=internal-otelsdk
MIRROR_BRANCH=main
GUARD=scripts/check_otel_imports.sh

TAG=""
CREATE_TAG=0
for arg in "$@"; do
  case "$arg" in
    --tag) CREATE_TAG=1 ;;
    v*) TAG="$arg" ;;
    *) echo "usage: $0 <upstream-tag> [--tag]" >&2; exit 1 ;;
  esac
done
if [ -z "$TAG" ]; then
  echo "usage: $0 <upstream-tag> [--tag]" >&2
  exit 1
fi

say() { echo "[sync-upstream] $*"; }
die() { echo "[sync-upstream] ERROR: $*" >&2; exit 1; }

# Whitelisted rule modules may keep real go.opentelemetry.io imports and
# requires (same list as scripts/check_otel_imports.sh).
is_whitelisted() {
  case "$1" in
    pkg/rules/otsdk|pkg/rules/otel-context|pkg/rules/otel-sdk*|pkg/rules/echo|\
    pkg/rules/gin|pkg/rules/go-kit-log|pkg/rules/golog|pkg/rules/goslog|\
    pkg/rules/gorestful|pkg/rules/hertz*|pkg/rules/iris|pkg/rules/logrus|\
    pkg/rules/mux*|pkg/rules/zap*|pkg/rules/zerolog|pkg/rules/gomicro|\
    pkg/rules/aws-sdk-go*) return 0 ;;
    *) return 1 ;;
  esac
}

sweep_stale_requires() {
  local fail=0 gomod dir deps d
  while IFS= read -r gomod; do
    dir="$(dirname "$gomod")"
    is_whitelisted "$dir" && continue
    deps="$(grep -oE '^[[:space:]]+go\.opentelemetry\.io/[A-Za-z0-9/._-]+' "$gomod" \
            | awk '{print $1}' | sort -u || true)"
    [ -z "$deps" ] && continue
    say "dropping stale otel requires in $dir"
    for d in $deps; do
      (cd "$dir" && go mod edit -droprequire="$d") || { echo "  FAILED: $dir $d" >&2; fail=1; }
    done
  done < <(find pkg/rules -name go.mod)
  return $fail
}

# Deterministic resolution of the recurring go.mod conflict class:
# upstream bumps/adds otel requires on lines our sweep deleted, so both sides
# touched the same lines. Resolve by taking the upstream file (keeps its
# non-otel version bumps) and re-deleting the otel requires — except for
# whitelisted modules (dev-only manifests that may keep real otel) and
# pkg/go.sum (extra entries are harmless). pkg/go.mod runs LAST so its
# `go mod tidy` rewrites go.sum after the theirs checkout, then stages both.
resolve_gomod_conflicts() {
  local f dir deps d
  while IFS= read -r f; do
    dir="$(dirname "$f")"
    case "$f" in
      pkg/go.mod) continue ;;  # handled in the second pass below
      pkg/go.sum)
        git checkout --theirs -- "$f" && git add "$f"
        say "resolved $f (took upstream)"
        ;;
      pkg/rules/*/go.mod|pkg/rules/*/*/go.mod|pkg/rules/*/*/*/go.mod)
        git checkout --theirs -- "$f"
        if ! is_whitelisted "$dir"; then
          deps="$(grep -oE '^[[:space:]]+go\.opentelemetry\.io/[A-Za-z0-9/._-]+' "$f" \
                  | awk '{print $1}' | sort -u || true)"
          for d in $deps; do
            (cd "$dir" && go mod edit -droprequire="$d") || return 1
          done
        fi
        git add "$f"
        if is_whitelisted "$dir"; then
          say "resolved $f (upstream base; whitelist keeps otel)"
        else
          say "resolved $f (upstream base; otel requires dropped)"
        fi
        ;;
    esac
  done < <(git diff --name-only --diff-filter=U | grep -E '^pkg/(go\.mod|go\.sum|rules/.*/go\.mod)$' || true)

  if git diff --name-only --diff-filter=U | grep -qE '^pkg/go\.mod$'; then
    git checkout --theirs -- pkg/go.mod
    deps="$(grep -oE '^[[:space:]]+go\.opentelemetry\.io/[A-Za-z0-9/._-]+' pkg/go.mod \
            | awk '{print $1}' | sort -u || true)"
    for d in $deps; do
      (cd pkg && go mod edit -droprequire="$d") || return 1
    done
    # Re-record the grpc-chain otel MVS floor as indirect entries; this also
    # rewrites go.sum (already checked out to theirs) to match the resolved
    # go.mod, so stage both afterwards.
    (cd pkg && go mod tidy) || return 1
    git add pkg/go.mod && git add pkg/go.sum
    say "resolved pkg/go.mod (upstream base; otel requires dropped; tidied)"
  fi
}

# ---------------------------------------------------------------- stage 0: repo state
[ -f "$GUARD" ] || die "guard script $GUARD not found (run me on $INTEGRATION_BRANCH)"
if [ -f .git/MERGE_HEAD ]; then
  # Resume mode: a conflicted merge is exactly the state we continue from.
  CURRENT_MERGE="$(cat .git/MERGE_HEAD)"
  [ "$CURRENT_MERGE" = "$(git rev-parse "$TAG^{commit}")" ] \
    || die "MERGE_HEAD is $CURRENT_MERGE, not $TAG — re-run with that tag (or git merge --abort)"
  say "stage 0: resuming conflicted merge of $TAG"
else
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  if [ "$BRANCH" != "$INTEGRATION_BRANCH" ]; then
    if git diff --quiet && git diff --cached --quiet; then
      git checkout "$INTEGRATION_BRANCH" || die "cannot checkout $INTEGRATION_BRANCH"
    else
      die "dirty worktree; commit or stash first (current branch: $BRANCH)"
    fi
  fi
  git diff --quiet && git diff --cached --quiet || die "dirty worktree on $INTEGRATION_BRANCH"
fi
git rev-parse -q --verify "refs/tags/$TAG^{commit}" >/dev/null \
  || die "tag $TAG not found locally; run: git fetch $UPSTREAM_REMOTE --tags"

# ---------------------------------------------------------------- stage 1: mirror main
# Keep the local mirror identical to upstream, ff-only by construction
# (git fetch refuses to update a ref non-fast-forward). Never pushes.
say "stage 1: fetching $UPSTREAM_REMOTE (tags + main ff-only)"
if ! git fetch "$UPSTREAM_REMOTE" --tags >/dev/null 2>&1; then
  say "git fetch $UPSTREAM_REMOTE failed (offline?); continuing with local refs"
fi
# Compare against the last known upstream/main; only refuse when local main
# is NOT a fast-forward of it (a real divergence). Being ahead is impossible
# for a strict mirror, being behind just means the fetch failed/skipped.
if git rev-parse -q --verify refs/remotes/"$UPSTREAM_REMOTE"/main >/dev/null; then
  if ! git merge-base --is-ancestor refs/remotes/"$UPSTREAM_REMOTE"/main "$MIRROR_BRANCH"; then
    die "local $MIRROR_BRANCH diverged from upstream — resolve by hand (it must be a strict mirror)"
  fi
  if git fetch "$UPSTREAM_REMOTE" main:main >/dev/null 2>&1; then
    say "stage 1: local $MIRROR_BRANCH fast-forwarded (or already current)"
  else
    say "stage 1: $MIRROR_BRANCH ff-update skipped (offline or already current)"
  fi
else
  die "no $UPSTREAM_REMOTE/main ref; run: git fetch $UPSTREAM_REMOTE main"
fi

# ---------------------------------------------------------------- stage 2: merge tag
if git merge-base --is-ancestor "$TAG" HEAD 2>/dev/null; then
  say "stage 2: $TAG already merged into $INTEGRATION_BRANCH"
elif [ -f .git/MERGE_HEAD ]; then
  say "stage 2: applying deterministic resolutions to the conflicted merge"
  resolve_gomod_conflicts
  if git status --porcelain | grep -qE '^(UU|AA|DD|AU|UA|DU|UD)'; then
    say "remaining conflicts need MANUAL resolution:"
    git status --porcelain | grep -E '^(UU|AA|DD|AU|UA|DU|UD)' || true
    say "resolution rule: take the upstream side for everything EXCEPT the"
    say "go.opentelemetry.io -> pkg/go-sdk import rewrites and the Path-A"
    say "gutting of otelDeps in tool/preprocess/update.go (keep ours)."
    say "after 'git add' run me again."
    exit 2
  fi
  git commit --no-edit >/dev/null || die "auto-resolved but 'git commit' failed"
  say "stage 2: merge committed after deterministic conflict resolution"
else
  say "stage 2: merging $TAG into $INTEGRATION_BRANCH"
  if ! git merge --no-edit "$TAG"; then
    say "merge produced conflicts; applying deterministic go.mod resolutions"
    resolve_gomod_conflicts
    if git status --porcelain | grep -qE '^(UU|AA|DD|AU|UA|DU|UD)'; then
      say "remaining conflicts need MANUAL resolution:"
      git status --porcelain | grep -E '^(UU|AA|DD|AU|UA|DU|UD)' || true
      say "resolution rule: take the upstream side for everything EXCEPT the"
      say "go.opentelemetry.io -> pkg/go-sdk import rewrites and the Path-A"
      say "gutting of otelDeps in tool/preprocess/update.go (keep ours)."
      say "after 'git add' run me again."
      exit 2
    fi
    git commit --no-edit >/dev/null || die "auto-resolved but 'git commit' failed"
    say "stage 2: merge committed after deterministic conflict resolution"
  fi
fi
[ -f .git/MERGE_HEAD ] && die "merge still in progress; resolve conflicts and re-run"
git diff --quiet && git diff --cached --quiet || die "unexpected dirty worktree after merge; commit first"

# ---------------------------------------------------------------- stage 3: guard + sweep
if "$GUARD" >/dev/null 2>&1; then
  say "stage 3: isolation guard passed"
else
  say "stage 3: sweeping stale otel requires (whitelisted modules skipped)"
  sweep_stale_requires || die "droprequire failed; see output above"
  if "$GUARD" >/dev/null 2>&1; then
    say "stage 3: isolation guard passed after sweep"
  else
    say "leaky real otel imports remain — these need MANUAL rewriting to"
    say "github.com/alibaba/loongsuite-go/pkg/go-sdk/... ; list:"
    "$GUARD" 2>&1 | grep '^ERROR' || true
    die "fix the leaks above, then re-run this script"
  fi
fi

# ---------------------------------------------------------------- stage 4: build
say "stage 4: make package-pkg (runs the guard again as a pre-step)"
make package-pkg || die "make package-pkg failed"
say "stage 4: make build (produces the otel-fork binary)"
make build || die "make build failed"

# ---------------------------------------------------------------- stage 5: version-matrix regression
# Build the demo matrix with the freshly built otel-fork to prove the OTel
# isolation contract end to end. All three tiers guard the same floor
# discipline:
#   - grpc-demo      : no-otel user project -> otel enters only via the
#                      upstream golog/goslog rule cascade (stdlib log rules are
#                      ungated and every real project hits them), so the
#                      injected otel must equal the tool floor exactly;
#                      an empty graph is the even better outcome.
#   - otel-low-demo  : user otel BELOW the GLS floor    -> raised to >= v1.39.0
#   - otel-high-demo : user otel above the tool floor   -> user version wins
# go.mod/go.sum/otel.runtime.go/.otel-build are restored/removed afterwards.
#
# Freshness rule for otel-high-demo: the demo pin must stay above the tool
# floor (= max otel require across the whitelisted rule modules; non-
# whitelisted ones are guaranteed otel-free by the guard, and the vendored
# go-sdk baseline never participates in user MVS). Whenever the floor catches
# up with the pin, the demo is bumped to the latest otel release — unless the
# tool itself is already at the latest, in which case pin == floor == latest
# is the accepted boundary (user at the floor, no bump).
FLOOR_SOFT_CEILING=v1.40.0   # floor discipline: warn when the low demo resolves above this

ver_ge() { [ "$(printf '%s\n' "$1" "$2" | sort -V | head -1)" = "$2" ]; }

tool_floor() {
  grep -rhoE 'go\.opentelemetry\.io/otel v[0-9]+\.[0-9]+\.[0-9]+' pkg/rules --include=go.mod \
    | awk '{print $2}' | sort -V | tail -1
}

latest_otel() {
  go list -m -versions go.opentelemetry.io/otel 2>/dev/null | awk '{print $NF}'
}

HIGH_DEMO=example/otel-high-demo
FLOOR="$(tool_floor)"
say "stage 5: tool otel floor is ${FLOOR:-none}"
if LATEST="$(latest_otel)" && [ -n "$LATEST" ]; then
  PIN="$(grep -oE 'go\.opentelemetry\.io/otel v[0-9]+\.[0-9]+\.[0-9]+' "$HIGH_DEMO/go.mod" | head -1 | awk '{print $2}')"
  if [ -n "$FLOOR" ] && [ -n "$PIN" ] && ! ver_ge "$PIN" "$FLOOR" && [ "$(printf '%s\n' "$FLOOR" "$LATEST" | sort -V | tail -1)" = "$LATEST" ] && [ "$FLOOR" != "$LATEST" ]; then
    say "stage 5: tool floor $FLOOR caught up with demo pin $PIN; bumping $HIGH_DEMO to latest $LATEST"
    (cd "$HIGH_DEMO" \
      && go mod edit -require="go.opentelemetry.io/otel@$LATEST" -require="go.opentelemetry.io/otel/sdk@$LATEST" \
      && go mod tidy) || die "failed to bump $HIGH_DEMO to $LATEST"
    say "stage 5: bump is part of this sync's review diff — remember to commit it"
  elif [ -n "$PIN" ] && ! ver_ge "$PIN" "$FLOOR" && [ "$FLOOR" = "$LATEST" ]; then
    say "stage 5: tool floor $FLOOR is already the latest otel release; keeping demo pin $PIN (boundary case)"
  fi
else
  say "stage 5: could not query latest otel version (offline?); freshness check skipped — verify the demo pin by hand"
fi

VERSION_MATRIX=(
  "example/grpc-demo|floor"
  "example/otel-low-demo|ge|v1.39.0"
  "$HIGH_DEMO|eq|pin"
)
for spec in "${VERSION_MATRIX[@]}"; do
  dir="${spec%%|*}"; rest="${spec#*|}"; mode="${rest%%|*}"; expect="${rest#*|}"
  [ "$expect" = pin ] && expect="$(grep -oE 'go\.opentelemetry\.io/otel v[0-9]+\.[0-9]+\.[0-9]+' "$dir/go.mod" | head -1 | awk '{print $2}')"
  say "stage 5: regression build $dir (expect: $mode ${expect:-no-otel})"
  cp "$dir/go.mod" "$dir/go.mod.syncbak"
  if [ -f "$dir/go.sum" ]; then cp "$dir/go.sum" "$dir/go.sum.syncbak"; fi
  ok=1
  if ! (cd "$dir" && "$REPO_ROOT/otel-fork" go build -o /tmp/sync-demo-bin .); then
    say "  BUILD FAILED for $dir"
    ok=0
  fi
  if [ "$ok" = 1 ]; then
    # The tool restores go.mod on success, so the ground truth of what MVS
    # actually resolved is the module metadata embedded in the built binary.
    resolved="$(go version -m /tmp/sync-demo-bin 2>/dev/null | awk '$1=="dep" && $2=="go.opentelemetry.io/otel" {print $3}')"
    case "$mode" in
      floor)
        # No-otel project: otel may enter via the upstream golog/goslog rule
        # cascade (ungated stdlib log rules; net/http and grpc all hit them),
        # but it must be brought in exactly at the tool floor — nothing
        # higher. An empty graph is the even better outcome.
        if [ -z "$resolved" ]; then
          say "  no otel in graph, as required"
        elif [ "$resolved" = "$FLOOR" ]; then
          say "  otel injected at the tool floor $resolved (upstream golog/goslog cascade)"
          if [ -n "$FLOOR_SOFT_CEILING" ] && ! ver_ge "$FLOOR_SOFT_CEILING" "$resolved"; then
            say "  WARNING: floor inflated above $FLOOR_SOFT_CEILING — cap the whitelisted otel requires"
          fi
        else
          say "  FAILED: injected otel $resolved does not match the tool floor ${FLOOR:-none} (a require above the floor leaked in)"; ok=0
        fi ;;
      ge)
        if [ -z "$resolved" ]; then
          say "  FAILED: otel missing from graph after instrumentation"; ok=0
        elif ver_ge "$resolved" "$expect"; then
          say "  resolved go.opentelemetry.io/otel $resolved (>= $expect, GLS injectable)"
          if [ -n "$FLOOR_SOFT_CEILING" ] && ! ver_ge "$FLOOR_SOFT_CEILING" "$resolved"; then
            say "  WARNING: floor inflated above $FLOOR_SOFT_CEILING — cap the whitelisted otel requires"
          fi
        else
          say "  FAILED: resolved $resolved < required $expect (GLS hooks would not inject)"; ok=0
        fi ;;
      eq)
        if [ "$resolved" != "$expect" ]; then
          say "  FAILED: user version did not win: resolved $resolved, expected $expect"; ok=0
        else
          say "  user version wins: $resolved"
        fi ;;
    esac
  fi
  mv "$dir/go.mod.syncbak" "$dir/go.mod"
  if [ -f "$dir/go.sum.syncbak" ]; then mv "$dir/go.sum.syncbak" "$dir/go.sum"; fi
  rm -f "$dir/otel.runtime.go" /tmp/sync-demo-bin
  rm -rf "$dir/.otel-build"
  [ "$ok" = 1 ] || die "version-matrix regression failed at $dir"
done
say "stage 5: version-matrix regression passed"

# ---------------------------------------------------------------- stage 6: tag
UPSTREAM_HASH="$(git rev-parse "$TAG^{commit}" | cut -c1-12)"
FORK_TAG="${TAG}-fork"
if [ "$CREATE_TAG" = 1 ]; then
  if git rev-parse -q --verify "refs/tags/$FORK_TAG" >/dev/null; then
    say "stage 6: $FORK_TAG already exists, not touching it"
  else
    git tag -a "$FORK_TAG" -m \
      "Fork of upstream $TAG ($UPSTREAM_HASH): vendored OTel SDK (Path A) with isolation guard"
    say "stage 5: created local annotated tag $FORK_TAG"
  fi
fi

say "done. manual follow-ups:"
say "  1. extra regression on your otel-using project, e.g."
say "     cd /Users/wenjiang/cdfsh_projectspace/cdf-channel-center && otel-fork go build -o main-fork ."
say "     (grpc-demo + the otel-low/high version matrix already ran in stage 5)"
say "  2. review, then push by hand:"
say "     git push origin $INTEGRATION_BRANCH${CREATE_TAG:+ $FORK_TAG}"
say "  3. if local $MIRROR_BRANCH moved forward, push it too: git push origin $MIRROR_BRANCH"
say "  4. if stage 5 bumped $HIGH_DEMO, commit that go.mod change too"
[ "$CREATE_TAG" = 0 ] && say "  (run with --tag to have the fork tag created automatically)"
exit 0
