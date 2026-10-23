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
	_ "unsafe"

	"github.com/alibaba/loongsuite-go/pkg/api"
	agent_otel "github.com/alibaba/loongsuite-go/pkg/go-sdk/otel"
	spec_trace "go.opentelemetry.io/otel/trace"
)

// Bridges of the user OTel global tracer provider entry points.
//
// GetTracerProvider: every call returns an adapter wrapping the fork's
// global provider (registered by the agent's otel_setup init), so all spans
// user code creates through the public OTel API actually live in the fork's
// pipeline and are exported by the agent's exporters.
//
// SetTracerProvider: the call is skipped; the user's own provider never
// becomes the global one. Returning an error or registering a no-op would
// break user code that depends on the provider it passed in, but that is
// the documented behavior of agent-managed telemetry.

//go:linkname getTracerProviderOnEnter go.opentelemetry.io/otel.getTracerProviderOnEnter
func getTracerProviderOnEnter(call api.CallContext) {
}

//go:linkname getTracerProviderOnExit go.opentelemetry.io/otel.getTracerProviderOnExit
func getTracerProviderOnExit(call api.CallContext, tp spec_trace.TracerProvider) {
	agentTraceProvider := agent_otel.GetTracerProvider()
	call.SetReturnVal(0, toAppTraceProvider(agentTraceProvider))
}

//go:linkname setTracerProviderOnEnter go.opentelemetry.io/otel.setTracerProviderOnEnter
func setTracerProviderOnEnter(call api.CallContext, tp spec_trace.TracerProvider) {
	call.SetSkipCall(true)
}

//go:linkname setTracerProviderOnExit go.opentelemetry.io/otel.setTracerProviderOnExit
func setTracerProviderOnExit(call api.CallContext) {
}
