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

# Guard for the "Path A" OTel isolation (see pkg/go-sdk/README.md).
#
# The injected agent module must not depend on go.opentelemetry.io modules
# except for the whitelisted rule modules that deliberately interact with the
# USER's OTel (the otsdk bridge, the otel-sdk/otel-context GLS hooks, and the
# rules that consume GLS APIs injected into the user's OTel packages).
#
# Run this after merging upstream: new upstream rules arrive with real
# go.opentelemetry.io imports that must be rewritten to the vendored fork
# (github.com/alibaba/loongsuite-go/pkg/go-sdk/...) before they can reach a
# user build, otherwise instrumentation of those libraries breaks with
# cross-package type mismatches.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Rule modules allowed to import the real go.opentelemetry.io packages.
# Everything else must import the vendored fork under pkg/go-sdk instead.
WHITELIST=(
  "pkg/rules/otsdk"
  "pkg/rules/otel-context"
  "pkg/rules/otel-sdk"
  "pkg/rules/echo"
  "pkg/rules/gin"
  "pkg/rules/go-kit-log"
  "pkg/rules/golog"
  "pkg/rules/goslog"
  "pkg/rules/gorestful"
  "pkg/rules/hertz"
  "pkg/rules/iris"
  "pkg/rules/logrus"
  "pkg/rules/mux"
  "pkg/rules/zap"
  "pkg/rules/zerolog"
  "pkg/rules/gomicro"
  "pkg/rules/aws-sdk-go"
)

is_whitelisted() {
  local dir="$1"
  for w in "${WHITELIST[@]}"; do
    case "$dir" in
      "$w"*) return 0 ;;
    esac
  done
  return 1
}

status=0

# 1. No real go.opentelemetry.io imports outside the whitelist, the vendored
#    fork itself, and test files.
while IFS= read -r file; do
  dir="$(dirname "$file")"
  case "$dir" in
    pkg/go-sdk/*) continue ;;
  esac
  if is_whitelisted "$dir"; then
    continue
  fi
  # Whitelisted module files were already filtered by dir; anything left with
  # a real otel import is a leak (e.g. introduced by an upstream merge).
  echo "ERROR: real OTel import outside whitelist: $file" >&2
  echo "       rewrite it to github.com/alibaba/loongsuite-go/pkg/go-sdk/... or" >&2
  echo "       add the module to the whitelist in scripts/check_otel_imports.sh" >&2
  status=1
done < <(grep -rl '"go\.opentelemetry\.io' pkg --include='*.go' \
           | grep -v '_test\.go$' || true)

# 2. No go.opentelemetry.io requires in rule go.mod files outside the
#    whitelist (stale requires needlessly raise the MVS floor seen by user
#    builds).
for gomod in $(find pkg/rules -name go.mod); do
  dir="$(dirname "$gomod")"
  if is_whitelisted "$dir"; then
    continue
  fi
  if grep -q 'go\.opentelemetry\.io' "$gomod"; then
    echo "ERROR: stale OTel require in non-whitelisted module: $gomod" >&2
    echo "       run: (cd $dir && go mod edit -droprequire=... && go mod tidy)" >&2
    status=1
  fi
done

if [ "$status" -ne 0 ]; then
  exit 1
fi
echo "otel-isolation check passed"
