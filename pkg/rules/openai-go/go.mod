module github.com/alibaba/loongsuite-go/pkg/rules/openai-go

go 1.25.0

require (
	github.com/alibaba/loongsuite-go/pkg v0.0.0-20260107074919-08c36b668c42
	github.com/openai/openai-go v1.5.0
)

require (
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/go-logr/logr v1.4.4 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/tidwall/gjson v1.14.4 // indirect
	github.com/tidwall/match v1.1.1 // indirect
	github.com/tidwall/pretty v1.2.1 // indirect
	github.com/tidwall/sjson v1.2.5 // indirect
)

replace github.com/alibaba/loongsuite-go => ../../../

replace github.com/alibaba/loongsuite-go/pkg => ../..
