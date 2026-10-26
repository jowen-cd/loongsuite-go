module github.com/alibaba/loongsuite-go/pkg/rules/streadway-amqp/producer

go 1.24.0

toolchain go1.24.13

replace github.com/alibaba/loongsuite-go/pkg => ../../../../pkg

require (
	github.com/alibaba/loongsuite-go/pkg v0.0.0-00010101000000-000000000000
	github.com/streadway/amqp v1.0.0
)

require (
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/go-logr/logr v1.4.3 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
)
