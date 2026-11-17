# 四方向选题调研与最终选择

调研日期：2026-11-16。面向本次 MoonBit 黑客松，按个人或小团队、约一个月可交付的前提筛选。以下“最有价值”是这些约束下的工程判断，不是对全网所有项目的客观排名，也不是预测官方得分。

## 每个方向选出的项目

| 比赛方向 | 最终候选与 GitHub 来源 | 建议开发的具体内容 | 价值依据与主要风险 |
| --- | --- | --- | --- |
| 工具库 | [mizchi/moonbit_jsonschema](https://github.com/mizchi/moonbit_jsonschema)，对照 [JSON Schema Test Suite](https://github.com/json-schema-org/JSON-Schema-Test-Suite) | 为现有校验库补充明确的标准能力，建立按关键字分类的官方语料合规矩阵 | JSON 数据边界可广泛复用；README 列出了尚未支持的关键字。但需要与其他 MoonBit Schema 库逐项比较，避免重复；完整 2020-12 语义，特别是动态引用和 evaluated annotations，范围很大 |
| 数据处理 | [johnkerl/miller](https://github.com/johnkerl/miller) | MoonBit 原生流式 CSV/JSONL 转换内核：字段选择、过滤、分组统计和格式转换，清楚限定 DSL 范围 | 命名字段、流处理和组合式数据转换有直接用途；完整 Miller 的表达式语言与多种格式远超首版范围，过度裁剪又容易只剩普通 CSV 工具 |
| AI 应用 | [promptfoo/promptfoo](https://github.com/promptfoo/promptfoo) | 面向工具调用和结构化输出的回归评测应用：数据集、固定响应回放、确定性断言和报告 | 能帮助发现模型或提示词变化后的行为退化；完整参考项目涉及大量供应商与评测类型。没有真实模型/应用接入时，只能证明评测框架行为，无法证明业务效果 |
| 开发者工具 | [bytecodealliance/filecheck](https://github.com/bytecodealliance/filecheck) | MoonBit 文本模式回归检查库与 CLI，六类指令、捕获复用、诊断和独立差分 | 有可执行的成熟上游作为基准，核心算法独立于外部服务，容易形成完整工程和验证闭环；受众主要是生成文本、编译工具和 CLI 的维护者 |

上述候选是本方向的推荐开发切口，不表示建议完整移植 Miller、Promptfoo 或实现全部 JSON Schema 2020-12。

## 四个项目对比

| 判断维度 | Schema 增强 | 流式数据内核 | AI 回归评测 | MoonFileCheck |
| --- | --- | --- | --- | --- |
| 实际复用范围 | 很广 | 很广 | 广，但依赖具体 AI 场景 | 集中在开发工具和生成器，可跨语言使用 |
| 一个月完成核心闭环 | 中 | 中 | 中 | 高 |
| 可依赖的外部验证 | 官方语料强，但语义面广 | 可对照 Miller，格式和 DSL 差异较多 | 确定性部分可验证，模型质量较难归因 | 固定版本 Rust 实现可直接运行差分 |
| 生态增量证明难度 | 较高：已有多项实现 | 中：需证明超出已有解析/查询库 | 较高：不能只包装模型 API | 较低：本轮未检索到直接对应的 MoonBit 实现 |
| 主要技术攻关 | 引用、数值、组合校验 | 流式状态、表达式与内存边界 | 数据集、评判语义与供应商边界 | 匹配区间、变量依赖、否定规则、Unicode |
| 开发与演示依赖 | 本地工具链 | 本地工具链和数据集 | 通常还需模型、费用或真实数据 | 本地工具链，无外部服务 |

最终选择 **MoonFileCheck**。选择重点是：可在一个明确范围内实现足够深的核心，验证能够直接依赖一个独立实现，成果可以作为库和 CLI 使用。没有证据支持“其市场需求超过另外三个方向”，因此不作此结论。

## 同类检索与限制

GitHub 与 Mooncakes 已检索到 [moon_mutest](https://github.com/Magic486/moon_mutest) 和 [MoonGuard](https://github.com/QinXi-ai/moonguard)，因此没有把变异测试和 API/SemVer 检查当作全新缺口。

本轮以 `MoonBit FileCheck`、`site:mooncakes.io FileCheck` 及相关项目名检索，未找到直接对应的 MoonBit FileCheck 实现。搜索索引不完整，“未检索到”不等于“绝对不存在”。

官方标准库已经提供快照测试。MoonFileCheck 的增量是可复用的模式约束：允许未约束输出变化，检查变量关系和局部顺序，并能消费不同语言/进程的文本输出。当前实际接入验证是 MoonBit 工具链生成的两个接口文件；没有第三方维护者采用的证据。

## 与赛事标准对应

依据 [赛事官网](https://moonbitlang.github.io/Hackathon2026/) 的工程深度、技术贡献、生态增量和开发验证四项标准，本项目交付核心实现、来源说明、上游差分、回归用例和可运行演示。正则依赖与测试源的原有代码单独归属，不计作本项目原创贡献；没有做获奖或官方验收承诺。
