![](docs/public/anim-logo.svg)

[![](https://shields.io/badge/-Docs-blue?logo=readthedocs)](https://alibaba.github.io/loongsuite-go/)  &nbsp;
[![](https://shields.io/badge/-商业版-blue?logo=alibabacloud)](https://help.aliyun.com/zh/arms/application-monitoring/getting-started/monitoring-the-golang-applications) &nbsp;

**Loongsuite Go Agent** provides an automatic solution for Golang applications that want to
leverage OpenTelemetry to enable effective observability. No code changes are
required in the target application, the instrumentation is done at compile
time. Simply adding `otel` prefix to `go build` to get started :rocket:

# Installation

> [!IMPORTANT]
> Requires Go 1.25+ for both the tool and the instrumented application. See [compatibility](docs/user/compatibility.md).

### Prebuilt Binaries

- [![Download](https://shields.io/badge/-Linux_AMD64-blue?logo=ubuntu)](https://github.com/alibaba/loongsuite-go/releases/latest/download/otel-linux-amd64)
- [![Download](https://shields.io/badge/-Linux_ARM64-blue?logo=ubuntu)](https://github.com/alibaba/loongsuite-go/releases/latest/download/otel-linux-arm64)
- [![Download](https://shields.io/badge/-macOS_AMD64-blue?logo=apple)](https://github.com/alibaba/loongsuite-go/releases/latest/download/otel-darwin-amd64)
- [![Download](https://shields.io/badge/-macOS_ARM64-blue?logo=apple)](https://github.com/alibaba/loongsuite-go/releases/latest/download/otel-darwin-arm64)
- [![Download](https://shields.io/badge/-Windows_AMD64-blue?logo=wine)](https://github.com/alibaba/loongsuite-go/releases/latest/download/otel-windows-amd64.exe)

### Install via Bash
For Linux and macOS, the following script installs `otel` to `/usr/local/bin/otel` by default:
```bash
$ curl -fsSL https://cdn.jsdelivr.net/gh/alibaba/loongsuite-go@main/install.sh | sudo bash
```

### Build from Source

```bash
$ make         # build only
$ make install # build and install
```

# Getting Started

Make sure the tool is installed:
```bash
$ # You may use "otel-linux-amd64" instead of "otel"
$ otel version
```

Just adding `otel` prefix to `go build` to build your project:

```bash
$ otel go build
$ otel go build -o app cmd/app
$ otel go build -gcflags="-m" cmd/app
```

That's the whole process! The tool will automatically instrument your code with OpenTelemetry, and you can start to observe your application. :telescope:

The detailed usage of `otel` tool can be found in [**Usage**](./docs/user/config.md).

> [!NOTE]
> If you find any compilation failures while `go build` works, it's likely a bug.
> Please feel free to file a bug
> at [GitHub Issues](https://github.com/alibaba/loongsuite-go/issues)
> to help us enhance this project.

# Examples

- [demo](example/demo) - End-to-end example with OpenTelemetry tracing and metrics
- [zap logging](example/log) - Auto-instrumentation for `go.uber.org/zap` logging
- [benchmark](example/benchmark) - Performance testing and overhead measurement
- [sql injection](example/sqlinject) - Custom code injection for SQL injection detection
- [nethttp](example/nethttp) - HTTP monitoring with request/response instrumentation
- [kratos-demo](example/kratos-demo) - Integration with the Kratos framework
- [kafka-demo](example/kafka-demo) - Kafka consumer message monitoring

# Releasing (fork)

发布一个新版本只需要一条命令：

```bash
./scripts/release.sh v1.15.0-fork
```

这条命令背后做了几件事：先把工作区切到指定的 tag（保证编译出来的东西就是这个 tag 的内容，不会出现目录叫 v1.15.0-fork、二进制却是别的代码的情况），然后跑 `make all` 一次性编出五个平台的二进制（darwin/amd64、darwin/arm64、linux/amd64、linux/arm64、windows/amd64，命名统一为 `otel-fork-<os>-<arch>`），连同 SHA256SUMS 一起放到 `dist/<tag>/` 下。如果本地配好了 Nexus 的账号信息，还会把这一目录整个传上去，并把 `latest/` 刷成同一份内容。全部做完后自动切回你原来所在的分支，不用手动收拾。

前提是先准备一份 Nexus 配置。把 `scripts/nexus.conf.example` 复制成 `scripts/.nexus.conf`，填上服务器地址、仓库名、上传根路径和账号——密码不要写进文件，执行前 `export NEXUS_PASS=xxx` 即可（`.nexus.conf` 已在 .gitignore 里，不会误提交）。没配密码时脚本只编译不上传，所以日常构建也可以放心用。

几个常用的变化：

```bash
./scripts/release.sh                          # 不带参数时，要求当前 HEAD 正好在某个 tag 上
./scripts/release.sh --no-upload v1.15.0-fork # 只编译，不上传
./scripts/release.sh --no-latest v1.15.0-fork # 上传但不刷新 latest/
```

上传走的是 Nexus 的 raw 仓库 REST 接口（`PUT /repository/...`，HTTP Basic Auth 每次请求带上账号密码，没有单独的登录这一步）。有个曾经踩过的坑值得记一下：二进制文件必须显式带 `Content-Type: application/octet-stream`，否则 Nexus 前面的代理层会直接回 500——脚本里已经处理了，但如果哪天有人手写 curl 上传二进制遇到 500，先想起这一条。

上传完成后可以这样核对：

```bash
curl -s 'https://<nexus>/service/rest/v1/assets?repository=<repo>' | grep -o '<path>/<tag>/[^"]*' | sort
```

或者直接在浏览器里打开 Nexus 的 browse 页面看那个 tag 目录下是不是六个文件、回环下载一个比对 SHA256SUMS 里的哈希。旧版本的同名文件 PUT 会直接覆盖；文件名不同的旧残留（比如历史上手传的文件）不会自动清理，需要删的话在 Nexus 页面上删或者用 `curl -X DELETE`。

# Supported Libraries
<details>
 <summary>List of Supported Libraries</summary>

| Library            | Repository Url                                  | Min Version | Max Version |
|--------------------|-------------------------------------------------|-------------|-------------|
| adk-go             | https://pkg.go.dev/google.golang.org/adk        | v0.2.0      | -           |
| amqp091            | https://github.com/rabbitmq/amqp091-go          | v1.10.0     | -           |
| ants               | https://github.com/panjf2000/ants               | v1.1.0      | -           |
| anthropic-sdk-go   | https://github.com/anthropics/anthropic-sdk-go  | v1.25.0     | -           |
| asynq              | https://github.com/hibiken/asynq                | v0.23.0     | -           |
| aws-sdk-go         | https://github.com/aws/aws-sdk-go               | v1.55.5     | -           |
| clickhouse/v2      | https://github.com/ClickHouse/clickhouse-go/v2  | v2.13.0     | -           |
| cron               | https://github.com/robfig/cron/v3               | v3.0.0      | -           |
| database/sql       | https://pkg.go.dev/database/sql                 | -           | -           |
| deepseek           | https://github.com/cohesion-org/deepseek-go     | v1.3.0      | -           |
| dubbo-go           | https://github.com/apache/dubbo-go              | v3.3.0      | -           |
| echo               | https://github.com/labstack/echo                | v4.0.0      | -           |
| elasticsearch      | https://github.com/elastic/go-elasticsearch     | v8.4.0      | v8.15.1     |
| eino               | https://github.com/cloudwego/eino               | v0.7.13     | -           |
| fasthttp           | https://github.com/valyala/fasthttp             | v1.45.0     | -           |
| fiber              | https://github.com/gofiber/fiber                | v2.43.0     | v2.53.0     |
| fiber/v3           | https://github.com/gofiber/fiber/v3             | v3.0.0      | -           |
| franz-go           | https://github.com/twmb/franz-go                | v1.18.0     | -           |
| gin                | https://github.com/gin-gonic/gin                | v1.7.0      | v1.10.2     |
| go-kit/log         | https://github.com/go-kit/log                   | v0.1.0      | v0.2.2      |
| go-micro           | https://github.com/micro/go-micro               | v5.0.0      | v5.3.1      |
| go-openai          | https://github.com/sashabaranov/go-openai       | v1.30.0     | -           |
| gocql              | https://github.com/gocql/gocql                  | v1.3.0      | v1.7.1      |
| google-genai       | https://pkg.go.dev/google.golang.org/genai      | v1.30.0     | -           |
| gopg               | https://github.com/go-pg/pg                     | v10.10.0    | v10.14.1    |
| gorestful/v3       | https://github.com/emicklei/go-restful/v3       | v3.7.0      | v3.12.2     |
| gorm               | https://github.com/go-gorm/gorm                 | v1.22.0     | v1.25.10    |
| gorilla/mux        | https://github.com/gorilla/mux                  | v1.3.0      | v1.8.2      |
| grpc               | https://google.golang.org/grpc                  | v1.44.0     | -           |
| hertz              | https://github.com/cloudwego/hertz              | v0.9.0      | -           |
| ibm-sarama         | https://github.com/IBM/sarama                   | v1.40.0     | -           |
| iris               | https://github.com/kataras/iris                 | v12.2.0     | v12.2.12    |
| k8s client-go      | https://github.com/kubernetes/client-go         | v0.33.3     | -           |
| kitex              | https://github.com/cloudwego/kitex              | v0.5.1      | -           |
| kratos             | https://github.com/go-kratos/kratos             | v2.6.3      | -           |
| kratos/v3          | https://github.com/go-kratos/kratos/v3          | v3.0.0      | -           |
| langchaingo        | https://github.com/tmc/langchaingo              | v0.1.13     | -           |
| log                | https://pkg.go.dev/log                          | -           | -           |
| logrus             | https://github.com/sirupsen/logrus              | v1.5.0      | -           |
| mcp                | https://github.com/mark3labs/mcp-go             | v0.20.0     | -           |
| mcp go-sdk         | https://github.com/modelcontextprotocol/go-sdk  | v0.7.0      | -           |
| meguminnnnnnnnn/go-openai | https://github.com/meguminnnnnnnnn/go-openai    | -           | -           |
| mongodb            | https://github.com/mongodb/mongo-go-driver      | v1.11.1     | v1.15.2     |
| mqtt               | https://github.com/mochi-mqtt/server            | v2.6.4      | -           |
| neo4j              | https://github.com/neo4j/neo4j-go-driver        | v6.0.0      | -           |
| nacos              | https://github.com/nacos-group/nacos-sdk-go/v2  | v2.0.0      | v2.3.0      |
| net/http           | https://pkg.go.dev/net/http                     | -           | -           |
| new-api            | https://github.com/QuantumNous/new-api          | -           | -           |
| ollama             | https://github.com/ollama/ollama                | v0.3.14     | -           |
| openai-go          | https://github.com/openai/openai-go             | v1.5.0      | -           |
| redigo             | https://github.com/gomodule/redigo              | v1.9.0      | -           |
| redis (go-redis)   | https://github.com/redis/go-redis               | v9.0.5      | -           |
| redis v8           | https://github.com/go-redis/redis/v8            | v8.11.0     | v8.11.6     |
| rocketmq           | https://github.com/apache/rocketmq-client-go/v2 | v2.0.0      | -           |
| rpcx               | https://github.com/smallnest/rpcx               | v1.6.2      | -           |
| rueidis            | https://github.com/redis/rueidis                | v1.0.30     | -           |
| segmentio/kafka-go | https://github.com/segmentio/kafka-go           | v0.4.0      | -           |
| sentinel           | https://github.com/alibaba/sentinel-golang      | v1.0.4      | -           |
| shopify-sarama     | https://github.com/Shopify/sarama               | v1.22.0     | -           |
| slog               | https://pkg.go.dev/log/slog                     | -           | -           |
| sqlx               | https://github.com/jmoiron/sqlx                 | v1.3.0      | v1.4.1      |
| streadway-amqp     | https://github.com/streadway/amqp               | v1.0.0      | -           |
| trpc-agent-go      | https://github.com/trpc-group/trpc-agent-go     | v0.1.0      | -           |
| trpc-go            | https://github.com/trpc-group/trpc-go           | v1.0.0      | -           |
| zap                | https://go.uber.org/zap                  | v1.20.0     | v1.27.1     |
| zerolog            | https://github.com/rs/zerolog                   | v1.10.0     | v1.34.1     |

</details>

We are progressively open-sourcing the libraries we have supported, and your contributions are <kbd>Very Welcome</kbd>

> [!IMPORTANT]
> The framework you expected is not in the list? Don't worry, you can easily inject your code into any frameworks/libraries that are not officially supported.
>
> Please refer to [this document](./docs/dev/overview.md) to get started.

# Community

This project has been contributed upstream to the OpenTelemetry community and successfully incubated the official [opentelemetry-go-compile-instrumentation](https://github.com/open-telemetry/opentelemetry-go-compile-instrumentation) project.

Join our [DingTalk group](https://qr.dingtalk.com/action/joingroup?code=v1,k1,mexukXI88tZ1uiuLYkKhdaETUx/K59ncyFFFG5Voe9s=&_dt_no_comment=1&origin=11) or scan the QR codes below.

| LoongCollector SIG | LoongSuite Python SIG | LoongSuite Go SIG | LoongSuite Java SIG |
|----|----|----|----|
| <img src="docs/_assets/img/loongcollector-sig-dingtalk.png" height="120"> | <img src="docs/_assets/img/loongsuite-python-sig-dingtalk.jpg" height="120"> | <img src="docs/_assets/img/loongsuite-go-sig-dingtalk.png" height="120"> | <img src="docs/_assets/img/loongsuite-java-sig-dingtalk.jpg" height="120"> |

# Star History

<img src="https://star-history.dera.page/svg?repos=alibaba/loongsuite-go&type=Date" height="200" />
