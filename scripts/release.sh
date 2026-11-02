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

# Build otel-fork for all platforms (reusing `make all`: the lint-otel
# guard, pkg repackage, and version ldflags all come along) and, when
# Nexus credentials are configured, upload the artifacts.
#
# The build baseline and the remote directory name are both decided by
# the git tag — the compiled content and the uploaded path can never
# disagree. Run this from any branch:
#
#   ./scripts/release.sh v1.15.0-fork   # check out the tag, build from it,
#                                       # upload to <NEXUS_PATH>/v1.15.0-fork/,
#                                       # then check back out to where you were
#   ./scripts/release.sh                 # HEAD must be exactly on a tag,
#                                       # otherwise the run aborts
#
# Configuration (env vars take precedence over scripts/.nexus.conf):
#   NEXUS_URL    server base url      e.g. https://nexus.cdfsunrise.com
#   NEXUS_REPO   raw repository name  e.g. go-agent-version
#   NEXUS_PATH   root path in repo    e.g. /loongsuite-go
#   NEXUS_USER   account
#   NEXUS_PASS   password (env only; never commit it)
#
# Any of the five NEXUS_* values missing => build only, skip upload.
# Nexus REST API uses HTTP Basic Auth per request; there is no separate
# login step. The credential probe below stops the run before any file
# is transferred if auth fails.
#
# Usage:
#   ./scripts/release.sh [tag] [--force] [--no-upload] [--no-latest]
#     tag         git tag to build from (default: the tag HEAD is on)
#     --force     re-upload even if the tag directory already exists,
#                 and allow latest/ to move to an OLDER version (rollback)
#     --no-upload build only
#     --no-latest  upload but skip the latest/ refresh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# ---------------------------------------------------------------- config
CONF="$REPO_ROOT/scripts/.nexus.conf"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"
: "${NEXUS_URL:=}";  : "${NEXUS_REPO:=}"
: "${NEXUS_PATH:=}"; : "${NEXUS_USER:=}"; : "${NEXUS_PASS:=}"

NO_UPLOAD=0
NO_LATEST=0
FORCE=0
TAG=""
for arg in "$@"; do
  case "$arg" in
    --no-upload) NO_UPLOAD=1 ;;
    --no-latest) NO_LATEST=1 ;;
    --force)     FORCE=1 ;;
    -*) echo "usage: $0 [tag] [--force] [--no-upload] [--no-latest]" >&2; exit 1 ;;
    *)  if [ -n "$TAG" ]; then
          echo "ERROR: unexpected extra argument '$arg'" >&2
          echo "usage: $0 [tag] [--force] [--no-upload] [--no-latest]" >&2; exit 1
        fi
        TAG="$arg" ;;
  esac
done
CAN_UPLOAD=1
if [ -z "$NEXUS_URL" ] || [ -z "$NEXUS_REPO" ] || [ -z "$NEXUS_PATH" ] \
   || [ -z "$NEXUS_USER" ] || [ -z "$NEXUS_PASS" ]; then
  CAN_UPLOAD=0
fi

# ---------------------------------------------------------------- tag
# Resolve the build baseline. With an explicit tag, check it out (and
# check back out at exit, success or failure). Without one, HEAD must
# sit exactly on a tag — building an untagged state and labelling it
# with a version would be worse than refusing.
ORIG_REF=""
restore_ref() {
  if [ -n "$ORIG_REF" ]; then
    git checkout --quiet "$ORIG_REF"
    echo "==> checked back out to $ORIG_REF"
  fi
}
trap restore_ref EXIT

if [ -n "$TAG" ]; then
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
    || { echo "ERROR: tag '$TAG' not found"; exit 1; }
  ORIG_REF="$(git rev-parse --abbrev-ref HEAD)"
  [ "$ORIG_REF" = "HEAD" ] && ORIG_REF="$(git rev-parse HEAD)"
  if [ "$(git rev-parse HEAD)" != "$(git rev-parse "$TAG^{commit}")" ]; then
    echo "==> checking out $TAG (was on $ORIG_REF)"
    git checkout --quiet "$TAG"
  fi
  VERSION="$TAG"
else
  VERSION="$(git describe --tags --exact-match 2>/dev/null || true)"
  [ -n "$VERSION" ] \
    || { echo "ERROR: HEAD is not on a tag and no tag argument given"; \
         echo "       pass one explicitly, e.g.: $0 v1.15.0-fork"; exit 1; }
fi

# ---------------------------------------------------------------- build
echo "==> make all (inherits lint-otel guard, pkg repackage, version ldflags)"
make all

# ---------------------------------------------------------------- collect
# `make all` drops the artifacts in the repo root; gather them (plus a
# checksum file) into dist/<VERSION>/ so uploads and local inspection
# have a single, self-contained directory.
DIST="$REPO_ROOT/dist/$VERSION"
rm -rf "$DIST"; mkdir -p "$DIST"
ARTIFACTS=(
  otel-fork-darwin-amd64
  otel-fork-darwin-arm64
  otel-fork-linux-amd64
  otel-fork-linux-arm64
  otel-fork-windows-amd64.exe
)
for f in "${ARTIFACTS[@]}"; do
  [ -f "$f" ] || { echo "ERROR: $f missing (make all failed?)"; exit 1; }
  cp "$f" "$DIST/"
done
shasum -a 256 "$DIST"/otel-fork-* > "$DIST/SHA256SUMS"
echo "==> artifacts in: $DIST"
ls -l "$DIST"

if [ "$NO_UPLOAD" = 1 ]; then
  echo "==> --no-upload, done"
  exit 0
fi
if [ "$CAN_UPLOAD" = 0 ]; then
  echo "==> Nexus config incomplete (NEXUS_URL/REPO/PATH/USER/PASS), skipping upload"
  exit 0
fi

# ---------------------------------------------------------------- probe
echo "==> verifying Nexus credentials"
STATUS="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 \
  -u "$NEXUS_USER:$NEXUS_PASS" "$NEXUS_URL/service/rest/v1/repositories")"
if [ "$STATUS" != "200" ]; then
  echo "ERROR: Nexus auth/connectivity failed (HTTP $STATUS)"
  exit 1
fi

# ---------------------------------------------------------------- upload
BASE="$NEXUS_URL/repository/$NEXUS_REPO$NEXUS_PATH"

# A published tag directory is immutable: re-running release.sh on an
# already-uploaded tag is a no-op unless --force is given. SHA256SUMS is
# written together with the artifacts, so it doubles as the existence probe.
probe() { # $1 = path relative to $BASE; echoes the HTTP status
  curl -sS -o /dev/null -w '%{http_code}' --max-time 30 \
    -u "$NEXUS_USER:$NEXUS_PASS" -I "$BASE/$1"
}
if [ "$FORCE" = 0 ]; then
  EXIST="$(probe "$VERSION/SHA256SUMS")"
  if [ "$EXIST" = "200" ]; then
    echo "==> $NEXUS_PATH/$VERSION already uploaded, skipping (released versions are immutable)"
    echo "    re-upload intentionally with: $0 $TAG --force"
    echo "==> done"
    exit 0
  fi
fi

upload() { # $1 = local file, $2 = path relative to $BASE
  local s
  # Explicit Content-Type is REQUIRED: with binary bodies and no explicit
  # type, curl sends a default that the Nexus front layer rejects with
  # HTTP 500 (text bodies slip through, which is why small probes passed
  # while every real artifact failed). application/octet-stream is the
  # neutral type for raw-repository binaries.
  s="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 300 \
       -u "$NEXUS_USER:$NEXUS_PASS" -X PUT \
       -H "Content-Type: application/octet-stream" \
       --data-binary "@$1" "$BASE/$2")"
  [ "$s" = "201" ] || [ "$s" = "200" ] \
    || { echo "ERROR: upload $2 failed (HTTP $s)"; exit 1; }
}
upload_text() { # $1 = content, $2 = path relative to $BASE
  local s
  s="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 60 \
       -u "$NEXUS_USER:$NEXUS_PASS" -X PUT \
       -H "Content-Type: text/plain" \
       --data-binary "$1" "$BASE/$2")"
  [ "$s" = "201" ] || [ "$s" = "200" ] \
    || { echo "ERROR: upload $2 failed (HTTP $s)"; exit 1; }
}
for f in "$DIST"/*; do
  name="$(basename "$f")"
  echo "==> $NEXUS_REPO$NEXUS_PATH/$VERSION/$name"
  upload "$f" "$VERSION/$name"
done
# Self-describing marker: the tag directory records its own version.
upload_text "$VERSION" "$VERSION/VERSION"

# Refresh latest/ with a monotonic guard: latest/ carries a VERSION file
# telling consumers which release it mirrors, and moving it to an OLDER
# version is almost always a mistake (e.g. re-releasing v1.14.0-fork
# after v1.15.0-fork). --force overrides, e.g. for a deliberate rollback.
if [ "$NO_LATEST" = 1 ]; then
  echo "==> --no-latest, latest/ untouched"
else
  CURRENT="$(curl -sS --max-time 30 \
    -u "$NEXUS_USER:$NEXUS_PASS" "$BASE/latest/VERSION" 2>/dev/null || true)"
  if [ -n "$CURRENT" ] && [ "$FORCE" = 0 ]; then
    NEWER="$(printf '%s\n' "$CURRENT" "$VERSION" | sort -V | tail -1)"
    if [ "$NEWER" = "$CURRENT" ] && [ "$CURRENT" != "$VERSION" ]; then
      echo "ERROR: latest/ is at $CURRENT, refusing to move it back to $VERSION"
      echo "       deliberate rollback? use: $0 $TAG --force"
      exit 1
    fi
  fi
  for f in "$DIST"/*; do
    upload "$f" "latest/$(basename "$f")"
  done
  upload_text "$VERSION" "latest/VERSION"
  echo "==> latest/ now at $VERSION"
fi
echo "==> done"
