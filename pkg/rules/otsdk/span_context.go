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
	_ "unsafe"

	"github.com/alibaba/loongsuite-go/pkg/api"
	tracex "github.com/alibaba/loongsuite-go/pkg/go-sdk/otel/trace"
	spec_trace "go.opentelemetry.io/otel/trace"
)

// Context mirroring between the user's OTel and the fork.
//
// The fork stores its current span in contexts under its own (fork) key.
// appTracer.Start writes it, and these hooks make the user's
// trace.SpanFromContext read it and trace.ContextWithSpanContext write it,
// so parent-child links and W3C propagation through user-side
// instrumentations (otelgin, otelgrpc, ...) keep working without touching
// the propagators themselves.

//go:linkname spanFromContextOnEnter go.opentelemetry.io/otel/trace.spanFromContextOnEnter
func spanFromContextOnEnter(call api.CallContext, ctx context.Context) {
	if ctx == nil {
		return
	}
	sp := ctx.Value(tracex.CurrentSpanKey)
	if sp == nil {
		return
	}
	if ss, ok := sp.(tracex.Span); ok {
		call.SetData(toAppSpan(ss))
	}
}

//go:linkname spanFromContextOnExit go.opentelemetry.io/otel/trace.spanFromContextOnExit
func spanFromContextOnExit(call api.CallContext, span spec_trace.Span) {
	if call.GetData() == nil {
		return
	}
	call.SetReturnVal(0, call.GetData().(spec_trace.Span))
}

//go:linkname contextWithSpanContextOnEnter go.opentelemetry.io/otel/trace.contextWithSpanContextOnEnter
func contextWithSpanContextOnEnter(call api.CallContext, parent context.Context, rsc spec_trace.SpanContext) {
	if parent == nil {
		parent = context.Background()
	}
	sCtx := toAgentSpanContext(rsc).WithRemote(true)
	ctx := tracex.ContextWithRemoteSpanContext(parent, sCtx)
	call.SetParam(0, ctx)
	call.SetData(ctx)
	call.SetSkipCall(true)
}

//go:linkname contextWithSpanContextOnExit go.opentelemetry.io/otel/trace.contextWithSpanContextOnExit
func contextWithSpanContextOnExit(call api.CallContext, ctx context.Context) {
	if call.GetData() == nil {
		return
	}
	call.SetReturnVal(0, call.GetData().(context.Context))
}
