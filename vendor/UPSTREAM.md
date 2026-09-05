# vendor/ 上游追踪

`vendor/spoke/` 与 `vendor/tests/` 是从上游仓库**内联**的源码，不是 git submodule。
曾经用过 submodule（`vendor/spoke-lua`），但上游整仓 189 个文件里我们只用 68 个，
挂载点也和内联布局冲突，所以改为内联 + 本文件做版本追踪。

| 项 | 值 |
| --- | --- |
| 上游 | `http://lzxsvn:3000/qinyuanj/spoke.git` |
| 对应 commit | `8966186c4ea3bdb10d80edfaabb6723b0ec3ab06` |
| 同步日期 | 2026-09-05 |

## 内联范围

- 上游 `src/spoke/` → 本仓库 `vendor/spoke/`（35 个文件，全量）
- 上游 `tests/` → 本仓库 `vendor/tests/`（28 个文件）

`tests/` 故意少 5 个：`acceptance/steps_test.lua`、`property/json_property.lua`、
`property/sha256_property.lua`、`tools/cli_test.lua`、`tools/runner_worker_test.lua`。
它们测的是上游自己的 gherkin/CLI 工具链，本仓库没有那套工具，拉进来跑不了。

上游其余目录（`acceptance/` `features/` `docs/` `swarmforge/` `scripts/` 等）与本仓库无关，不内联。

## 唯一的本地改动：require 前缀

内联后把所有 `src.spoke` / `src/spoke` 改写成了 `vendor.spoke` / `vendor/spoke`，
测试同理 `tests.` → `vendor.tests.`。除此之外与上游逐字节一致。

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
grep -rl 'src\.spoke' "$d/src/spoke" | xargs sed -i '' 's|src\.spoke|vendor.spoke|g'
diff -ru "$d/src/spoke" vendor/spoke
```

确认要更新后，用同一套改写落盘，然后跑测试并更新上表的 commit：

```sh
rm -rf vendor/spoke && cp -R "$d/src/spoke" vendor/spoke
lua vendor/tests/run.lua && lua vendor/tests/property/run.lua
```
