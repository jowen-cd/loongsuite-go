// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

// Package internal provides internal functionality for the prometheus
// package.
package internal // import "github.com/alibaba/loongsuite-go/pkg/go-sdk/otel/exporters/prometheus/internal"

//go:generate gotmpl --body=../../../internal/shared/counter/counter.go.tmpl "--data={ \"pkg\": \"github.com/alibaba/loongsuite-go/pkg/go-sdk/otel/exporters/prometheus/internal/counter\" }" --out=counter/counter.go
//go:generate gotmpl --body=../../../internal/shared/counter/counter_test.go.tmpl "--data={}" --out=counter/counter_test.go

//go:generate gotmpl --body=../../../internal/shared/x/x.go.tmpl "--data={ \"pkg\": \"github.com/alibaba/loongsuite-go/pkg/go-sdk/otel/exporters/prometheus\" }" --out=x/x.go
//go:generate gotmpl --body=../../../internal/shared/x/x_test.go.tmpl "--data={}" --out=x/x_test.go
