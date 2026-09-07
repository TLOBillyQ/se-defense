# 架构决策记录（ADR）

编号递增，不删除只废止。术语以根 `CONTEXT.md` 为准；玩法规则在 `docs/gdd/`，不进 ADR。

| 编号 | 标题 |
| --- | --- |
| [0001](0001-server-authoritative-heartbeat-step.md) | 服务端权威 spoke 树 + Heartbeat 固定步长节拍 |
| [0002](0002-snapshot-protocol.md) | 快照协议（节点级增量 + 全量重同步） |
| [0003](0003-shape-dual-routing.md) | 形状双路由（ring / line 在服务端就地渲染） |
| [0004](0004-god-view-input-and-camera.md) | 上帝视角输入与相机标定 |

spoke-first 约束（业务必须建立在 `common/spoke` 原语之上）写在 `CONTEXT.md`「spoke 原语约束」并由 `features/engineering/spoke-primitives.feature` 机器检查，不另立 ADR。
