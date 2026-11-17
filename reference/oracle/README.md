# Rust 对照实现

这是围绕**未修改**的 Cargo `filecheck=0.5.0` 的小型 JSON 适配器，不是另写一遍匹配算法。`regex=1.11.1` 与 Cargo.lock 固定语义和依赖。使用 Rust 1.85.1 完成本次验证。

Linux/macOS：

```sh
CARGO_TARGET_DIR=.tools/oracle-target cargo build --release --locked --manifest-path reference/oracle/Cargo.toml
node scripts/verify.mjs
```

PowerShell：

```powershell
$env:CARGO_TARGET_DIR = Join-Path (Get-Location) '.tools/oracle-target'
cargo build --release --locked --manifest-path reference/oracle/Cargo.toml
node scripts/verify.mjs
```

可用 `MOONFILECHECK_ORACLE` 指向不同位置的测试适配器。没有可执行文件时，验证脚本检查语料 SHA256，然后使用 tests/oracle-baseline.json 中记录的真实 Rust 结果；输出 `oracle_mode=recorded-rust`，不会伪称本次执行了 Rust。

只有在实际运行 Rust 基准时，才允许 `node scripts/verify.mjs --record-oracle` 更新记录基准。添加语料后应复核 Rust 结果和项目的独立期望，不能根据 MoonBit 当前输出修改期望值。
