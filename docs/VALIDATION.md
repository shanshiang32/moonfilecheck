# 验证记录

开发与调研始于 2026-11-16；最终交付验证于 2026-11-17（Asia/Shanghai）。下列结果是本地执行记录，不是远端 CI 或第三方认证。

## 环境

- Windows x64，Node.js v24.14.1。
- moon 0.1.20261104 (940aa18)，moonc v0.10.20+65efd5b93。
- Rust 1.85.1，未修改的 filecheck 0.5.0；regex 1.11.1；具体依赖以 Cargo.lock 为准。
- 本地 MoonBit 和 Rust 归档经其官方 SHA256 文件校验；工具链位于忽略的 .tools 内，不进入交付包。

## 检查范围与结果

| 检查 | 范围 | 结果 |
| --- | --- | --- |
| MoonBit 类型检查 | JS、wasm-gc、native；警告视作错误 | 通过 |
| MoonBit 测试 | 每后端 174 项：主项目 14 项，vendored regexp 160 项 | 三后端均通过 |
| 跨后端共享语料 | 87 项语料，由单个 corpus test 在每个后端逐项断言 | 三后端均通过 |
| 固定语料 | 48 项从上游 basic.rs 提取的断言＋39 项独立回归 | 87/87 |
| CLI/宿主 | 退出码、文件与标准输入、非法参数、协议类型、空规则、非法 Unicode、超时 | 15/15 |
| 实际 Rust 差分 | 87 个固定输入＋种子 0x5eed2026 生成的 2400 个输入 | 2487 组，0 不一致 |
| 工具输出接入 | moon info 生成的主库与 regexp 接口文件 | 两组规则均通过 |
| 便携包 | 解压到独立目录后运行通过和失败示例 | 退出码分别为 0 和 1 |

原始差分结果在 [evidence/verification.json](evidence/verification.json)。`tests/oracle-baseline.json` 含语料 SHA256 和未修改的 Rust 上游生成的结果；测试脚本不根据 MoonBit 输出生成基准。

## 复现

```sh
node scripts/build.mjs
node scripts/verify.mjs --recorded
moon check --target js --deny-warn
moon test --target js
moon test --target wasm-gc
moon test --target native
moon info
node cli.mjs examples/interface.fc --input pkg.generated.mbti
node cli.mjs examples/regexp-interface.fc --input vendor/regexp/pkg.generated.mbti
```

真实差分先按 [Rust 适配器说明](../reference/oracle/README.md) 编译基准，再运行 `node scripts/verify.mjs`。`--recorded` 显式使用存档基准；新测试结果写入被忽略的 `artifacts/verification.json`，不会覆盖已提交的交付记录。

## 开发中发现的问题

1. **UTF-16 单词边界崩溃**：依赖库在单词边界读取前一 code unit 时，可能落到 emoji 的低代理项，`get_char(...).unwrap()` 会崩溃。修复其标量恢复逻辑，并保留独立测试。
2. **补充平面字符丢失导致误通过**：本项目最初按 UTF-16 单元归一化正则，半个 surrogate 的片段被 StringBuilder 丢弃，规则可能退化为空匹配。随机 Rust 差分揭示错误；改为逐 Unicode scalar 复制，并对匹配偏移添加回归断言。
3. **捕获命名限制**：规则语法允许数字变量名，但 Rust regex 的 capture name 不能以数字开头。显式返回错误，保留相应语料。

## 性能

`node scripts/benchmark.mjs` 每档预热一次、测量五次。包括 Worker 创建、引擎载入、JSON 和匹配，不是纯匹配器吞吐率。当前本机中位数约为：1 KiB 64 ms，64 KiB 79 ms，1 MiB 241 ms。完整样本、机器信息在 [evidence/benchmark.json](evidence/benchmark.json)。

样本只测试一条尾部匹配规则。结果不支持“比 Rust 更快”或任意复杂规则仍为线性时间的结论。0.1.1 对顺序匹配复用行列扫描位置；无序匹配回退时仍可能重扫。2000 条顺序匹配、约 200 KiB 输入的同机测试中，旧版与新版中位数分别为 4984 ms 和 421 ms（约 11.8 倍）；包含 Worker 启动，非通用加速承诺。原始样本见 [optimization.json](evidence/optimization.json)。

## 已知限制

验证语料不涵盖完整 Rust regex 或完整 LLVM FileCheck；具体差异见 COMPATIBILITY.md。没有第三方实际采用记录，也没有远端 Actions 成功记录。CI 文件已提供，需在公开仓库推送后实际执行。
