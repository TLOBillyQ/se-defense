# ADR 0002：快照协议（节点级增量 + 全量重同步）

状态：已采纳（源自 Gitea 票 #18 决策 1、2、4，#28 重开扩展）

## 背景

服务端业务把 UI 状态写进 `host.eui` 节点（text / visible / color / fill）。客户端 EUI 必须在 client realm 创建，所以 UI 状态要跨网络。SE 中 server→client 唯一文档化通道是 RemoteEvent（`FireAllClients` → `OnClientEvent`），送达与有序没有文档承诺。

## 决策

1. 快照是"节点路径 → `{text, visible, color, fill}`"的状态表。快照只携状态，表现知识全在客户端 recipe 表（`client/eui_render.lua`）。
2. 混合制：平时发节点级增量 `delta`，每帧派发结束只要有 dirty 就发，不做额外节流。
3. 每条消息带单调递增 `seq`。客户端发现序号缺口就发 `resync`，服务端回 `full` 全量；客户端 resync 有 1 秒冷却防风暴。
4. 握手：客户端先挂 `OnClientEvent` 再发 `client_ready`，未收到首快照前每 2 秒重发。
5. 重开：服务端重建树后 `host.eui.generation` 加一，丢弃重建期间的增量，广播 `reset` 全量。客户端整树替换，血条按 `<实体id>g<gen>` 寻找复制单位。

## 后果

- 无序或丢包只会导致一次全量重同步，不会状态漂移。
- 客户端不需要理解任何业务语义，新增 UI 只改服务端节点与客户端 recipe 表。
- 每帧 dirty 即发意味着高频变化的节点（血条 fill）会产生持续小包。目前实测可接受，若成瓶颈再引入节流。
