module github.com/alibaba/loongsuite-go/pkg/rules/ollama

go 1.25.0

require (
	github.com/alibaba/loongsuite-go/pkg v0.0.0
	github.com/ollama/ollama v0.3.14
)

require (
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/go-logr/logr v1.4.4 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/google/uuid v1.6.0 // indirect
	golang.org/x/sys v0.47.0 // indirect
)

replace github.com/alibaba/loongsuite-go/pkg => ../../../pkg
