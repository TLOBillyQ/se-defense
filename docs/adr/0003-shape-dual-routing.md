# ADR 0003：形状双路由（ring / line 在服务端就地渲染）

状态：部分取代——`ring` 部分由 [ADR 0006](0006-ring-through-snapshot.md) 取代（#42），`line` 部分仍然有效（源自 Gitea 票 #9 D2、#18）

## 背景

业务的覆盖圈、供电链路、放置预览、光束都通过 `host.eui` 的 `set_ring` / `set_line` 表达。这些形状锚定在世界坐标，且数量随建筑数增长。若全部进快照，客户端要自己维护世界锚定节点，且每帧增量体积会随建筑数膨胀。

## 决策

`host.eui` 适配器内部分流：

- `text / fill / color / visible` 进快照，跨网络（ADR 0002）。
- `set_ring` / `set_line` 在服务端直接渲成 EffectUnit。EffectUnit 随 Unit 复制机制到达客户端，不进快照、不跨 RemoteEvent。
  （`set_ring` 已按 ADR 0006 改走快照；以下后果只对 `set_line` 成立。）

## 后果

- 快照体积与形状数量无关，客户端 recipe 表不需要世界锚定形状的配方。
- 形状的样式（颜色、粗细、特效 ID）知识落在服务端适配层 `server/adapter/eui.lua`，与"快照零表现知识"的原则并不冲突：形状根本不经快照。
- 形状表现依赖 Unit 复制节奏，无法像快照那样 resync。重开时靠 `reset_scene` 销毁再重建。
