// rules/go/tooling.md: the go line is the newest patch release; tools run from tools/go.mod

module example.com/daemon

go 1.26.10

require (
	github.com/caarlos0/env/v11 v11.4.1
	github.com/stretchr/testify v1.12.1
	go.uber.org/goleak v1.3.0
	golang.org/x/sync v0.24.0
	google.golang.org/grpc v1.85.0
	google.golang.org/protobuf v1.36.12
)

require (
	go.yaml.in/yaml/v3 v3.0.5 // indirect
	golang.org/x/net v0.60.0 // indirect
	golang.org/x/sys v0.48.0 // indirect
	golang.org/x/text v0.42.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20260817212433-ac3dfec99bb1 // indirect
)
