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

# Vendor a path-rewritten fork of the OpenTelemetry Go modules into
# pkg/go-sdk so that the injected agent module has zero
# go.opentelemetry.io/* module dependencies ("Path A" isolation).
#
# The fork keeps the upstream file layout under pkg/go-sdk and only
# rewrites import paths, so refreshing it after an OTel release is a
# mechanical re-run of this script (module versions pinned below).
#
# Usage: scripts/vendor_otel_fork.sh
# Requires the listed modules in the local module cache
# (go mod download from the repo root is enough).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$REPO_ROOT/pkg/go-sdk"
FORK_PREFIX="github.com/alibaba/loongsuite-go/pkg/go-sdk"
MC="$(go env GOMODCACHE)"

# module@version (relative to $MC/go.opentelemetry.io) -> destination
# subdirectory under pkg/go-sdk. The destination equals the module import
# path with the go.opentelemetry.io prefix replaced by the fork prefix,
# so the uniform rewrite below resolves every internal import.
MODULES=(
  "otel@v1.40.0                                         otel"
  "otel/trace@v1.40.0                                   otel/trace"
  "otel/metric@v1.40.0                                  otel/metric"
  "otel/sdk@v1.40.0                                     otel/sdk"
  "otel/sdk/metric@v1.40.0                              otel/sdk/metric"
  "otel/exporters/otlp/otlptrace@v1.40.0                otel/exporters/otlp/otlptrace"
  "otel/exporters/otlp/otlptrace/otlptracegrpc@v1.40.0  otel/exporters/otlp/otlptrace/otlptracegrpc"
  "otel/exporters/otlp/otlptrace/otlptracehttp@v1.40.0  otel/exporters/otlp/otlptrace/otlptracehttp"
  "otel/exporters/otlp/otlpmetric/otlpmetricgrpc@v1.40.0 otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
  "otel/exporters/otlp/otlpmetric/otlpmetrichttp@v1.40.0 otel/exporters/otlp/otlpmetric/otlpmetrichttp"
  "otel/exporters/prometheus@v0.61.0                    otel/exporters/prometheus"
  "otel/exporters/stdout/stdoutmetric@v1.40.0           otel/exporters/stdout/stdoutmetric"
  "otel/exporters/stdout/stdouttrace@v1.40.0            otel/exporters/stdout/stdouttrace"
  "otel/exporters/zipkin@v1.40.0                        otel/exporters/zipkin"
  "proto/otlp@v1.9.0                                    proto/otlp"
  "auto/sdk@v1.2.1                                      auto/sdk"
  "contrib/instrumentation/runtime@v0.65.0              contrib/instrumentation/runtime"
)

# Module cache entries are read-only; restore write permission on the
# destination before wiping it on a re-run and after each extraction so
# later iterations can nest further modules under these directories.
chmod -R u+w "$DEST" 2>/dev/null || true
rm -rf "$DEST"
mkdir -p "$DEST"

for entry in "${MODULES[@]}"; do
  mod="${entry%%[[:space:]]*}"
  sub="$(echo "$entry" | awk '{print $NF}')"
  src="$MC/go.opentelemetry.io/$mod"
  if [ ! -d "$src" ]; then
    echo "ERROR: $src not found in module cache" >&2
    echo "       run 'go mod download' from the repo root first" >&2
    exit 1
  fi
  dst="$DEST/$sub"
  mkdir -p "$dst"
  # Copy package sources; skip module metadata, tests and repo scaffolding.
  # LICENSE files are kept for Apache-2.0 attribution.
  (cd "$src" && tar cf - \
      --exclude='go.mod' \
      --exclude='go.sum' \
      --exclude='*_test.go' \
      --exclude='example*' \
      --exclude='testdata' \
      --exclude='*.md' \
      --exclude='Makefile' \
      --exclude='*.yaml' \
      --exclude='*.yml' \
      --exclude='*.json' \
      --exclude='*.Dockerfile' \
      --exclude='renovate.json' \
      --exclude='requirements.txt' \
      --exclude='verify_released_changelog.sh' \
      --exclude='CODEOWNERS' \
      --exclude='.github' \
      .) | (cd "$dst" && tar xf -)
  # Module cache entries are read-only; restore write permissions so
  # later iterations can nest further modules under these directories.
  chmod -R u+w "$dst"
  echo "vendored $mod -> pkg/go-sdk/$sub"
done

# Uniform import-path rewrite across the whole fork. Order is irrelevant:
# the four source prefixes do not overlap.
find "$DEST" -name '*.go' -print0 | xargs -0 perl -pi -e "
  s{go\.opentelemetry\.io/otel}{${FORK_PREFIX}/otel}g;
  s{go\.opentelemetry\.io/proto/otlp}{${FORK_PREFIX}/proto/otlp}g;
  s{go\.opentelemetry\.io/auto/sdk}{${FORK_PREFIX}/auto/sdk}g;
  s{go\.opentelemetry\.io/contrib}{${FORK_PREFIX}/contrib}g;
"

gofmt -w "$DEST"

# Native test hooks: stock loongsuite-go injects these vars into the user's
# OTel packages via file rules (otel_trace_test_func_holder.go and friends).
# With the fork, pkg imports its own SDK, so the hooks must live in the fork
# itself. Written here so re-runs of the script keep them.
cat > "$DEST/otel/sdk/trace/test_func_holder.go" <<'EOF'
// Test hooks normally injected into the user's OTel SDK by file rules.
// The fork carries them natively; see pkg/testaccess.
package trace

var GetTestSpans func() interface{}
var ResetTestSpans func()
EOF
cat > "$DEST/otel/sdk/metric/test_func_holder.go" <<'EOF'
// Test hooks normally injected into the user's OTel SDK by file rules.
// The fork carries them natively; see pkg/testaccess.
package metric

var GetTestMetrics func() (interface{}, error)
EOF

# Exported context key so the rules/otsdk bridge can read/write the fork's
# current span in contexts (the upstream key is unexported).
cat > "$DEST/otel/trace/context_ext.go" <<'EOF'
// Exported alias of the unexported context key, used by the
// rules/otsdk bridge to mirror the fork's current span into
// user OTel contexts.
package trace

const CurrentSpanKey = currentSpanKey
EOF

cat > "$DEST/README.md" <<EOF
# go-sdk: vendored OpenTelemetry fork (path-rewritten)

This directory contains a copy of the OpenTelemetry Go modules listed in
scripts/vendor_otel_fork.sh with every go.opentelemetry.io import path
rewritten to github.com/alibaba/loongsuite-go/pkg/go-sdk/...

The injected agent module therefore has no direct go.opentelemetry.io
module dependency: the user application's OTel version is bridged at
runtime by the rules/otsdk adapters instead of being pinned via replace
directives. google.golang.org/grpc (used by the OTLP exporters' shared
config) transitively requires go.opentelemetry.io/otel as an indirect
dependency; that entry participates in MVS only and never pins or
downgrades the user's version because the tool adds no replace.

DO NOT edit files here by hand; rerun scripts/vendor_otel_fork.sh to
refresh the baseline (the script also re-adds the native test hooks).
Original sources are Apache-2.0 licensed (see the LICENSE files kept
per vendored module).
EOF

echo "done: fork generated at $DEST"
