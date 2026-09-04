# Issue tracker: Gitea

Issues and specs for this repo live in Gitea: `http://lzxsvn:3000/qinyuanj/se-defense`.

Two surfaces:

- **`tea` CLI** (login `lzxsvn`, user `qinyuanj`): create, list, view, edit labels/assignees/body, close.
- **Gitea API** at `http://lzxsvn:3000/api/v1`, authenticated with the token from `~/.config/tea/config.yml`:

  ```sh
  TOKEN=$(awk '/token:/{print $2}' ~/.config/tea/config.yml)
  api() { curl -s -H "Authorization: token $TOKEN" -H "Content-Type: application/json" "$@"; }
  ```

## Conventions

- **Create**: `tea issues create -t "..." -d "<body>" -L "label1,label2"`. Heredoc bodies: `-d "$(cat <<'EOF' ... EOF)"`.
- **Read with comments**: `tea issues <n> --comments` (note: `tea issues view` is not a subcommand). Machine-readable body: `api "…/issues/<n>"` then `jq -r .body`.
- **List**: `tea issues list --state open --labels wayfinder:task` etc.
- **Comment**: API only — `api -X POST -d '{"body":"..."}' "…/issues/<n>/comments"`.
- **Labels / assignees**: `tea issues edit <n> --add-labels "..."` / `--add-assignees qinyuanj` (also `--remove-labels`).
- **Close with explanation**: post the resolution comment first, then `tea issues close <n>` (close takes no comment).
- **Pull requests**: `tea pulls …` if ever needed; this effort currently uses issues only.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with child issues as tickets.

- **Map**: the issue labelled `wayfinder:map` ([#1](http://lzxsvn:3000/qinyuanj/se-defense/issues/1)).
- **Child ticket**: issue labelled `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`); once claimed, assigned to the driving dev.
- **Blocking**: **native Gitea dependencies**, read via `api "…/issues/<n>/dependencies"` (returns blocker issues with their `state`). **The write API is broken on this instance** (Gitea 1.27.2: POST/DELETE `…/issues/<n>/dependencies` return 404), so wire new edges **in the web UI** (issue sidebar → Dependencies), or fall back to a `Blocked by: #<n>, #<n>` line at the top of the description. A ticket is unblocked when every blocker is closed.
- **Frontier query**: `tea issues list --state open` filtered to `wayfinder:*` labels minus `wayfinder:map`; drop anything with an open dependency (`api "…/issues/<n>/dependencies"`) or an assignee; first in map order wins.
- **Claim**: `tea issues edit <n> --add-assignees qinyuanj`, the session's first write.
- **Resolve**: post the answer as a comment, `tea issues close <n>`, append a context pointer (gist + link) to the map's Decisions-so-far (`tea issues edit 1 -d "<updated body>"`).

## When a skill says "publish to the issue tracker"

Create a Gitea issue.

## When a skill says "fetch the relevant ticket"

`tea issues <n> --comments`.
