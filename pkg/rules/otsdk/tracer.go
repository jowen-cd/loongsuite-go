// Copyright (c) 2024 Alibaba Group Holding Ltd.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package otsdk

import (
	"context"

	agent_spec_trace "github.com/alibaba/loongsuite-go/pkg/go-sdk/otel/trace"
	spec_trace "go.opentelemetry.io/otel/trace"
	spec_embedded "go.opentelemetry.io/otel/trace/embedded"
)

type appTracer struct {
	spec_embedded.Tracer

	agentTr agent_spec_trace.Tracer
}

var _ spec_trace.Tracer = appTracer{}

func toAppTracer(tracer agent_spec_trace.Tracer) spec_trace.Tracer {
	return appTracer{agentTr: tracer}
}

func (appTr appTracer) Start(ctx context.Context, spanName string, opts ...spec_trace.SpanStartOption) (context.Context, spec_trace.Span) {
	ctx, agentSp := appTr.agentTr.Start(ctx, spanName, toAgentSpanStartOpts(opts...)...)
	// The returned context carries the fork's span under the fork's context
	// key; user code observes it through the SpanFromContext bridge in
	// span_context.go.
	return ctx, toAppSpan(agentSp)
}
