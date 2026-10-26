// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package tracetransform // import "github.com/alibaba/loongsuite-go/pkg/go-sdk/otel/exporters/otlp/otlptrace/internal/tracetransform"

import (
	resourcepb "github.com/alibaba/loongsuite-go/pkg/go-sdk/proto/otlp/resource/v1"

	"github.com/alibaba/loongsuite-go/pkg/go-sdk/otel/sdk/resource"
)

// Resource transforms a Resource into an OTLP Resource.
func Resource(r *resource.Resource) *resourcepb.Resource {
	if r == nil {
		return nil
	}
	return &resourcepb.Resource{Attributes: ResourceAttributes(r)}
}
