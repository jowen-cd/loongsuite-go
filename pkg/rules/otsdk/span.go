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
	agent_spec_trace "github.com/alibaba/loongsuite-go/pkg/go-sdk/otel/trace"
	spec_attribute "go.opentelemetry.io/otel/attribute"
	spec_codes "go.opentelemetry.io/otel/codes"
	spec_trace "go.opentelemetry.io/otel/trace"
	spec_embedded "go.opentelemetry.io/otel/trace/embedded"
)

type appSpan struct {
	spec_embedded.Span

	agentSp agent_spec_trace.Span
}

var _ spec_trace.Span = appSpan{}

func toAppSpan(span agent_spec_trace.Span) spec_trace.Span {
	return appSpan{agentSp: span}
}

func (appSp appSpan) End(options ...spec_trace.SpanEndOption) {
	var opts []agent_spec_trace.SpanEndOption
	if len(options) > 0 {
		config := spec_trace.NewSpanEndConfig(options...)
		if config.Attributes() != nil {
			appSp.agentSp.SetAttributes(toAgentAttributes(config.Attributes()...)...)
		}
		if !config.Timestamp().IsZero() {
			opts = append(opts, agent_spec_trace.WithTimestamp(config.Timestamp()))
		}
	}
	appSp.agentSp.End(opts...)
}

func (appSp appSpan) AddEvent(name string, options ...spec_trace.EventOption) {
	var opts []agent_spec_trace.EventOption
	if len(options) > 0 {
		config := spec_trace.NewEventConfig(options...)
		if config.Attributes() != nil {
			opts = append(opts, agent_spec_trace.WithAttributes(toAgentAttributes(config.Attributes()...)...))
		}
		if config.StackTrace() {
			opts = append(opts, agent_spec_trace.WithStackTrace(true))
		}
		if !config.Timestamp().IsZero() {
			opts = append(opts, agent_spec_trace.WithTimestamp(config.Timestamp()))
		}
	}
	appSp.agentSp.AddEvent(name, opts...)
}

func (appSp appSpan) AddLink(link spec_trace.Link) {
	// The fork's API has no AddLink; links are dropped.
}

func (appSp appSpan) IsRecording() bool {
	return appSp.agentSp.IsRecording()
}

func (appSp appSpan) RecordError(err error, options ...spec_trace.EventOption) {
	var opts []agent_spec_trace.EventOption
	if len(options) > 0 {
		config := spec_trace.NewEventConfig(options...)
		if config.Attributes() != nil {
			opts = append(opts, agent_spec_trace.WithAttributes(toAgentAttributes(config.Attributes()...)...))
		}
		if config.StackTrace() {
			opts = append(opts, agent_spec_trace.WithStackTrace(true))
		}
		if !config.Timestamp().IsZero() {
			opts = append(opts, agent_spec_trace.WithTimestamp(config.Timestamp()))
		}
	}
	appSp.agentSp.RecordError(err, opts...)
}

func (appSp appSpan) SpanContext() spec_trace.SpanContext {
	return toAppSpanContext(appSp.agentSp.SpanContext())
}

func (appSp appSpan) SetStatus(code spec_codes.Code, description string) {
	appSp.agentSp.SetStatus(toAgentCodes(code), description)
}

func (appSp appSpan) SetName(name string) {
	appSp.agentSp.SetName(name)
}

func (appSp appSpan) SetAttributes(kv ...spec_attribute.KeyValue) {
	appSp.agentSp.SetAttributes(toAgentAttributes(kv...)...)
}

func (appSp appSpan) TracerProvider() spec_trace.TracerProvider {
	return toAppTraceProvider(appSp.agentSp.TracerProvider())
}
