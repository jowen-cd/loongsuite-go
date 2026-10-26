// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package otel // import "github.com/alibaba/loongsuite-go/pkg/go-sdk/otel"

import (
	"github.com/alibaba/loongsuite-go/pkg/go-sdk/otel/internal/global"
	"github.com/alibaba/loongsuite-go/pkg/go-sdk/otel/propagation"
)

// GetTextMapPropagator returns the global TextMapPropagator. If none has been
// set, a No-Op TextMapPropagator is returned.
func GetTextMapPropagator() propagation.TextMapPropagator {
	return global.TextMapPropagator()
}

// SetTextMapPropagator sets propagator as the global TextMapPropagator.
func SetTextMapPropagator(propagator propagation.TextMapPropagator) {
	global.SetTextMapPropagator(propagator)
}
