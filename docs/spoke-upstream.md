# spoke 上游追踪

`common/spoke/` 与 `tests/spoke/` 是从上游仓库**内联**的源码，不是 git submodule。
运行时放在仓库根 `common/` 而不是 `vendor/`，因为 SE 工作区只认 `client/common/data/server`
四个根目录，仓库根直接对齐工作区根（无 `src/` 中间层），spoke 由此和业务代码走同一条部署规则。
曾经用过 submodule（`vendor/spoke-lua`），但上游整仓 189 个文件里我们只用 68 个，
挂载点也和内联布局冲突，所以改为内联 + 本文件做版本追踪。

| 项 | 值 |
| --- | --- |
| 上游 | `http://lzxsvn:3000/qinyuanj/spoke.git` |
| 对应 commit | `8966186c4ea3bdb10d80edfaabb6723b0ec3ab06` |
| 同步日期 | 2026-09-05 |

## 内联范围

- 上游 `src/spoke/` → 本仓库 `common/spoke/`（35 个文件，全量）
- 上游 `tests/` → 本仓库 `tests/spoke/`（28 个文件）

`tests/` 故意少 5 个：`acceptance/steps_test.lua`、`property/json_property.lua`、
`property/sha256_property.lua`、`tools/cli_test.lua`、`tools/runner_worker_test.lua`。
它们测的是上游自己的 gherkin/CLI 工具链，本仓库没有那套工具，拉进来跑不了。

上游其余目录（`acceptance/` `features/` `docs/` `swarmforge/` `scripts/` 等）与本仓库无关，不内联。

## 唯一的本地改动：require 前缀

内联后把所有 `src.spoke` 改写成了 `common.spoke`（注释里的路径 `src/spoke` 同理改为 `common/spoke`），
测试同理 `tests.` → `tests.spoke.`。另外两处本地改动：上游 `tests/tests/lib.lua` 放在本仓库
`tests/lib/`；`tests/sanity_test.lua` 删掉了 Lua 版本断言（本机解释器不一定是 5.4，真机才是）。
上游 `tests/run.lua` 不内联，本仓库 `tests/run.lua` 统一发现 `tests/**/*_test.lua`。除此之外与上游逐字节一致。

**所以同步时不能直接覆盖**，必须重新做这次改写，否则 require 全部断掉。

## 同步上游

remote 只存在 `.git/config` 里，不随仓库分发，先各自加一次：

```sh
git remote add spoke-upstream http://lzxsvn:3000/qinyuanj/spoke.git
git fetch spoke-upstream
```

看上游动了什么（先归一化前缀再比，否则满屏都是前缀噪音）：

```sh
d=$(mktemp -d)
git archive spoke-upstream/main src/spoke | tar -x -C "$d"
grep -rl 'src\.spoke' "$d/src/spoke" | xargs sed -i '' 's|src\.spoke|common.spoke|g'
diff -ru "$d/src/spoke" common/spoke
```

确认要更新后，用同一套改写落盘，然后跑测试并更新上表的 commit：

```sh
rm -rf common/spoke && cp -R "$d/src/spoke" common/spoke
lua tests/run.lua && lua tests/spoke/property/run.lua
```

## 业务模块不在 vendor/ 里

上游曾有 `examples/base_defence/`（Base Defence 业务示例），最后版本是上游
`4bdcf06`，之后被上游删除。它已迁入本仓库 `server/game/`（require 前缀
`server.game`，宿主 mock 改为直接依赖 `server.adapter.*`），从此在本仓库维护，
**不参与上游同步**。
