module github.com/alibaba/loongsuite-go/pkg/rules/segmentio-kafka-go

go 1.25.0

replace github.com/alibaba/loongsuite-go/pkg => ../../../pkg

require (
	github.com/alibaba/loongsuite-go/pkg v0.0.0-00010101000000-000000000000
	github.com/segmentio/kafka-go v0.4.0
)

require (
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/go-logr/logr v1.4.4 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/golang/snappy v0.0.1 // indirect
	github.com/google/uuid v1.6.0 // indirect
	github.com/klauspost/compress v1.18.0 // indirect
	github.com/pierrec/lz4 v2.0.5+incompatible // indirect
	golang.org/x/sys v0.47.0 // indirect
)
