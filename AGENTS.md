# AGENTS.md — loongsuite-go fork 工作上下文

本文件是本 fork 仓库（`internal-otelsdk` 分支）的工作上下文，供 agent 与协作者快速建立
认知。对外介绍见 `overview` 分支的 README（含图解）。

## 项目概览

上游 loongsuite-go 是阿里开源的编译期 OpenTelemetry Go 自动埋点工具：目标应用零代码改动，
在 `go build` 前加 `otel-fork` 前缀即可完成插桩。要求 Go 1.25+。

仓库布局：`pkg/`（注入到用户项目的 agent 模块：`api` / `core` / `inst-api` /
`inst-api-semconv` / `rules` / `sdkconfig` / `testaccess` / `go-sdk`）、`tool/`（构建工具
本体）、`util-genai/`、`example/`（含版本矩阵 demo）、`test/`、`scripts/`、`docs/`。

## 分支与发布策略

- remote：`origin` = `jowen-cd/loongsuite-go`（本 fork），`upstream` =
  `alibaba/loongsuite-go`（上游）。
- `main` 与全部上游 tag **严格镜像上游，零本地改动**。同步只用
  `git fetch upstream && git merge --ff-only upstream/main`（sync_upstream.sh stage 1 会用
  `git fetch upstream main:main` 实现同样的 ff-only 语义）。
- 所有 fork 定制（Path A 代码、本文件等元文件）都在集成分支 **`internal-otelsdk`** 上。
- 上游发布新 tag 后：`./scripts/sync_upstream.sh <tag> --tag` 走完整流程（见下），验证通过
  后打 **`vX.Y.Z-fork`** annotated tag（message 嵌上游短哈希；发布后不可移动）。tag 一律
  本地打好、人工验证后手动 push。
- 发布形态：**仅预编译二进制**。module path 保持 `github.com/alibaba/loongsuite-go` 不变，
  不走 GOPROXY / `go install`（module path 与实际托管仓库不一致会被模块校验拒绝，这是有意
  接受的取舍）。
- `overview` 分支：orphan 纯文档分支（对外 README），**永不参与 merge/sync**。
- 本地产物（`otel-fork` 二进制、`.otel-build/`、`.zcode/`）不入库（.gitignore 已覆盖）。

## 兄弟仓库：~/personal/loongsuite-go-agent（历史参考）

同一项目的旧工作副本，Path A 可行性验证在此完成（`path-a-fork` 分支，基于 v1.13.0 合并
v1.15.0）。**其结论已全部移植到本仓库**，仓库使命已完成，仅作历史对照参考。注意其
`path-a-fork` 分支因 `.gitignore` 缺陷不自包含（`pkg/go-sdk/otel/` 曾被无锚定的 `otel`
规则忽略而未入库），本仓库已修复该问题。

## Path A 架构要点（双世界隔离）

核心：注入用户项目的 `pkg` 模块对 `go.opentelemetry.io/*` 保持零直接依赖；用户应用自己的
otel 版本不受工具钉扎。

- **`pkg/go-sdk/`** 是路径重写的 OTel Go fork（vendored 基线 v1.40.0；otel/sdk 全家 v1.40.0、
  prometheus v0.61.0、contrib runtime v0.65.0、proto/otlp v1.9.0、auto/sdk v1.2.1）。禁止手改，
  刷新用 `scripts/vendor_otel_fork.sh`（版本在脚本内钉死，机械重跑）。
- **两个"版本"要分清**：vendored 基线是工具内部管线用的（不参与用户 MVS，升级对用户无感）；
  **用户地板**是白名单规则的 otel require（参与用户 MVS，应保持低位）。
- **白名单**（17 组规则，允许 import 真实 otel，是 GLS/桥接边界代码）：otsdk、otel-context、
  otel-sdk/*、echo、gin、go-kit-log、golog、goslog、gorestful、hertz、iris、logrus、mux、
  zap、zerolog、gomicro、aws-sdk-go。其余规则模块零 otel（import 与 require 都不能出现）。
- **otsdk 桥**：hook 用户全局 API——`GetTracerProvider` 返回包装工具管线的适配器、
  `SetTracerProvider` 跳过（agent-managed telemetry）。仅依赖 v1.20.0 起稳定的 API 面。
- **GLS 设计**：钩子（`otel-sdk/trace/v1_39_0` 等规则，版本区间 `[1.39.0,)`）注入用户
  `sdk/trace` 包实现 goroutine 级 span 存取；框架/日志规则（gin 等）消费这些注入 API 读写
  用户 span 对象（`http.route` 即来源于 gin 规则的 `LocalRootSpanFromGLS().SetName(路由)`）。
  因此白名单必须 import 真实 otel（类型同一性），这是上游架构，不是本 fork 的选择。
- **MVS 语义**：用户 otel ≥ 地板时用户版本胜出；低于地板被抬到地板（功能性必需：GLS 钩子
  只能注入 otel/sdk ≥ v1.39.0）。规则引擎按用户解析版本匹配版本化规则（如 `v1_39_0`）。
- **防回归守卫**：`scripts/check_otel_imports.sh`（`make lint-otel`，挂在 `package-pkg`
  前置）。扫描非白名单的真实 otel import 与 otel require。
- **架构对比结论**：instgo（商业版）是接管模型（规则用内置 otel 自建 span，数据进 ARMS）；
  上游开源版是协作模型（GLS + 白名单，协作用户 span 树）。本 fork 继承协作模型，不重写。

## 同步流程：scripts/sync_upstream.sh

用法：`./scripts/sync_upstream.sh <tag> [--tag]`。幂等可重入（冲突解完重跑自动续），
**永不自动 push、不自动改 import**。六阶段：

1. 镜像 main（fetch upstream，ff-only）
2. 合并 tag：`pkg/rules/**/go.mod` 冲突自动解（非白名单取上游再删 otel require；白名单
   取上游保留；`pkg/go.sum` 取上游；`pkg/go.mod` 取上游 + 删 otel + tidy）；代码文件冲突
   停下人工解（原则：除 import 重写与 update.go 的 otelDeps 阉割外取上游）
3. 守卫 + 自动清扫 stale otel require；漏网 import 列人工清单
4. `make package-pkg` + `make build`
5. 版本矩阵回归（见下）
6. 打 fork tag（`--tag` 时）

**版本矩阵**（stage 5，从产物二进制的 `go version -m` 元数据读实际链接版本——工具成功后
会还原 go.mod，事后 `go list -m` 读到的是 pin 不是真相）：

| demo | 断言 |
|------|------|
| `example/grpc-demo`（无 otel） | 注入 otel == 工具地板（stdlib log → golog 级联是上游设计） |
| `example/otel-low-demo`（v1.31.0） | 抬到 ≥ v1.39.0；> v1.40.0 软警告 |
| `example/otel-high-demo`（最新） | 用户版本胜出；地板追上 pin 时自动 bump 到最新 |

## 第二阶段经验（踩坑记录）

- **`output_*` / 任何含 .go 文件的目录放进仓库树会被 go 工具当源码扫描**——gitignore ≠
  go-ignore（go 只忽略 `.`/`_` 前缀和 testdata）。真实案例：cdf-channel-center 的
  `output_otel_v2`（对 otel v1.45.0 插桩的残留）污染 `go mod tidy`，把解析漂到
  otel v1.47.0 并触发 go1.26 工具链切换；本仓库自己的 `tmp/` 备份目录同样踩过。备份
  产物要么放仓库外，要么用点/下划线前缀。
- **grpc-demo 被"塞"otel 是上游设计而非回归**：stdlib `log` → golog 规则（无门控、白名单）
  → otel 入图 → otsdk/GLS 级联。net/http、grpc 等依赖使几乎所有项目命中。v1.13.0 时代
  行为相同；旧验证只测过"构建成功"没测过"无 otel"。
- **demo 的最小 go.mod 需先 tidy**：stage 5 对每个 demo 先跑 `go mod tidy`（go.sum 不入库
  + 无 indirect 条目时，工具内部 dry build 偶发先于 tidy 失败）。
- **打 tag 用引号包 ref**：`git rev-parse "v1.15.0^{commit}"`（zsh 下 `^{}` 会被当 glob）。
- 合并上游 tag 时白名单版本可能经两种路径膨胀：冲突解"取上游"（hertz/gomicro），或无冲突
  自动合并直接带入（gin/echo 等）——都会被版本矩阵的软警告暴露。

## 当前已知待办

1. **白名单地板膨胀**：v1.15.0 合并后 15 个白名单模块 otel require 为 v1.45.0（仅 otsdk、
   aws-sdk-go 保持 v1.40.0），用户 otel < v1.45.0 会被静默抬高。待压回 v1.40.0 并给守卫
   加"白名单版本 ≤ 基线"检查（版本矩阵软警告持续暴露中）。
2. **vendored 基线 CVE**：v1.40.0 命中 CVE-2026-29181（baggage DoS，v1.41.0 修复）与
   GO-2026-5426（v1.43.0 修复），建议升到 ≥ v1.45.0（pkg 零 otel require 后升级对用户
   无感，只需重跑 vendor 脚本 + 回归）。
3. v1.15.0 → 上游 main（9576e38）之间仍有提交未追赶：继续 merge main 还是等下个 tag，
   待决策。
