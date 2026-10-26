// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package tracetransform // import "github.com/alibaba/loongsuite-go/pkg/go-sdk/otel/exporters/otlp/otlptrace/internal/tracetransform"

import (
	commonpb "github.com/alibaba/loongsuite-go/pkg/go-sdk/proto/otlp/common/v1"

	"github.com/alibaba/loongsuite-go/pkg/go-sdk/otel/sdk/instrumentation"
)

func InstrumentationScope(il instrumentation.Scope) *commonpb.InstrumentationScope {
	if il == (instrumentation.Scope{}) {
		return nil
	}
	return &commonpb.InstrumentationScope{
		Name:       il.Name,
		Version:    il.Version,
		Attributes: Iterator(il.Attributes.Iter()),
	}
}
