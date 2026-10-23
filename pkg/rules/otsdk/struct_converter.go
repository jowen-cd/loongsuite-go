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
	"unicode/utf8"

	agent_spec_attribute "github.com/alibaba/loongsuite-go/pkg/go-sdk/otel/attribute"
	agent_spec_codes "github.com/alibaba/loongsuite-go/pkg/go-sdk/otel/codes"
	agent_spec_trace "github.com/alibaba/loongsuite-go/pkg/go-sdk/otel/trace"
	spec_attribute "go.opentelemetry.io/otel/attribute"
	spec_codes "go.opentelemetry.io/otel/codes"
	spec_trace "go.opentelemetry.io/otel/trace"
)

// The fork and the user's OTel modules are distinct packages with identical
// data shapes; every value crossing the bridge is converted field by field.

func toAppSpanContext(sc agent_spec_trace.SpanContext) spec_trace.SpanContext {
	tsStr := sc.TraceState().String()
	ts, _ := spec_trace.ParseTraceState(tsStr)
	return spec_trace.NewSpanContext(spec_trace.SpanContextConfig{
		TraceID:    [16]byte(sc.TraceID()),
		SpanID:     [8]byte(sc.SpanID()),
		TraceFlags: spec_trace.TraceFlags(byte(sc.TraceFlags())),
		TraceState: ts,
		Remote:     sc.IsRemote(),
	})
}

func toAgentSpanContext(sc spec_trace.SpanContext) agent_spec_trace.SpanContext {
	tsStr := sc.TraceState().String()
	ts, _ := agent_spec_trace.ParseTraceState(tsStr)
	return agent_spec_trace.NewSpanContext(agent_spec_trace.SpanContextConfig{
		TraceID:    [16]byte(sc.TraceID()),
		SpanID:     [8]byte(sc.SpanID()),
		TraceFlags: agent_spec_trace.TraceFlags(byte(sc.TraceFlags())),
		TraceState: ts,
		Remote:     sc.IsRemote(),
	})
}

func toAgentCodes(code spec_codes.Code) agent_spec_codes.Code {
	switch code {
	case spec_codes.Error:
		return agent_spec_codes.Error
	case spec_codes.Ok:
		return agent_spec_codes.Ok
	default:
		return agent_spec_codes.Unset
	}
}

func toAgentAttribute(attr spec_attribute.KeyValue) agent_spec_attribute.KeyValue {
	agentK := string(attr.Key)

	switch attr.Value.Type() {
	case spec_attribute.BOOL:
		return agent_spec_attribute.Bool(agentK, attr.Value.AsBool())
	case spec_attribute.BOOLSLICE:
		return agent_spec_attribute.BoolSlice(agentK, attr.Value.AsBoolSlice())
	case spec_attribute.INT64:
		return agent_spec_attribute.Int64(agentK, attr.Value.AsInt64())
	case spec_attribute.INT64SLICE:
		return agent_spec_attribute.Int64Slice(agentK, attr.Value.AsInt64Slice())
	case spec_attribute.FLOAT64:
		return agent_spec_attribute.Float64(agentK, attr.Value.AsFloat64())
	case spec_attribute.FLOAT64SLICE:
		return agent_spec_attribute.Float64Slice(agentK, attr.Value.AsFloat64Slice())
	case spec_attribute.STRING:
		val := attr.Value.AsString()
		if !utf8.ValidString(val) {
			return agent_spec_attribute.String(agentK, "not_utf8")
		}
		return agent_spec_attribute.String(agentK, val)
	case spec_attribute.STRINGSLICE:
		return agent_spec_attribute.StringSlice(agentK, attr.Value.AsStringSlice())
	default:
		return agent_spec_attribute.KeyValue{}
	}
}

func toAgentAttributes(attrs ...spec_attribute.KeyValue) []agent_spec_attribute.KeyValue {
	result := make([]agent_spec_attribute.KeyValue, 0, len(attrs))
	for _, attr := range attrs {
		agentAttr := toAgentAttribute(attr)
		if agentAttr.Valid() {
			result = append(result, agentAttr)
		}
	}
	return result
}

func toAgentSpanStartOpts(opts ...spec_trace.SpanStartOption) []agent_spec_trace.SpanStartOption {
	agentOpts := make([]agent_spec_trace.SpanStartOption, 0, len(opts))
	config := spec_trace.NewSpanStartConfig(opts...)

	if config.Attributes() != nil && len(config.Attributes()) > 0 {
		agentOpts = append(agentOpts, agent_spec_trace.WithAttributes(toAgentAttributes(config.Attributes()...)...))
	}
	if !config.Timestamp().IsZero() {
		agentOpts = append(agentOpts, agent_spec_trace.WithTimestamp(config.Timestamp()))
	}
	if config.NewRoot() {
		agentOpts = append(agentOpts, agent_spec_trace.WithNewRoot())
	}
	if config.SpanKind() == spec_trace.SpanKindClient {
		agentOpts = append(agentOpts, agent_spec_trace.WithSpanKind(agent_spec_trace.SpanKindClient))
	} else if config.SpanKind() == spec_trace.SpanKindServer {
		agentOpts = append(agentOpts, agent_spec_trace.WithSpanKind(agent_spec_trace.SpanKindServer))
	} else if config.SpanKind() == spec_trace.SpanKindProducer {
		agentOpts = append(agentOpts, agent_spec_trace.WithSpanKind(agent_spec_trace.SpanKindProducer))
	} else if config.SpanKind() == spec_trace.SpanKindConsumer {
		agentOpts = append(agentOpts, agent_spec_trace.WithSpanKind(agent_spec_trace.SpanKindConsumer))
	} else if config.SpanKind() == spec_trace.SpanKindInternal {
		agentOpts = append(agentOpts, agent_spec_trace.WithSpanKind(agent_spec_trace.SpanKindInternal))
	} else {
		agentOpts = append(agentOpts, agent_spec_trace.WithSpanKind(agent_spec_trace.SpanKindUnspecified))
	}
	return agentOpts
}
