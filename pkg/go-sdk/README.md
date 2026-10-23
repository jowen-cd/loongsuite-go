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
