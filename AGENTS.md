# AGENTS.md — loongsuite-go fork 工作上下文

本文件是 fork 仓库（`internal-otelsdk` 分支）的工作上下文，供 agent 与协作者快速建立
认知——任何人克隆本仓库后都应能据此在本机复现全部工作流。对外介绍见 `overview`
分支的 README（含图解）。

## 项目概览

上游 loongsuite-go 是阿里开源的编译期 OpenTelemetry Go 自动埋点工具：目标应用零代码
改动，在 `go build` 前加 `otel-fork` 前缀即可完成插桩。要求 Go 1.25+。

仓库布局：`pkg/`（注入到用户项目的 agent 模块：`api` / `core` / `inst-api` /
`inst-api-semconv` / `rules` / `sdkconfig` / `testaccess` / `go-sdk`）、`tool/`（构建
工具本体）、`util-genai/`、`example/`（含版本矩阵 demo）、`test/`、`scripts/`、`docs/`。

## 分支与发布策略

- remote 约定：`origin` = 本 fork 仓库（GitHub），`upstream` =
  `alibaba/loongsuite-go`（上游，只读）。克隆后执行
  `git remote add upstream https://github.com/alibaba/loongsuite-go.git` 补齐。
  如需向公司内 GitLab 镜像分发，另加一个 remote（**用 SSH 形态**——公司网络下
  HTTPS 推大包会 HTTP 500 中断，实测 SSH 直连稳定），并可用
  `git config --add remote.<name>.push 'refs/heads/internal-otelsdk'` 等
  "部分推送集合"，裸 `git push <name>` 只推 fork 自身内容。
- `main` 与全部上游 tag **严格镜像上游，零本地改动**。同步只用
  `git fetch upstream && git merge --ff-only upstream/main`（sync_upstream.sh stage 1
  会用 `git fetch upstream main:main` 实现同样的 ff-only 语义）。
- 所有 fork 定制（内置 SDK 隔离改造、本文件等元文件）都在集成分支
  **`internal-otelsdk`** 上。
- 上游发布新 tag 后：`./scripts/sync_upstream.sh <tag> --tag` 走完整流程（见下），
  验证通过后打 **`vX.Y.Z-fork`** annotated tag（message 嵌上游短哈希；发布后不可
  移动）。tag 一律本地打好、人工验证后手动 push。
- 发布形态：**仅预编译二进制**（发布流程见"发布脚本"一节）。module path 保持
  `github.com/alibaba/loongsuite-go` 不变，不走 GOPROXY / `go install`（module
  path 与实际托管仓库不一致会被模块校验拒绝，这是有意接受的取舍）。
- `overview` 分支：orphan 纯文档分支（对外 README），**永不参与 merge/sync**。
  建议将其设为远端默认分支，访客打开仓库第一眼就是项目介绍。
- 本地产物（`otel-fork` 二进制、`dist/`、`.otel-build/`、`.zcode/` 等编辑器/agent
  工作目录）不入库（.gitignore 已覆盖）。

## 发布脚本：scripts/release.sh

用法：`./scripts/release.sh [tag] [--force] [--no-upload] [--no-latest]`。
以 git tag 为唯一版本源：显式传 tag 就检出该 tag 编译（结束自动切回原分支，
成败都会恢复）；不传则要求 HEAD 恰好在 tag 上。编译复用 `make all`（五平台 +
守卫 + 版本注入），产物与 SHA256SUMS 收进 `dist/<tag>/`，配置齐全则上传 Nexus
raw 仓库并刷新 `latest/`。

- **凭据**：复制 `scripts/nexus.conf.example` 为 `scripts/.nexus.conf` 填入服务器/
  仓库/路径/账号（已 gitignore）；密码只走 `NEXUS_PASS` 环境变量。未配置时只编译
  不上传。Nexus REST 走 Basic Auth，无独立登录步骤。
- **不可变发布**：tag 目录已存在则跳过（SHA256SUMS 兼做存在性探测）；`--force`
  才覆盖。
- **latest 版本感知 + 单调防呆**：`latest/VERSION` 记录当前镜像的版本；刷新时
  拒绝把 latest 移回旧版本（`sort -V` 比较），回滚需 `--force`。
- **已知坑**：二进制 PUT 必须显式带 `Content-Type: application/octet-stream`，
  否则 Nexus 前置代理层回 500（文本能过所以小探针曾误通过）——脚本已处理，
  手写 curl 时注意。

## 历史参考：原可行性验证仓库

本项目早期在一个单独的工作副本里完成了内置 SDK 隔离方案的可行性验证（`path-a-fork`
分支，基于 v1.13.0 合并 v1.15.0——分支名里的 "path-a" 是当时的内部路线代号，即本
仓库采用的"内置 vendored SDK"路线）。其结论已全部移植到本仓库，验证使命已完成。
该仓库不在本 fork 的依赖链上，无需克隆；仅需知道一个历史教训：其 `path-a-fork`
分支曾因 `.gitignore` 的 `otel` 规则未锚定根路径，导致 `pkg/go-sdk/otel/` 整目录
被忽略而未入库（分支不自包含）——本仓库已修复。

## 隔离架构要点（双世界隔离）

方案：把 OTel SDK 路径重写后内置进 `pkg/go-sdk/`（vendored，详见下），使注入用户
项目的 `pkg` 模块对 `go.opentelemetry.io/*` 保持零直接依赖；用户应用自己的 otel
版本不受工具钉扎。

- **`pkg/go-sdk/`** 是路径重写的 OTel Go fork（vendored 基线 v1.40.0；otel/sdk 全家
  v1.40.0、prometheus v0.61.0、contrib runtime v0.65.0、proto/otlp v1.9.0、auto/sdk
  v1.2.1）。禁止手改，刷新用 `scripts/vendor_otel_fork.sh`（版本在脚本内钉死，
  机械重跑）。
- **两个"版本"要分清**：vendored 基线是工具内部管线用的（不参与用户 MVS，升级对
  用户无感）；**用户地板**是白名单规则的 otel require（参与用户 MVS，应保持低位）。
- **白名单**（17 组规则，允许 import 真实 otel，是 GLS/桥接边界代码）：otsdk、
  otel-context、otel-sdk/*、echo、gin、go-kit-log、golog、goslog、gorestful、hertz、
  iris、logrus、mux、zap、zerolog、gomicro、aws-sdk-go。其余规则模块零 otel（import
  与 require 都不能出现）。
- **otsdk 桥**：hook 用户全局 API——`GetTracerProvider` 返回包装工具管线的适配器、
  `SetTracerProvider` 跳过（agent-managed telemetry）。仅依赖 v1.20.0 起稳定的 API 面。
- **GLS 设计**：钩子（`otel-sdk/trace/v1_39_0` 等规则，版本区间 `[1.39.0,)`）注入
  用户 `sdk/trace` 包实现 goroutine 级 span 存取；框架/日志规则（gin 等）消费这些
  注入 API 读写用户 span 对象（`http.route` 即来源于 gin 规则的
  `LocalRootSpanFromGLS().SetName(路由)`）。白名单的必要性在于 GLS API 物理上定义
  在用户 otel 包内部（宿主与宿客关系），桥转换不了别人包里的函数——这是上游架构，
  不是本 fork 的选择。并发隔离由 goroutine 调度天然保证（存储是 g 结构体上的私有
  字段，每 goroutine 一份）；`newproc1` 快照继承处理 goroutine 诞生边界。
- **MVS 语义**：用户 otel ≥ 地板时用户版本胜出；低于地板被抬到地板（功能性必需：
  GLS 钩子只能注入 otel/sdk ≥ v1.39.0）。规则引擎按用户解析版本匹配版本化规则
  （如 `v1_39_0`），区间为开区间（`[1.39.0,)`），白名单 require 的地板值不参与
  规则匹配。破坏性变更的应对机制：版本矩阵回归先拦截 → 新增 `v1_xx_0` 变体规则
  并收窄旧区间（instgo 的 v1_6_0/v1_20_0 是范本）。
- **防回归守卫**：`scripts/check_otel_imports.sh`（`make lint-otel`，挂在
  `package-pkg` 前置）。扫描非白名单的真实 otel import 与 otel require。
- **架构对比结论**：instgo（商业版）是接管模型（规则用内置 otel 自建 span，数据进
  ARMS）；上游开源版是协作模型（GLS + 白名单，协作用户 span 树）。本 fork 继承协作
  模型，不重写。

## 同步流程：scripts/sync_upstream.sh

用法：`./scripts/sync_upstream.sh <tag> [--tag]`。幂等可重入（冲突解完重跑自动续），
**永不自动 push、不自动改 import**。六阶段：

1. 镜像 main（fetch upstream，ff-only）
2. 合并 tag：`pkg/rules/**/go.mod` 冲突自动解（非白名单取上游再删 otel require；
   白名单取上游保留；`pkg/go.sum` 取上游；`pkg/go.mod` 取上游 + 删 otel + tidy）；
   代码文件冲突停下人工解（原则：除 import 重写与 update.go 的 otelDeps 阉割外取上游）
3. 守卫 + 自动清扫 stale otel require；漏网 import 列人工清单
4. `make package-pkg` + `make build`
5. 版本矩阵回归（见下）
6. 打 fork tag（`--tag` 时）

**版本矩阵**（stage 5，从产物二进制的 `go version -m` 元数据读实际链接版本——工具
成功后会还原 go.mod，事后 `go list -m` 读到的是 pin 不是真相）：

| demo | 断言 |
|------|------|
| `example/grpc-demo`（无 otel） | 注入 otel == 工具地板（stdlib log → golog 级联是上游设计） |
| `example/otel-low-demo`（v1.31.0） | 抬到 ≥ v1.39.0；> v1.40.0 软警告 |
| `example/otel-high-demo`（最新） | 用户版本胜出；地板追上 pin 时自动 bump 到最新 |

## 踩坑记录

- **`output_*` / 任何含 .go 文件的目录放进仓库树会被 go 工具当源码扫描**——
  gitignore ≠ go-ignore（go 只忽略 `.`/`_` 前缀和 testdata）。曾有两个真实案例：
  某业务项目的 `output_otel_v2`（对 otel v1.45.0 插桩的残留）污染 `go mod tidy`，
  把解析漂到 otel v1.47.0 并触发 go1.26 工具链切换；本仓库自己的 `tmp/` 备份目录
  同样踩过。备份产物要么放仓库外，要么用点/下划线前缀。
- **grpc-demo 被"塞"otel 是上游设计而非回归**：stdlib `log` → golog 规则（无门控、
  白名单）→ otel 入图 → otsdk/GLS 级联。net/http、grpc 等依赖使几乎所有项目命中。
  v1.13.0 时代行为相同；旧验证只测过"构建成功"没测过"无 otel"。
- **demo 的最小 go.mod 需先 tidy**：stage 5 对每个 demo 先跑 `go mod tidy`（go.sum
  不入库 + 无 indirect 条目时，工具内部 dry build 偶发先于 tidy 失败）。
- **打 tag 用引号包 ref**：`git rev-parse "v1.15.0^{commit}"`（zsh 下 `^{}` 会被当
  glob）。
- 合并上游 tag 时白名单版本可能经两种路径膨胀：冲突解"取上游"（hertz/gomicro），
  或无冲突自动合并直接带入（gin/echo 等）——都会被版本矩阵的软警告暴露。
- **公司网络下 HTTPS 推大文件（git push / 大 body 上传）可能被代理层掐断**：
  git 场景换 SSH remote；Nexus 上传场景见"发布脚本"一节的 Content-Type 坑。

## 当前已知待办

1. **白名单地板膨胀**：v1.15.0 合并后 15 个白名单模块 otel require 为 v1.45.0（仅
   otsdk、aws-sdk-go 保持 v1.40.0），用户 otel < v1.45.0 会被静默抬高。两条候选
   路线二选一：
   - **小改（压版本）**：压回 v1.40.0 并给守卫加"白名单版本 ≤ 基线"检查（版本矩阵
     软警告持续暴露中）；
   - **大改（收缩白名单）**：给 `pkg/go-sdk` 补 GLS（vendor 脚本注入 gls_context.go，
     同 test_func_holder.go 模式；顺带补上"fork 管线 span 不进 GLS"的缺口）→ 日志类
     规则（只要 trace_id/span_id 字符串，纯数据）改用内置版 GetTraceAndSpanId，6 个
     模块退出白名单 → 框架规则改用内置版 GLS + otsdk 桥兼任两世界 GLS 同步，6 个
     模块退出白名单 → 最终白名单从 17 组收缩到 2 组（otsdk 桥 + otel-sdk 注入
     文件）。可再加一步"GLS 兜底 FromCtx"（内置 SDK 的 tracer.Start 在 ctx 无有效
     parent 时回退读 GLS，业务代码对 ctx 传递正确性免疫；需防 goroutine 池化复用
     串链）。代价：桥复杂度上升 + 跨世界 root 语义需要桥维持。
2. **vendored 基线 CVE**：v1.40.0 命中 CVE-2026-29181（baggage DoS，v1.41.0 修复）
   与 GO-2026-5426（v1.43.0 修复），建议升到 ≥ v1.45.0（pkg 零 otel require 后升级
   对用户无感，只需重跑 vendor 脚本 + 回归）。
3. v1.15.0 → 上游 main（9576e38）之间仍有提交未追赶：继续 merge main 还是等下个
   tag，待决策。
