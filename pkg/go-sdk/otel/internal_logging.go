// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package otel // import "github.com/alibaba/loongsuite-go/pkg/go-sdk/otel"

import (
	"github.com/go-logr/logr"

	"github.com/alibaba/loongsuite-go/pkg/go-sdk/otel/internal/global"
)

// SetLogger configures the logger used internally to opentelemetry.
func SetLogger(logger logr.Logger) {
	global.SetLogger(logger)
}
