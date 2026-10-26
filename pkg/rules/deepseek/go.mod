module github.com/alibaba/loongsuite-go/pkg/rules/deepseek

go 1.25.0

require (
	github.com/alibaba/loongsuite-go/pkg v0.0.0-20260107074919-08c36b668c42
	github.com/cohesion-org/deepseek-go v1.3.0
)

require (
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/go-logr/logr v1.4.4 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/joho/godotenv v1.5.1 // indirect
	github.com/ollama/ollama v0.6.5 // indirect
)

replace github.com/alibaba/loongsuite-go => ../../../

replace github.com/alibaba/loongsuite-go/pkg => ../..
