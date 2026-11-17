# 第三方来源与修改

## Bytecode Alliance filecheck 0.5.0

- 来源：https://github.com/bytecodealliance/filecheck
- 发布版本：Cargo `filecheck=0.5.0`，锁文件包含包 checksum。
- 作者：The Cranelift Project Developers。
- 许可证：Apache-2.0 WITH LLVM-exception，全文位于根目录 LICENSE。
- 本项目 `pattern.mbt` 与 `checker.mbt` 的解析/匹配语义参考并改写自其 Rust 实现。`reference/upstream/basic.rs` 保留上游测试，用于提取固定断言。
- 新增：MoonBit API、结构化诊断、CLI 宿主、输入约束、跨后端测试、差分适配、打包和使用文档。这些新增不改变上游代码的归属。

## moonbitlang/regexp 0.3.7

- 来源：https://github.com/moonbitlang/regexp.mbt
- 包源码固定为 Mooncakes 发布版 0.3.7，完整源文件在 vendor/regexp。
- 许可证：Apache-2.0，保留 vendor/regexp/LICENSE 与 NOTICE。NOTICE 含其参考 Russ Cox re1 的 BSD 来源声明。
- 修改：修复 Unicode 单词边界读取低代理项时 unwrap 崩溃；采用 Rust Unicode 单词表，使 \w/\W 与边界包含 Unicode；新增回归测试；两个 ASCII AST fixture 改为显式 ASCII 字符类；\W 的中文预期随已记录语义改变；迁移八处过时 derive 语法；moon fmt 格式化并重新生成接口。
- 未将这些原有库源文件或原有测试计为本项目原创工程量。

## Rust regex Unicode 16.0.0 表

- 来源：https://github.com/rust-lang/regex/blob/1.11.1/regex-syntax/src/unicode_tables/perl_word.rs
- 生成文件：vendor/regexp/internal/unicode/rust_word_ranges.mbt，796 组范围，保持原数据。
- 许可证：MIT OR Apache-2.0。全文在 licenses/regex-LICENSE-MIT 与 licenses/regex-LICENSE-APACHE。
- 该表是生成数据；不计作本项目原创算法。

## 工具与基准

Rust 仅用于 reference/oracle 的独立校验。它依赖未修改的 filecheck 0.5.0、regex 1.11.1 和 serde_json 1.0.140；递归依赖锁定于 Cargo.lock。便携 CLI 不包含 Rust 测试适配器或 Rust 工具链。

0.1.1 的额外依赖修改：`vendor/regexp/internal/ast/compile.mbt` 添加饱和编译成本估计；`vendor/regexp/top.mbt` 在指令展开前拒绝超预算 AST；`vendor/regexp/compile_budget_test.mbt` 添加计数重复与空重复的回归测试，接口文件由 moon info 更新。这些修复是本地补丁，未声称已由上游接受。

MoonBit 编译器、标准库和便携 Rust 工具链位于被忽略的 .tools，不随源码包交付。生成的 JS 包包含必要的 MoonBit 标准库/正则代码；其 Apache-2.0 及相关 NOTICE 随运行包提供。
