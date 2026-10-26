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

// Package main is a gin demo pinned to a LOW OpenTelemetry version (v1.31.0),
// below the agent's GLS minimum (v1.39.0). It verifies the whitelist floor
// behavior of the fork: building with otel-fork raises the resolved otel
// version to the floor (the max otel require across the whitelisted rule
// modules), because the GLS hooks can only be injected into otel/sdk >=
// v1.39.0. scripts/sync_upstream.sh builds this demo on every upstream sync
// and asserts the resolved version (>= v1.39.0, warning above v1.40.0).
package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

func main() {
	// The user's own OTel setup. otel.SetTracerProvider is bridged by the
	// agent (agent-managed telemetry): spans created through the global API
	// live in the agent's pipeline.
	tp := sdktrace.NewTracerProvider()
	defer func() { _ = tp.Shutdown(context.Background()) }()
	otel.SetTracerProvider(tp)

	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())

	r.GET("/hello/:name", func(c *gin.Context) {
		_, span := otel.Tracer("otel-low-demo").Start(c.Request.Context(), "hello")
		defer span.End()
		c.JSON(http.StatusOK, gin.H{"hello": c.Param("name")})
	})

	addr := ":8080"
	if p := os.Getenv("DEMO_ADDR"); p != "" {
		addr = p
	}
	log.Printf("listening on %s", addr)
	_ = r.Run(addr)
}
