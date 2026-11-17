# MoonFileCheck

用 MoonBit 实现的文本回归测试库与命令行工具。检查编译器、代码生成器、解释器或 CLI 的输出是否满足关键模式、顺序和变量关系。

例如寄存器从 `r17` 重命名成 `r42` 可以通过，定义和使用不一致则必须失败。检查器接受输入文本，不执行被测命令，也不修改输入文件。

基线：[Bytecode Alliance filecheck 0.5.0](https://github.com/bytecodealliance/filecheck)。它与 LLVM FileCheck 不直接兼容。本项目实现六类指令和明确的正则表达式范围；兼容边界见 [COMPATIBILITY.md](docs/COMPATIBILITY.md)。

## 直接运行

便携包 `moonfilecheck-cli-0.1.1.zip` 只需要 Node.js 20 或更新版本，无 npm 依赖，无需安装 MoonBit 或 Rust。

解压后在包目录执行：

```sh
node cli.mjs examples/registers.fc --input examples/registers.txt
```

输出：

```text
PASS: 2 matches, 4 directives
```

验证错误示例：

```sh
node cli.mjs examples/registers.fc --input examples/registers-broken.txt
```

该命令返回退出码 `1`，报告规则第 4 行和输入第 2 行的寄存器不一致。使用 `--json` 输出结构化报告。未指定 `--input` 时读取标准输入。

```sh
node cli.mjs rules.fc --input output.txt --json
node cli.mjs rules.fc --input output.txt -D TARGET=wasm
node cli.mjs --help
```

退出码：`0` 全部通过；`1` 输出不满足规则；`2` 规则、参数、文件、编码或执行错误。没有识别到规则默认返回错误；可显式传入 `--allow-empty`。

## 六类指令

| 指令 | 含义 |
| --- | --- |
| `check: pattern` | 在前一正向匹配之后查找 |
| `sameln: pattern` | 必须出现在上一匹配结束位置之后的同一行 |
| `nextln: pattern` | 必须出现在上一匹配之后紧邻的下一行 |
| `unordered: pattern` | 在最近的有序屏障之后查找；允许不同规则重叠，但遵守变量定义依赖 |
| `not: pattern` | 在由相邻有序匹配界定的区间中禁止出现；尾部规则检查到输入末尾 |
| `regex: NAME=expression` | 定义可以复用的正则变量 |

规则可以嵌入源码注释中。指令区分大小写，冒号后需要空格或制表符。模式两端空白被去掉；用 `$()` 保留边缘空白或取消自动单词边界。

```text
regex: REG=r[0-9]+
check: load $(value=$REG), input
nextln: add $value, 1
not: compilation failed
```

变量与模式：

| 语法 | 含义 |
| --- | --- |
| `$$` | 字面量 `$` |
| `$()` | 空模式，可阻止自动单词边界 |
| `$name` / `$(name)` | 使用已有变量；捕获的文本按字面量匹配 |
| `$(=regex)` | 匿名正则片段 |
| `$(name=regex)` | 捕获文本，供之后的规则使用 |
| `$(name=$REGEX)` | 使用已定义的正则并捕获文本 |

同一模式中不能定义并引用同一个变量，`not:` 不能定义变量。一个 Checker 可重复使用，捕获状态不会在不同输入之间泄漏。

## 从源码构建

1. 安装 [MoonBit 官方工具链](https://www.moonbitlang.com/download/) 和 Node.js 20+。
2. 在本目录执行：

```sh
node scripts/build.mjs
node scripts/verify.mjs
moon test --target js
moon test --target wasm-gc
moon test --target native
```

本次验证的编译器：`moonc v0.10.20+65efd5b93`，`moon 0.1.20261104`。`scripts/build.mjs` 优先使用本项目 `.tools/moon`，没有时使用 PATH 中的 `moon`，不会自动安装或修改系统配置。

`moon.work` 包含主模块和带 Unicode 修复的 `vendor/regexp`。源码构建必须保留这两个成员。当前未发布 Mooncakes 包，不能用 `moon add utopi/moonfilecheck` 从注册表安装。下游本地工作区可把本目录和其 `vendor/regexp` 一起列入 `moon.work`。

编译结果放在 `dist/`。匹配、规则解析与报告均由 MoonBit 实现；Node.js 宿主只负责文件、命令参数、Worker 隔离和终端格式化。核心库在 JS、wasm-gc、native 三个后端测试通过；当前 CLI 使用 JS/Node 后端。

## MoonBit 库 API

在消费方 `moon.pkg` 导入：

```text
import {
  "utopi/moonfilecheck" @fc,
}
```

```moonbit
let checker = @fc.Checker::parse("check: hello\nnextln: world")
let report = checker.check("hello\nworld")
// report.passed == true
```

`Checker::parse` / `Checker::check` 在规则无效时抛出 `CheckError(code, rule_line, message)`。正常的不匹配返回 `Report`，其中 `passed=false`，附带首个失败诊断。完整 API 见 `pkg.generated.mbti`。

`check(rules, input, variables=...)` 是单次检查的便利函数。库默认接受空 Checker；CLI 和 JSON 协议默认拒绝，防止规则路径错误导致误通过。

## JSON 协议

```sh
node cli.mjs --request-json < request.json
```

```json
{
  "rules": "check: hello $WHO",
  "input": "hello world",
  "variables": {"WHO": "world"},
  "allow_empty": false
}
```

也可提交含 1..4096 项的请求数组，返回等长结果数组。响应状态是 `pass`、`fail` 或 `error`。`fail` 的报告带规则行号、输入行列、模式与摘录；可选字段为 `None` 时 JSON 中省略。偏移量按 UTF-16 code unit，行列号从 1 开始，列号按 Unicode scalar value；不代表终端显示宽度。

## 验证与交付

- `tests/cases.json`：87 个固定语料，包括从上游 `tests/basic.rs` 提取的 48 个断言；期望值不是由 MoonBit 实现生成。
- `scripts/verify.mjs`：固定语料、15 项 CLI/宿主检查、固定种子的 2400 个生成用例。
- 有 Rust 基准时执行真实差分；没有时使用附带 SHA256 语料指纹的已记录 Rust 结果，报告明确区分两种模式。
- [验证记录](docs/VALIDATION.md)、[原始结果](docs/evidence/verification.json)、[端到端性能数据](docs/evidence/benchmark.json)。
- [四方向选题对比](docs/SELECTION.md)、[参赛项目说明](docs/PROPOSAL.md)、[第三方来源](THIRD_PARTY.md)。

此版本已完成本地开发与验证；报名和官方验收尚未执行。所有采用与性能结论均以附带记录为限。

0.1.1 安全修复、资源限制与性能优化详见 [安全检查记录](docs/SECURITY_REVIEW.md)。运行 `npm test` 同时执行语义验证和 18 项宿主安全检查。
