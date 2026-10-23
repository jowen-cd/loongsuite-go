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

// Package otsdk bridges the user application's own OpenTelemetry modules to
// the agent's vendored go-sdk fork ("Path A" isolation). The user's OTel
// global entry points are hooked so that every TracerProvider the user code
// observes is an adapter (appTraceProvider/appTracer/appSpan) whose spans
// actually live in the fork's pipeline, and context values are mirrored
// between the two worlds so parents and propagation keep working.
//
// The hooks only rely on OTel API surface stable since v1.20.0, so this rule
// applies to a wide version range and never constrains the user's choice of
// go.opentelemetry.io/otel version: the application's version wins in MVS.

package otsdk

import (
	agent_spec_trace "github.com/alibaba/loongsuite-go/pkg/go-sdk/otel/trace"
	spec_trace "go.opentelemetry.io/otel/trace"
	spec_embedded "go.opentelemetry.io/otel/trace/embedded"
)

type appTraceProvider struct {
	spec_embedded.TracerProvider

	agentTp agent_spec_trace.TracerProvider
}

var _ spec_trace.TracerProvider = appTraceProvider{}

func toAppTraceProvider(provider agent_spec_trace.TracerProvider) spec_trace.TracerProvider {
	return appTraceProvider{agentTp: provider}
}

func (appTp appTraceProvider) Tracer(name string, options ...spec_trace.TracerOption) spec_trace.Tracer {
	return toAppTracer(appTp.agentTp.Tracer(name))
}
