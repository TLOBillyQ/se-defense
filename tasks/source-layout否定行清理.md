# source-layout否定行清理

## 背景

`features/source-layout.feature` 场景 1「src 一级目录只含蛋仔工作区根目录名」的例子表里有两行否定行：

| 目录    | 存在 |
| game    | 否   |
| adapter | 否   |

软 Gherkin 变异对这两行留下 2 个等价存活体（`game -> gamf`、`adapter -> adaptfr`）：
断言「不存在」的目录名无论怎么改写依然不存在，任何步骤实现都杀不掉。
同一约束已由场景 2「src 一级目录都属于 client common data server」完整覆盖。

## 操作员意图

1. 删除场景 1 例子表中 `game` 与 `adapter` 两行否定行，只保留 `client`/`server` 肯定行；场景 2 不动。
2. 重跑 `tools/acceptance/run_mutation.sh features/source-layout.feature --level soft --workers 4`，确认 25/25 击杀（操作员原话）；删掉两行后变异总数会减少，验收标准是全部击杀、0 存活。
3. 验收套件 `tools/acceptance/run_acceptance.sh` 保持全绿。
