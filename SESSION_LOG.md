# セッションログ

---

🧑 あなた
どう？

↓
(作業)
↓

🤖 Claude
deferred tools リストを確認すると、`mcp__session-recall__*` は **まだ出てきていない**。Google 系 MCP しか登録されてない。前回 #11 で `claude mcp add` し直して Connected にしたはずだけど、resume 後も認識されてない。

現状を確認させて。

↓
(作業)
↓

🤖 Claude
## 状況報告

**MCP 状態:**
- `claude mcp list` → session-recall: ✓ Connected ✅
- でも **このセッションの deferred tools には依然として出ていない** ❌（Google系3つしか見えない）
- HANDOFF.md #11 と全く同じ症状（Connected なのにツール非露出）が再発。`.mcp.json` は `.bak` にリネームされてる、user スコープ登録だけ生きてる状態。

**HANDOFF.md の Step 2 で「次に試すこと」として残してあるオプション:**
1. user スコープ削除 → `--scope project` で `.mcp.json` を再生成して登録
2. `.mcp.json` を git tracked にして承認ダイアログを出させる
3. Mac で同手順試して Windows 固有問題か切り分け

どれから試す？個人的には **(1) project スコープで再登録** が一番素直（`.mcp.json.bak` の中身そのままなので戻すだけ）。やる場合は `/exit` → 再起動が必要だけど、その前に切り替えていい？

↓
(作業)
↓

🧑 あなた
うんいいよ

🤖 Claude
📡

了解、project スコープに切り替える。手順:
1. user スコープ登録を削除
2. `.mcp.json.bak` → `.mcp.json` にリネーム（project スコープに戻す）
3. HANDOFF.md に「今やったこと」と「次に確認すること」を追記
4. コミット
5. `/exit` → 再起動して deferred tools に出るか確認

↓
(作業)
↓

🤖 Claude
準備完了。次セッションで確認することを HANDOFF.md に書き出してコミット&push 済み。

**今やったこと:**
- `claude mcp remove session-recall`（user スコープ削除）
- `.mcp.json.bak` → `.mcp.json` にリネーム（project スコープで再登録）
- `claude mcp list` → Connected（project 経由に切り替わった）

**次セッション開始時に確認すること（HANDOFF Step 2 に記載済み）:**
- deferred tools に `mcp__session-recall__search` / `mcp__session-recall__semantic` が出ているか

`/exit` で終了して、`claude --resume` で再開してください。

↓
(作業)
↓

🧑 あなた
もどったよー

🤖 Claude
📡

おかえり！deferred tools に出てるか確認する。

↓
(作業)
↓

🤖 Claude
ダメだ、project スコープでも deferred tools に出ない。`claude mcp list` は Connected って言うのに。

別の仮説: project レベルの `.mcp.json` は **明示的な許可リスト** が必要かもしれない。`settings.json` に `enabledMcpjsonServers` 等の設定がいるパターン。確認する。

↓
(作業)
↓

🤖 Claude
これだ！`.claude.json` 内の `projects."G:/マイドライブ/_Apps2026/session-recall".enabledMcpjsonServers` が空 `[]` になってる。これが原因で Claude Code が `.mcp.json` の session-recall を「未承認」扱いしてツールをロードしてない。

Python で安全に書き換える（前回 sed で壊した実績があるので JSON モジュール使う）。

↓
(作業)
↓

🤖 Claude
書き換え成功、JSON は無事。`projects."...session-recall".enabledMcpjsonServers = ["session-recall"]` に設定。これで再起動時に Claude Code が `.mcp.json` の session-recall を承認済みとして扱い、ツールをロードするはず。

HANDOFF を更新してコミット → /exit 案内する。

↓
(作業)
↓

🤖 Claude
準備完了。

**真因:** `.claude.json` の `projects."...session-recall".enabledMcpjsonServers` が `[]` になっていて、Claude Code が `.mcp.json` の session-recall を未承認扱いしていた。`claude mcp list` の Connected 表示は health check が通ってるだけで、セッションへのツール露出とは別判定だった。

**対応:** Python で `enabledMcpjsonServers: ["session-recall"]` に書き換え（前回 sed で `.claude.json` を 0 バイトにした事故の教訓を踏まえて json モジュール使用）。コミット・push 済み。

`/exit` → `claude --resume` で再起動して、deferred tools に `mcp__session-recall__*` が出るか確認してください。

↓
(作業)
↓

🧑 あなた
もどったよー、どう？

🤖 Claude
📡

おかえり！deferred tools に出てるか確認する。

↓
(作業)
↓

🤖 Claude
サーバー側は完璧に動いてる（initialize → tools/list で 2 ツール正常返却）。問題は Claude Code クライアント側がツールを deferred tools リストに登録してくれていない。`enabledMcpjsonServers` も `hasTrustDialogAccepted` も揃ってるのに。

Claude Code 公式の挙動を調べさせる。

↓
(作業)
↓

🤖 Claude
決定打が出た。**Claude Code v2.1.116 以降の regression** が原因（GitHub Issue #51736）。custom MCP server のツールが deferred tools として登録されない既知バグ。built-in connector（Google系）だけ動く症状と完全一致。

**回避策:** `ENABLE_TOOL_SEARCH=false` を環境変数で渡す → deferred mechanism を排除して全ツール upfront 読み込みに切り替わる。

提案:

**まず動くか確認するため一発試してもらう:**
```bash
ENABLE_TOOL_SEARCH=false claude --resume
```
これで deferred tools に `mcp__session-recall__*` が出るかどうかで、原因確定 + 回避策 OK が同時にわかる。

**動いたら永続化する選択肢:**
- グローバル `settings.json` の `env` フィールドに `"ENABLE_TOOL_SEARCH": "false"` を追加 → 毎回 `ENABLE_TOOL_SEARCH=false` を打たなくて済む
- ただし副作用: 全ツール upfront 読み込みになるので毎セッションのコンテキスト初期消費がやや増える

どうする？まず一発試す方向で行く？HANDOFF 更新してから `/exit` 案内するけど、その前に試したい手順を確定したい。

🧑 あなた
ためそう！

🤖 Claude
📡

了解。HANDOFF 更新してコミット → 起動コマンド案内する。

↓
(作業)
↓

🤖 Claude
準備完了。コミット・push 済み。

**次の手順:**

1. `/exit` で終了
2. 次のコマンドで起動:

```bash
ENABLE_TOOL_SEARCH=false claude --resume
```

これで deferred tools に `mcp__session-recall__*` が出るかどうかで、回避策の効果が確定する。出れば永続化（settings.json の env に追加）するか相談しよう。

`/exit` どうぞ。

↓
(作業)
↓

🧑 あなた
もどったよー

🤖 Claude
📡

おかえり！deferred tools のリスト表示が今回のシステムリマインダから消えてる = `ENABLE_TOOL_SEARCH=false` が効いてるサイン。MCP ツールが直接呼べるか試す。

↓
(作業)
↓

🧑 あなた
[Request interrupted by user]

🧑 あなた
あ、ごめん、コマンド必要なの気づかずに普通にresumeだけしてたよ

🤖 Claude
📡

なるほど！普通に resume しちゃったからこうなった。**毎回環境変数を打つの面倒なので settings.json に永続化** してから再起動するのが楽だと思う。update-config skill 呼ぶ。

↓
(作業)
↓

🧑 あなた
# Update Config Skill

Modify Claude Code configuration by updating settings.json files.

## When Hooks Are Required (Not Memory)

If the user wants something to happen automatically in response to an EVENT, they need a **hook** configured in settings.json. Memory/preferences cannot trigger automated actions.

**These require hooks:**
- "Before compacting, ask me what to preserve" → PreCompact hook
- "After writing files, run prettier" → PostToolUse hook with Write|Edit matcher
- "When I run bash commands, log them" → PreToolUse hook with Bash matcher
- "Always run tests after code changes" → PostToolUse hook

**Hook events:** PreToolUse, PostToolUse, PreCompact, PostCompact, Stop, Notification, SessionStart

## CRITICAL: Read Before Write

**Always read the existing settings file before making changes.** Merge new settings with existing ones - never replace the entire file.

## CRITICAL: Use AskUserQuestion for Ambiguity

When the user's request is ambiguous, use AskUserQuestion to clarify:
- Which settings file to modify (user/project/local)
- Whether to add to existing arrays or replace them
- Specific values when multiple options exist

## Decision: /config command vs Direct Edit

**Suggest the `/config` slash command** for these simple settings:
- `theme`, `editorMode`, `verbose`, `model`
- `language`, `alwaysThinkingEnabled`
- `permissions.defaultMode`

**Edit settings.json directly** for:
- Hooks (PreToolUse, PostToolUse, etc.)
- Complex permission rules (allow/deny arrays)
- Environment variables
- MCP server configuration
- Plugin configuration

## Workflow

1. **Clarify intent** - Ask if the request is ambiguous
2. **Read existing file** - Use Read tool on the target settings file
3. **Merge carefully** - Preserve existing settings, especially arrays
4. **Edit file** - Use Edit tool (if file doesn't exist, ask user to create it first)
5. **Confirm** - Tell user what was changed

## Merging Arrays (Important!)

When adding to permission arrays or hook arrays, **merge with existing**, don't replace:

**WRONG** (replaces existing permissions):
```json
{ "permissions": { "allow": ["Bash(npm *)"] } }
```

**RIGHT** (preserves existing + adds new):
```json
{
  "permissions": {
    "allow": [
      "Bash(git *)",      // existing
      "Edit(.claude)",    // existing
      "Bash(npm *)"       // new
    ]
  }
}
```

## Settings File Locations

Choose the appropriate file based on scope:

| File | Scope | Git | Use For |
|------|-------|-----|---------|
| `~/.claude/settings.json` | Global | N/A | Personal preferences for all projects |
| `.claude/settings.json` | Project | Commit | Team-wide hooks, permissions, plugins |
| `.claude/settings.local.json` | Project | Gitignore | Personal overrides for this project |

Settings load in order: user → project → local (later overrides earlier).

## Settings Schema Reference

### Permissions
```json
{
  "permissions": {
    "allow": ["Bash(npm *)", "Edit(.claude)", "Read"],
    "deny": ["Bash(rm -rf *)"],
    "ask": ["Write(/etc/*)"],
    "defaultMode": "default" | "plan" | "acceptEdits" | "dontAsk",
    "additionalDirectories": ["/extra/dir"]
  }
}
```

**Permission Rule Syntax:**
- Exact match: `"Bash(npm run test)"`
- Prefix wildcard: `"Bash(git *)"` - matches `git`, `git status`, `git commit`, etc.
- Tool only: `"Read"` - allows all Read operations

### Environment Variables
```json
{
  "env": {
    "DEBUG": "true",
    "MY_API_KEY": "value"
  }
}
```

### Model & Agent
```json
{
  "model": "sonnet",  // or "opus", "haiku", full model ID
  "agent": "agent-name",
  "alwaysThinkingEnabled": true
}
```

### Attribution (Commits & PRs)
```json
{
  "attribution": {
    "commit": "Custom commit trailer text",
    "pr": "Custom PR description text"
  }
}
```
Set `commit` or `pr` to empty string `""` to hide that attribution.

### MCP Server Management
```json
{
  "enableAllProjectMcpServers": true,
  "enabledMcpjsonServers": ["server1", "server2"],
  "disabledMcpjsonServers": ["blocked-server"]
}
```

### Plugins
```json
{
  "enabledPlugins": {
    "formatter@anthropic-tools": true
  }
}
```
Plugin syntax: `plugin-name@source` where source is `claude-code-marketplace`, `claude-plugins-official`, or `builtin`.

### Other Settings
- `language`: Preferred response language (e.g., "japanese")
- `cleanupPeriodDays`: Days to keep transcripts before automatic cleanup (default: 30; minimum 1)
- `respectGitignore`: Whether to respect .gitignore (default: true)
- `spinnerTipsEnabled`: Show tips in spinner
- `spinnerVerbs`: Customize spinner verbs (`{ "mode": "append" | "replace", "verbs": [...] }`)
- `spinnerTipsOverride`: Override spinner tips (`{ "excludeDefault": true, "tips": ["Custom tip"] }`)
- `syntaxHighlightingDisabled`: Disable diff highlighting


## Hooks Configuration

Hooks run commands at specific points in Claude Code's lifecycle.

### Hook Structure
```json
{
  "hooks": {
    "EVENT_NAME": [
      {
        "matcher": "ToolName|OtherTool",
        "hooks": [
          {
            "type": "command",
            "command": "your-command-here",
            "timeout": 60,
            "statusMessage": "Running..."
          }
        ]
      }
    ]
  }
}
```

### Hook Events

| Event | Matcher | Purpose |
|-------|---------|---------|
| PermissionRequest | Tool name | Run before permission prompt |
| PreToolUse | Tool name | Run before tool, can block |
| PostToolUse | Tool name | Run after successful tool |
| PostToolUseFailure | Tool name | Run after tool fails |
| Notification | Notification type | Run on notifications |
| Stop | - | Run when Claude stops (including clear, resume, compact) |
| PreCompact | "manual"/"auto" | Before compaction |
| PostCompact | "manual"/"auto" | After compaction (receives summary) |
| UserPromptSubmit | - | When user submits |
| SessionStart | - | When session starts |

**Common tool matchers:** `Bash`, `Write`, `Edit`, `Read`, `Glob`, `Grep`

### Hook Types

**1. Command Hook** - Runs a shell command:
```json
{ "type": "command", "command": "prettier --write $FILE", "timeout": 30 }
```

**2. Prompt Hook** - Evaluates a condition with LLM:
```json
{ "type": "prompt", "prompt": "Is this safe? $ARGUMENTS" }
```
Only available for tool events: PreToolUse, PostToolUse, PermissionRequest.

**3. Agent Hook** - Runs an agent with tools:
```json
{ "type": "agent", "prompt": "Verify tests pass: $ARGUMENTS" }
```
Only available for tool events: PreToolUse, PostToolUse, PermissionRequest.

### Hook Input (stdin JSON)
```json
{
  "session_id": "abc123",
  "tool_name": "Write",
  "tool_input": { "file_path": "/path/to/file.txt", "content": "..." },
  "tool_response": { "success": true }  // PostToolUse only
}
```

### Hook JSON Output

Hooks can return JSON to control behavior:

```json
{
  "systemMessage": "Warning shown to user in UI",
  "continue": false,
  "stopReason": "Message shown when blocking",
  "suppressOutput": false,
  "decision": "block",
  "reason": "Explanation for decision",
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "Context injected back to model"
  }
}
```

**Fields:**
- `systemMessage` - Display a message to the user (all hooks)
- `continue` - Set to `false` to block/stop (default: true)
- `stopReason` - Message shown when `continue` is false
- `suppressOutput` - Hide stdout from transcript (default: false)
- `decision` - "block" for PostToolUse/Stop/UserPromptSubmit hooks (deprecated for PreToolUse, use hookSpecificOutput.permissionDecision instead)
- `reason` - Explanation for decision
- `hookSpecificOutput` - Event-specific output (must include `hookEventName`):
  - `additionalContext` - Text injected into model context
  - `permissionDecision` - "allow", "deny", or "ask" (PreToolUse only)
  - `permissionDecisionReason` - Reason for the permission decision (PreToolUse only)
  - `updatedInput` - Modified tool input (PreToolUse only)

### Common Patterns

**Auto-format after writes:**
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Write|Edit",
      "hooks": [{
        "type": "command",
        "command": "jq -r '.tool_response.filePath // .tool_input.file_path' | { read -r f; prettier --write \"$f\"; } 2>/dev/null || true"
      }]
    }]
  }
}
```

**Log all bash commands:**
```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "jq -r '.tool_input.command' >> ~/.claude/bash-log.txt"
      }]
    }]
  }
}
```

**Stop hook that displays message to user:**

Command must output JSON with `systemMessage` field:
```bash
# Example command that outputs: {"systemMessage": "Session complete!"}
echo '{"systemMessage": "Session complete!"}'
```

**Run tests after code changes:**
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Write|Edit",
      "hooks": [{
        "type": "command",
        "command": "jq -r '.tool_input.file_path // .tool_response.filePath' | grep -E '\\.(ts|js)$' && npm test || true"
      }]
    }]
  }
}
```


## Constructing a Hook (with verification)

Given an event, matcher, target file, and desired behavior, follow this flow. Each step catches a different failure class — a hook that silently does nothing is worse than no hook.

1. **Dedup check.** Read the target file. If a hook already exists on the same event+matcher, show the existing command and ask: keep it, replace it, or add alongside.

2. **Construct the command for THIS project — don't assume.** The hook receives JSON on stdin. Build a command that:
   - Extracts any needed payload safely — use `jq -r` into a quoted variable or `{ read -r f; ... "$f"; }`, NOT unquoted `| xargs` (splits on spaces)
   - Invokes the underlying tool the way this project runs it (npx/bunx/yarn/pnpm? Makefile target? globally-installed?)
   - Skips inputs the tool doesn't handle (formatters often have `--ignore-unknown`; if not, guard by extension)
   - Stays RAW for now — no `|| true`, no stderr suppression. You'll wrap it after the pipe-test passes.

3. **Pipe-test the raw command.** Synthesize the stdin payload the hook will receive and pipe it directly:
   - `Pre|PostToolUse` on `Write|Edit`: `echo '{"tool_name":"Edit","tool_input":{"file_path":"<a real file from this repo>"}}' | <cmd>`
   - `Pre|PostToolUse` on `Bash`: `echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | <cmd>`
   - `Stop`/`UserPromptSubmit`/`SessionStart`: most commands don't read stdin, so `echo '{}' | <cmd>` suffices

   Check exit code AND side effect (file actually formatted, test actually ran). If it fails you get a real error — fix (wrong package manager? tool not installed? jq path wrong?) and retest. Once it works, wrap with `2>/dev/null || true` (unless the user wants a blocking check).

4. **Write the JSON.** Merge into the target file (schema shape in the "Hook Structure" section above). If this creates `.claude/settings.local.json` for the first time, add it to .gitignore — the Write tool doesn't auto-gitignore it.

5. **Validate syntax + schema in one shot:**

   `jq -e '.hooks.<event>[] | select(.matcher == "<matcher>") | .hooks[] | select(.type == "command") | .command' <target-file>`

   Exit 0 + prints your command = correct. Exit 4 = matcher doesn't match. Exit 5 = malformed JSON or wrong nesting. A broken settings.json silently disables ALL settings from that file — fix any pre-existing malformation too.

6. **Prove the hook fires** — only for `Pre|PostToolUse` on a matcher you can trigger in-turn (`Write|Edit` via Edit, `Bash` via Bash). `Stop`/`UserPromptSubmit`/`SessionStart` fire outside this turn — skip to step 7.

   For a **formatter** on `PostToolUse`/`Write|Edit`: introduce a detectable violation via Edit (two consecutive blank lines, bad indentation, missing semicolon — something this formatter corrects; NOT trailing whitespace, Edit strips that before writing), re-read, confirm the hook **fixed** it. For **anything else**: temporarily prefix the command in settings.json with `echo "$(date) hook fired" >> /tmp/claude-hook-check.txt; `, trigger the matching tool (Edit for `Write|Edit`, a harmless `true` for `Bash`), read the sentinel file.

   **Always clean up** — revert the violation, strip the sentinel prefix — whether the proof passed or failed.

   **If proof fails but pipe-test passed and `jq -e` passed**: the settings watcher isn't watching `.claude/` — it only watches directories that had a settings file when this session started. The hook is written correctly. Tell the user to open `/hooks` once (reloads config) or restart — you can't do this yourself; `/hooks` is a user UI menu and opening it ends this turn.

7. **Handoff.** Tell the user the hook is live (or needs `/hooks`/restart per the watcher caveat). Point them at `/hooks` to review, edit, or disable it later. The UI only shows "Ran N hooks" if a hook errors or is slow — silent success is invisible by design.


## Example Workflows

### Adding a Hook

User: "Format my code after Claude writes it"

1. **Clarify**: Which formatter? (prettier, gofmt, etc.)
2. **Read**: `.claude/settings.json` (or create if missing)
3. **Merge**: Add to existing hooks, don't replace
4. **Result**:
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Write|Edit",
      "hooks": [{
        "type": "command",
        "command": "jq -r '.tool_response.filePath // .tool_input.file_path' | { read -r f; prettier --write \"$f\"; } 2>/dev/null || true"
      }]
    }]
  }
}
```

### Adding Permissions

User: "Allow npm commands without prompting"

1. **Read**: Existing permissions
2. **Merge**: Add `Bash(npm *)` to allow array
3. **Result**: Combined with existing allows

### Environment Variables

User: "Set DEBUG=true"

1. **Decide**: User settings (global) or project settings?
2. **Read**: Target file
3. **Merge**: Add to env object
```json
{ "env": { "DEBUG": "true" } }
```

## Common Mistakes to Avoid

1. **Replacing instead of merging** - Always preserve existing settings
2. **Wrong file** - Ask user if scope is unclear
3. **Invalid JSON** - Validate syntax after changes
4. **Forgetting to read first** - Always read before write

## Troubleshooting Hooks

If a hook isn't running:
1. **Check the settings file** - Read ~/.claude/settings.json or .claude/settings.json
2. **Verify JSON syntax** - Invalid JSON silently fails
3. **Check the matcher** - Does it match the tool name? (e.g., "Bash", "Write", "Edit")
4. **Check hook type** - Is it "command", "prompt", or "agent"?
5. **Test the command** - Run the hook command manually to see if it works
6. **Use --debug** - Run `claude --debug` to see hook execution logs


## Full Settings JSON Schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "$schema": {
      "description": "JSON Schema reference for Claude Code settings",
      "type": "string",
      "const": "https://json.schemastore.org/claude-code-settings.json"
    },
    "apiKeyHelper": {
      "description": "Path to a script that outputs authentication values",
      "type": "string"
    },
    "proxyAuthHelper": {
      "description": "Shell command that outputs a Proxy-Authorization header value (EAP)",
      "type": "string"
    },
    "awsCredentialExport": {
      "description": "Path to a script that exports AWS credentials",
      "type": "string"
    },
    "awsAuthRefresh": {
      "description": "Path to a script that refreshes AWS authentication",
      "type": "string"
    },
    "gcpAuthRefresh": {
      "description": "Command to refresh GCP authentication (e.g., gcloud auth application-default login)",
      "type": "string"
    },
    "fileSuggestion": {
      "description": "Custom file suggestion configuration for @ mentions",
      "type": "object",
      "properties": {
        "type": {
          "type": "string",
          "const": "command"
        },
        "command": {
          "type": "string"
        }
      },
      "required": [
        "type",
        "command"
      ]
    },
    "respectGitignore": {
      "description": "Whether file picker should respect .gitignore files (default: true). Note: .ignore files are always respected.",
      "type": "boolean"
    },
    "cleanupPeriodDays": {
      "description": "Number of days to retain chat transcripts before automatic cleanup (default: 30). Minimum 1. Use a large value for long retention; use --no-session-persistence to disable transcript writes entirely.",
      "type": "integer",
      "exclusiveMinimum": 0,
      "maximum": 9007199254740991
    },
    "skillListingMaxDescChars": {
      "description": "Per-skill description character cap in the skill listing sent to Claude (default: 1536). Descriptions longer than this are truncated. Raise to opt in to higher per-turn context cost.",
      "type": "integer",
      "exclusiveMinimum": 0,
      "maximum": 9007199254740991
    },
    "skillListingBudgetFraction": {
      "description": "Fraction of the context window (in characters) reserved for the skill listing sent to Claude (default: 0.01 = 1%). When the listing exceeds this, descriptions are shortened to fit. Raise to opt in to higher per-turn context cost.",
      "type": "number",
      "exclusiveMinimum": 0,
      "maximum": 1
    },
    "wslInheritsWindowsSettings": {
      "description": "When set to true in either admin-only Windows source — the HKLM SOFTWARE/Policies/ClaudeCode registry key or C:/Program Files/ClaudeCode/managed-settings.json — WSL reads managed settings from the full Windows policy chain (HKLM, C:/Program Files/ClaudeCode via DrvFs, HKCU) in addition to /etc/claude-code. Windows sources take priority. The flag is also required in HKCU itself for HKCU policy to apply on WSL (double opt-in: admin enables the chain, user confirms HKCU). On native Windows the flag has no effect.",
      "type": "boolean"
    },
    "env": {
      "description": "Environment variables to set for Claude Code sessions",
      "type": "object",
      "propertyNames": {
        "type": "string"
      },
      "additionalProperties": {
        "type": "string"
      }
    },
    "attribution": {
      "description": "Customize attribution text for commits and PRs. Each field defaults to the standard Claude Code attribution if not set.",
      "type": "object",
      "properties": {
        "commit": {
          "description": "Attribution text for git commits, including any trailers. Empty string hides attribution.",
          "type": "string"
        },
        "pr": {
          "description": "Attribution text for pull request descriptions. Empty string hides attribution.",
          "type": "string"
        }
      }
    },
    "includeCoAuthoredBy": {
      "description": "Deprecated: Use attribution instead. Whether to include Claude's co-authored by attribution in commits and PRs (defaults to true)",
      "type": "boolean"
    },
    "includeGitInstructions": {
      "description": "Include built-in commit and PR workflow instructions in Claude's system prompt (default: true)",
      "type": "boolean"
    },
    "permissions": {
      "description": "Tool usage permissions configuration",
      "type": "object",
      "properties": {
        "allow": {
          "description": "List of permission rules for allowed operations",
          "type": "array",
          "items": {
            "type": "string"
          }
        },
        "deny": {
          "description": "List of permission rules for denied operations",
          "type": "array",
          "items": {
            "type": "string"
          }
        },
        "ask": {
          "description": "List of permission rules that should always prompt for confirmation",
          "type": "array",
          "items": {
            "type": "string"
          }
        },
        "defaultMode": {
          "description": "Default permission mode when Claude Code needs access",
          "type": "string",
          "enum": [
            "acceptEdits",
            "auto",
            "bypassPermissions",
            "default",
            "dontAsk",
            "plan"
          ]
        },
        "disableBypassPermissionsMode": {
          "description": "Disable the ability to bypass permission prompts",
          "type": "string",
          "enum": [
            "disable"
          ]
        },
        "disableAutoMode": {
          "description": "Disable auto mode",
          "type": "string",
          "enum": [
            "disable"
          ]
        },
        "additionalDirectories": {
          "description": "Additional directories to include in the permission scope",
          "type": "array",
          "items": {
            "type": "string"
          }
        }
      },
      "additionalProperties": {}
    },
    "model": {
      "description": "Override the default model used by Claude Code",
      "type": "string"
    },
    "availableModels": {
      "description": "Allowlist of models that users can select. Accepts family aliases (\"opus\" allows any opus version), version prefixes (\"opus-4-5\" allows only that version), and full model IDs. If undefined, all models are available. If empty array, only the default model is available. Typically set in managed settings by enterprise administrators.",
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "modelOverrides": {
      "description": "Override mapping from Anthropic model ID (e.g. \"claude-opus-4-6\") to provider-specific model ID (e.g. a Bedrock inference profile ARN). Typically set in managed settings by enterprise administrators.",
      "type": "object",
      "propertyNames": {
        "type": "string"
      },
      "additionalProperties": {
        "type": "string"
      }
    },
    "enableAllProjectMcpServers": {
      "description": "Whether to automatically approve all MCP servers in the project",
      "type": "boolean"
    },
    "enabledMcpjsonServers": {
      "description": "List of approved MCP servers from .mcp.json",
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "disabledMcpjsonServers": {
      "description": "List of rejected MCP servers from .mcp.json",
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "skillOverrides": {
      "description": "Per-skill listing overrides keyed by skill name. \"name-only\" lists the skill without its description; \"user-invocable-only\" hides it from the model but keeps /name; \"off\" hides it from both. Absent = on.",
      "type": "object",
      "propertyNames": {
        "type": "string"
      },
      "additionalProperties": {
        "type": "string",
        "enum": [
          "on",
          "name-only",
          "user-invocable-only",
          "off"
        ]
      }
    },
    "allowedMcpServers": {
      "description": "Enterprise allowlist of MCP servers that can be used. Applies to all scopes including enterprise servers from managed-mcp.json. If undefined, all servers are allowed. If empty array, no servers are allowed. Denylist takes precedence - if a server is on both lists, it is denied.",
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "serverName": {
            "description": "Name of the MCP server that users are allowed to configure",
            "type": "string",
            "pattern": "^[a-zA-Z0-9_-]+$"
          },
          "serverCommand": {
            "description": "Command array [command, ...args] to match exactly for allowed stdio servers",
            "minItems": 1,
            "type": "array",
            "items": {
              "type": "string"
            }
          },
          "serverUrl": {
            "description": "URL pattern with wildcard support (e.g., \"https://*.example.com/*\") for allowed remote MCP servers",
            "type": "string"
          }
        }
      }
    },
    "deniedMcpServers": {
      "description": "Enterprise denylist of MCP servers that are explicitly blocked. If a server is on the denylist, it will be blocked across all scopes including enterprise. Denylist takes precedence over allowlist - if a server is on both lists, it is denied.",
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "serverName": {
            "description": "Name of the MCP server that is explicitly blocked",
            "type": "string",
            "pattern": "^[a-zA-Z0-9_-]+$"
          },
          "serverCommand": {
            "description": "Command array [command, ...args] to match exactly for blocked stdio servers",
            "minItems": 1,
            "type": "array",
            "items": {
              "type": "string"
            }
          },
          "serverUrl": {
            "description": "URL pattern with wildcard support (e.g., \"https://*.example.com/*\") for blocked remote MCP servers",
            "type": "string"
          }
        }
      }
    },
    "hooks": {
      "description": "Custom commands to run before/after tool executions",
      "type": "object",
      "propertyNames": {
        "anyOf": [
          {
            "type": "string",
            "enum": [
              "PreToolUse",
              "PostToolUse",
              "PostToolUseFailure",
              "PostToolBatch",
              "Notification",
              "UserPromptSubmit",
              "UserPromptExpansion",
              "SessionStart",
              "SessionEnd",
              "Stop",
              "StopFailure",
              "SubagentStart",
              "SubagentStop",
              "PreCompact",
              "PostCompact",
              "PermissionRequest",
              "PermissionDenied",
              "Setup",
              "TeammateIdle",
              "TaskCreated",
              "TaskCompleted",
              "Elicitation",
              "ElicitationResult",
              "ConfigChange",
              "WorktreeCreate",
              "WorktreeRemove",
              "InstructionsLoaded",
              "CwdChanged",
              "FileChanged"
            ]
          },
          {
            "not": {}
          }
        ]
      },
      "additionalProperties": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "matcher": {
              "description": "String pattern to match (e.g. tool names like \"Write\")",
              "type": "string"
            },
            "hooks": {
              "description": "List of hooks to execute when the matcher matches",
              "type": "array",
              "items": {
                "anyOf": [
                  {
                    "type": "object",
                    "properties": {
                      "type": {
                        "description": "Shell command hook type",
                        "type": "string",
                        "const": "command"
                      },
                      "command": {
                        "description": "Shell command to execute",
                        "type": "string"
                      },
                      "if": {
                        "description": "Permission rule syntax to filter when this hook runs (e.g., \"Bash(git *)\"). Only runs if the tool call matches the pattern. Avoids spawning hooks for non-matching commands.",
                        "type": "string"
                      },
                      "shell": {
                        "description": "Shell interpreter. 'bash' uses your $SHELL (bash/zsh/sh); 'powershell' uses pwsh. Defaults to bash.",
                        "type": "string",
                        "enum": [
                          "bash",
                          "powershell"
                        ]
                      },
                      "timeout": {
                        "description": "Timeout in seconds for this specific command",
                        "type": "number",
                        "exclusiveMinimum": 0
                      },
                      "statusMessage": {
                        "description": "Custom status message to display in spinner while hook runs",
                        "type": "string"
                      },
                      "once": {
                        "description": "If true, hook runs once and is removed after execution",
                        "type": "boolean"
                      },
                      "async": {
                        "description": "If true, hook runs in background without blocking",
                        "type": "boolean"
                      },
                      "asyncRewake": {
                        "description": "If true, hook runs in background and wakes the model on exit code 2 (blocking error). Implies async.",
                        "type": "boolean"
                      },
                      "rewakeMessage": {
                        "description": "@internal Custom prefix for the system-reminder shown to the model when an asyncRewake hook exits with code 2. The hook output is appended after this prefix.",
                        "type": "string",
                        "minLength": 1
                      },
                      "rewakeSummary": {
                        "description": "@internal One-line summary shown to the user in the terminal when an asyncRewake hook exits with code 2. Defaults to \"Stop hook feedback\".",
                        "type": "string",
                        "minLength": 1
                      }
                    },
                    "required": [
                      "type",
                      "command"
                    ]
                  },
                  {
                    "type": "object",
                    "properties": {
                      "type": {
                        "description": "LLM prompt hook type",
                        "type": "string",
                        "const": "prompt"
                      },
                      "prompt": {
                        "description": "Prompt to evaluate with LLM. Use $ARGUMENTS placeholder for hook input JSON.",
                        "type": "string"
                      },
                      "if": {
                        "description": "Permission rule syntax to filter when this hook runs (e.g., \"Bash(git *)\"). Only runs if the tool call matches the pattern. Avoids spawning hooks for non-matching commands.",
                        "type": "string"
                      },
                      "timeout": {
                        "description": "Timeout in seconds for this specific prompt evaluation",
                        "type": "number",
                        "exclusiveMinimum": 0
                      },
                      "model": {
                        "description": "Model to use for this prompt hook (e.g., \"claude-sonnet-4-6\"). If not specified, uses the default small fast model.",
                        "type": "string"
                      },
                      "statusMessage": {
                        "description": "Custom status message to display in spinner while hook runs",
                        "type": "string"
                      },
                      "once": {
                        "description": "If true, hook runs once and is removed after execution",
                        "type": "boolean"
                      }
                    },
                    "required": [
                      "type",
                      "prompt"
                    ]
                  },
                  {
                    "type": "object",
                    "properties": {
                      "type": {
                        "description": "Agentic verifier hook type",
                        "type": "string",
                        "const": "agent"
                      },
                      "prompt": {
                        "description": "Prompt describing what to verify (e.g. \"Verify that unit tests ran and passed.\"). Use $ARGUMENTS placeholder for hook input JSON.",
                        "type": "string"
                      },
                      "if": {
                        "description": "Permission rule syntax to filter when this hook runs (e.g., \"Bash(git *)\"). Only runs if the tool call matches the pattern. Avoids spawning hooks for non-matching commands.",
                        "type": "string"
                      },
                      "timeout": {
                        "description": "Timeout in seconds for agent execution (default 60)",
                        "type": "number",
                        "exclusiveMinimum": 0
                      },
                      "model": {
                        "description": "Model to use for this agent hook (e.g., \"claude-sonnet-4-6\"). If not specified, uses Haiku.",
                        "type": "string"
                      },
                      "statusMessage": {
                        "description": "Custom status message to display in spinner while hook runs",
                        "type": "string"
                      },
                      "once": {
                        "description": "If true, hook runs once and is removed after execution",
                        "type": "boolean"
                      }
                    },
                    "required": [
                      "type",
                      "prompt"
                    ]
                  },
                  {
                    "type": "object",
                    "properties": {
                      "type": {
                        "description": "HTTP hook type",
                        "type": "string",
                        "const": "http"
                      },
                      "url": {
                        "description": "URL to POST the hook input JSON to",
                        "type": "string",
                        "format": "uri"
                      },
                      "if": {
                        "description": "Permission rule syntax to filter when this hook runs (e.g., \"Bash(git *)\"). Only runs if the tool call matches the pattern. Avoids spawning hooks for non-matching commands.",
                        "type": "string"
                      },
                      "timeout": {
                        "description": "Timeout in seconds for this specific request",
                        "type": "number",
                        "exclusiveMinimum": 0
                      },
                      "headers": {
                        "description": "Additional headers to include in the request. Values may reference environment variables using $VAR_NAME or ${VAR_NAME} syntax (e.g., \"Authorization\": \"Bearer $MY_TOKEN\"). Only variables listed in allowedEnvVars will be interpolated.",
                        "type": "object",
                        "propertyNames": {
                          "type": "string"
                        },
                        "additionalProperties": {
                          "type": "string"
                        }
                      },
                      "allowedEnvVars": {
                        "description": "Explicit list of environment variable names that may be interpolated in header values. Only variables listed here will be resolved; all other $VAR references are left as empty strings. Required for env var interpolation to work.",
                        "type": "array",
                        "items": {
                          "type": "string"
                        }
                      },
                      "statusMessage": {
                        "description": "Custom status message to display in spinner while hook runs",
                        "type": "string"
                      },
                      "once": {
                        "description": "If true, hook runs once and is removed after execution",
                        "type": "boolean"
                      }
                    },
                    "required": [
                      "type",
                      "url"
                    ]
                  },
                  {
                    "type": "object",
                    "properties": {
                      "type": {
                        "description": "MCP tool hook type",
                        "type": "string",
                        "const": "mcp_tool"
                      },
                      "server": {
                        "description": "Name of an already-configured MCP server to invoke",
                        "type": "string"
                      },
                      "tool": {
                        "description": "Name of the tool on that server to call",
                        "type": "string"
                      },
                      "input": {
                        "description": "Arguments passed to the MCP tool. String values support ${path} interpolation from the hook input JSON (e.g. \"${tool_input.file_path}\").",
                        "type": "object",
                        "propertyNames": {
                          "type": "string"
                        },
                        "additionalProperties": {}
                      },
                      "if": {
                        "description": "Permission rule syntax to filter when this hook runs (e.g., \"Bash(git *)\"). Only runs if the tool call matches the pattern. Avoids spawning hooks for non-matching commands.",
                        "type": "string"
                      },
                      "timeout": {
                        "description": "Timeout in seconds for this specific tool call",
                        "type": "number",
                        "exclusiveMinimum": 0
                      },
                      "statusMessage": {
                        "description": "Custom status message to display in spinner while hook runs",
                        "type": "string"
                      },
                      "once": {
                        "description": "If true, hook runs once and is removed after execution",
                        "type": "boolean"
                      }
                    },
                    "required": [
                      "type",
                      "server",
                      "tool"
                    ]
                  }
                ]
              }
            }
          },
          "required": [
            "hooks"
          ]
        }
      }
    },
    "worktree": {
      "description": "Git worktree configuration for --worktree flag.",
      "type": "object",
      "properties": {
        "symlinkDirectories": {
          "description": "Directories to symlink from main repository to worktrees to avoid disk bloat. Must be explicitly configured - no directories are symlinked by default. Common examples: \"node_modules\", \".cache\", \".bin\"",
          "type": "array",
          "items": {
            "type": "string"
          }
        },
        "sparsePaths": {
          "description": "Directories to include when creating worktrees, via git sparse-checkout (cone mode). Dramatically faster in large monorepos — only the listed paths are written to disk.",
          "type": "array",
          "items": {
            "type": "string"
          }
        }
      }
    },
    "disableAllHooks": {
      "description": "Disable all hooks and statusLine execution",
      "type": "boolean"
    },
    "disableSkillShellExecution": {
      "description": "Disable inline shell execution in skills and custom slash commands from user, project, or plugin sources. Commands are replaced with a placeholder instead of being run.",
      "type": "boolean"
    },
    "defaultShell": {
      "description": "Default shell for input-box ! commands. Defaults to 'bash' on all platforms (no Windows auto-flip).",
      "type": "string",
      "enum": [
        "bash",
        "powershell"
      ]
    },
    "allowManagedHooksOnly": {
      "description": "When true (and set in managed settings), only hooks from managed settings run. User, project, and local hooks are ignored.",
      "type": "boolean"
    },
    "allowedHttpHookUrls": {
      "description": "Allowlist of URL patterns that HTTP hooks may target. Supports * as a wildcard (e.g. \"https://hooks.example.com/*\"). When set, HTTP hooks with non-matching URLs are blocked. If undefined, all URLs are allowed. If empty array, no HTTP hooks are allowed. Arrays merge across settings sources (same semantics as allowedMcpServers).",
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "httpHookAllowedEnvVars": {
      "description": "Allowlist of environment variable names HTTP hooks may interpolate into headers. When set, each hook's effective allowedEnvVars is the intersection with this list. If undefined, no restriction is applied. Arrays merge across settings sources (same semantics as allowedMcpServers).",
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "allowManagedPermissionRulesOnly": {
      "description": "When true (and set in managed settings), only permission rules (allow/deny/ask) from managed settings are respected. User, project, local, and CLI argument permission rules are ignored.",
      "type": "boolean"
    },
    "allowManagedMcpServersOnly": {
      "description": "When true (and set in managed settings), allowedMcpServers is only read from managed settings. deniedMcpServers still merges from all sources, so users can deny servers for themselves. Users can still add their own MCP servers, but only the admin-defined allowlist applies.",
      "type": "boolean"
    },
    "strictPluginOnlyCustomization": {
      "description": "When set in managed settings, blocks non-plugin customization sources for the listed surfaces. Array form locks specific surfaces (e.g. [\"skills\", \"hooks\"]); `true` locks all four; `false` is an explicit no-op. Blocked: ~/.claude/{surface}/, .claude/{surface}/ (project), settings.json hooks, .mcp.json. NOT blocked: managed (policySettings) sources, plugin-provided customizations. Composes with strictKnownMarketplaces for end-to-end admin control — plugins gated by marketplace allowlist, everything else blocked here.",
      "anyOf": [
        {
          "type": "boolean"
        },
        {
          "type": "array",
          "items": {
            "type": "string",
            "enum": [
              "skills",
              "agents",
              "hooks",
              "mcp"
            ]
          }
        }
      ]
    },
    "statusLine": {
      "description": "Custom status line display configuration",
      "type": "object",
      "properties": {
        "type": {
          "type": "string",
          "const": "command"
        },
        "command": {
          "type": "string"
        },
        "padding": {
          "type": "number"
        },
        "refreshInterval": {
          "description": "Re-run the status line command every N seconds in addition to event-driven updates",
          "type": "number",
          "minimum": 1
        }
      },
      "required": [
        "type",
        "command"
      ]
    },
    "prUrlTemplate": {
      "description": "URL template for PR links in the footer badge and inline messages. Placeholders: {host} {owner} {repo} {number} {url}. Example: \"https://reviews.example.com/{owner}/{repo}/pull/{number}\"",
      "type": "string"
    },
    "subagentStatusLine": {
      "description": "Custom per-subagent status line shown in the agent panel; receives row context as JSON on stdin",
      "type": "object",
      "properties": {
        "type": {
          "type": "string",
          "const": "command"
        },
        "command": {
          "type": "string"
        }
      },
      "required": [
        "type",
        "command"
      ]
    },
    "enabledPlugins": {
      "description": "Enabled plugins using plugin-id@marketplace-id format. Example: { \"formatter@anthropic-tools\": true }. Also supports extended format with version constraints.",
      "type": "object",
      "propertyNames": {
        "type": "string"
      },
      "additionalProperties": {
        "anyOf": [
          {
            "type": "array",
            "items": {
              "type": "string"
            }
          },
          {
            "type": "boolean"
          },
          {
            "not": {}
          }
        ]
      }
    },
    "extraKnownMarketplaces": {
      "description": "Additional marketplaces to make available for this repository. Typically used in repository .claude/settings.json to ensure team members have required plugin sources.",
      "type": "object",
      "propertyNames": {
        "type": "string"
      },
      "additionalProperties": {
        "type": "object",
        "properties": {
          "source": {
            "description": "Where to fetch the marketplace from",
            "anyOf": [
              {
                "type": "object",
                "properties": {
                  "source": {
                    "type": "string",
                    "const": "url"
                  },
                  "url": {
                    "description": "Direct URL to marketplace.json file",
                    "type": "string",
                    "format": "uri"
                  },
                  "headers": {
                    "description": "Custom HTTP headers (e.g., for authentication)",
                    "type": "object",
                    "propertyNames": {
                      "type": "string"
                    },
                    "additionalProperties": {
                      "type": "string"
                    }
                  }
                },
                "required": [
                  "source",
                  "url"
                ]
              },
              {
                "type": "object",
                "properties": {
                  "source": {
                    "type": "string",
                    "const": "github"
                  },
                  "repo": {
                    "description": "GitHub repository in owner/repo format",
                    "type": "string"
                  },
                  "ref": {
                    "description": "Git branch or tag to use (e.g., \"main\", \"v1.0.0\"). Defaults to repository default branch.",
                    "type": "string"
                  },
                  "path": {
                    "description": "Path to marketplace.json within repo (defaults to .claude-plugin/marketplace.json)",
                    "type": "string"
                  },
                  "sparsePaths": {
                    "description": "Directories to include via git sparse-checkout (cone mode). Use for monorepos where the marketplace lives in a subdirectory. Example: [\".claude-plugin\", \"plugins\"]. If omitted, the full repository is cloned.",
                    "type": "array",
                    "items": {
                      "type": "string"
                    }
                  }
                },
                "required": [
                  "source",
                  "repo"
                ]
              },
              {
                "type": "object",
                "properties": {
                  "source": {
                    "type": "string",
                    "const": "git"
                  },
                  "url": {
                    "description": "Full git repository URL",
                    "type": "string"
                  },
                  "ref": {
                    "description": "Git branch or tag to use (e.g., \"main\", \"v1.0.0\"). Defaults to repository default branch.",
                    "type": "string"
                  },
                  "path": {
                    "description": "Path to marketplace.json within repo (defaults to .claude-plugin/marketplace.json)",
                    "type": "string"
                  },
                  "sparsePaths": {
                    "description": "Directories to include via git sparse-checkout (cone mode). Use for monorepos where the marketplace lives in a subdirectory. Example: [\".claude-plugin\", \"plugins\"]. If omitted, the full repository is cloned.",
                    "type": "array",
                    "items": {
                      "type": "string"
                    }
                  }
                },
                "required": [
                  "source",
                  "url"
                ]
              },
              {
                "type": "object",
                "properties": {
                  "source": {
                    "type": "string",
                    "const": "npm"
                  },
                  "package": {
                    "description": "NPM package containing marketplace.json",
                    "type": "string"
                  }
                },
                "required": [
                  "source",
                  "package"
                ]
              },
              {
                "type": "object",
                "properties": {
                  "source": {
                    "type": "string",
                    "const": "file"
                  },
                  "path": {
                    "description": "Local file path to marketplace.json",
                    "type": "string"
                  }
                },
                "required": [
                  "source",
                  "path"
                ]
              },
              {
                "type": "object",
                "properties": {
                  "source": {
                    "type": "string",
                    "const": "directory"
                  },
                  "path": {
                    "description": "Local directory containing .claude-plugin/marketplace.json",
                    "type": "string"
                  }
                },
                "required": [
                  "source",
                  "path"
                ]
              },
              {
                "type": "object",
                "properties": {
                  "source": {
                    "type": "string",
                    "const": "hostPattern"
                  },
                  "hostPattern": {
                    "description": "Regex pattern to match the host/domain extracted from any marketplace source type. For github sources, matches against \"github.com\". For git sources (SSH or HTTPS), extracts the hostname from the URL. Use in strictKnownMarketplaces to allow all marketplaces from a specific host (e.g., \"^github\\.mycompany\\.com$\").",
                    "type": "string"
                  }
                },
                "required": [
                  "source",
                  "hostPattern"
                ]
              },
              {
                "type": "object",
                "properties": {
                  "source": {
                    "type": "string",
                    "const": "pathPattern"
                  },
                  "pathPattern": {
                    "description": "Regex pattern matched against the .path field of file and directory sources. Use in strictKnownMarketplaces to allow filesystem-based marketplaces alongside hostPattern restrictions for network sources. Use \".*\" to allow all filesystem paths, or a narrower pattern (e.g., \"^/opt/approved/\") to restrict to specific directories.",
                    "type": "string"
                  }
                },
                "required": [
                  "source",
                  "pathPattern"
                ]
              },
              {
                "description": "Inline marketplace manifest defined directly in settings.json. The reconciler writes a synthetic marketplace.json to the cache; diffMarketplaces detects edits via isEqual on the stored source (the plugins array is inside this object, so edits surface as sourceChanged).",
                "type": "object",
                "properties": {
                  "source": {
                    "type": "string",
                    "const": "settings"
                  },
                  "name": {
                    "description": "Marketplace name. Must match the extraKnownMarketplaces key (enforced); the synthetic manifest is written under this name. Same validation as PluginMarketplaceSchema plus reserved-name rejection — validateOfficialNameSource runs after the disk write, too late to clean up.",
                    "type": "string",
                    "minLength": 1
                  },
                  "plugins": {
                    "description": "Plugin entries declared inline in settings.json",
                    "type": "array",
                    "items": {
                      "type": "object",
                      "properties": {
                        "name": {
                          "description": "Plugin name as it appears in the target repository",
                          "type": "string",
                          "minLength": 1
                        },
                        "source": {
                          "description": "Where to fetch the plugin from. Must be a remote source — relative paths have no marketplace repository to resolve against.",
                          "anyOf": [
                            {
                              "description": "Path to the plugin root, relative to the marketplace root (the directory containing .claude-plugin/, not .claude-plugin/ itself)",
                              "type": "string",
                              "pattern": "^\\.\\/.*"
                            },
                            {
                              "description": "NPM package as plugin source",
                              "type": "object",
                              "properties": {
                                "source": {
                                  "type": "string",
                                  "const": "npm"
                                },
                                "package": {
                                  "description": "Package name (or url, or local path, or anything else that can be passed to `npm` as a package)",
                                  "anyOf": [
                                    {
                                      "type": "string"
                                    },
                                    {
                                      "type": "string"
                                    }
                                  ]
                                },
                                "version": {
                                  "description": "Specific version or version range (e.g., ^1.0.0, ~2.1.0)",
                                  "type": "string"
                                },
                                "registry": {
                                  "description": "Custom NPM registry URL (defaults to using system default, likely npmjs.org)",
                                  "type": "string",
                                  "format": "uri"
                                }
                              },
                              "required": [
                                "source",
                                "package"
                              ]
                            },
                            {
                              "type": "object",
                              "properties": {
                                "source": {
                                  "type": "string",
                                  "const": "url"
                                },
                                "url": {
                                  "description": "Full git repository URL (https:// or git@)",
                                  "type": "string"
                                },
                                "ref": {
                                  "description": "Git branch or tag to use (e.g., \"main\", \"v1.0.0\"). Defaults to repository default branch.",
                                  "type": "string"
                                },
                                "sha": {
                                  "description": "Specific commit SHA to use",
                                  "type": "string",
                                  "minLength": 40,
                                  "maxLength": 40,
                                  "pattern": "^[a-f0-9]{40}$"
                                }
                              },
                              "required": [
                                "source",
                                "url"
                              ]
                            },
                            {
                              "type": "object",
                              "properties": {
                                "source": {
                                  "type": "string",
                                  "const": "github"
                                },
                                "repo": {
                                  "description": "GitHub repository in owner/repo format",
                                  "type": "string"
                                },
                                "ref": {
                                  "description": "Git branch or tag to use (e.g., \"main\", \"v1.0.0\"). Defaults to repository default branch.",
                                  "type": "string"
                                },
                                "sha": {
                                  "description": "Specific commit SHA to use",
                                  "type": "string",
                                  "minLength": 40,
                                  "maxLength": 40,
                                  "pattern": "^[a-f0-9]{40}$"
                                }
                              },
                              "required": [
                                "source",
                                "repo"
                              ]
                            },
                            {
                              "description": "Plugin located in a subdirectory of a larger repository (monorepo). Only the specified subdirectory is materialized; the rest of the repo is not downloaded.",
                              "type": "object",
                              "properties": {
                                "source": {
                                  "type": "string",
                                  "const": "git-subdir"
                                },
                                "url": {
                                  "description": "Git repository: GitHub owner/repo shorthand, https://, or git@ URL",
                                  "type": "string"
                                },
                                "path": {
                                  "description": "Subdirectory within the repo containing the plugin (e.g., \"tools/claude-plugin\"). Cloned sparsely using partial clone (--filter=tree:0) to minimize bandwidth for monorepos.",
                                  "type": "string",
                                  "minLength": 1
                                },
                                "ref": {
                                  "description": "Git branch or tag to use (e.g., \"main\", \"v1.0.0\"). Defaults to repository default branch.",
                                  "type": "string"
                                },
                                "sha": {
                                  "description": "Specific commit SHA to use",
                                  "type": "string",
                                  "minLength": 40,
                                  "maxLength": 40,
                                  "pattern": "^[a-f0-9]{40}$"
                                }
                              },
                              "required": [
                                "source",
                                "url",
                                "path"
                              ]
                            }
                          ]
                        },
                        "description": {
                          "type": "string"
                        },
                        "version": {
                          "type": "string"
                        },
                        "strict": {
                          "type": "boolean"
                        }
                      },
                      "required": [
                        "name",
                        "source"
                      ]
                    }
                  },
                  "owner": {
                    "type": "object",
                    "properties": {
                      "name": {
                        "description": "Display name of the plugin author or organization",
                        "type": "string",
                        "minLength": 1
                      },
                      "email": {
                        "description": "Contact email for support or feedback",
                        "type": "string"
                      },
                      "url": {
                        "description": "Website, GitHub profile, or organization URL",
                        "type": "string"
                      }
                    },
                    "required": [
                      "name"
                    ]
                  }
                },
                "required": [
                  "source",
                  "name",
                  "plugins"
                ]
              }
            ]
          },
          "installLocation": {
            "description": "Local cache path where marketplace manifest is stored (auto-generated if not provided)",
            "type": "string"
          },
          "autoUpdate": {
            "description": "Whether to automatically update this marketplace and its installed plugins on startup",
            "type": "boolean"
          }
        },
        "required": [
          "source"
        ]
      }
    },
    "strictKnownMarketplaces": {
      "description": "Enterprise strict list of allowed marketplace sources. When set in managed settings, ONLY these exact sources can be added as marketplaces. The check happens BEFORE downloading, so blocked sources never touch the filesystem. Note: this is a policy gate only — it does NOT register marketplaces. To pre-register allowed marketplaces for users, also set extraKnownMarketplaces.",
      "type": "array",
      "items": {
        "anyOf": [
          {
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "url"
              },
              "url": {
                "description": "Direct URL to marketplace.json file",
                "type": "string",
                "format": "uri"
              },
              "headers": {
                "description": "Custom HTTP headers (e.g., for authentication)",
                "type": "object",
                "propertyNames": {
                  "type": "string"
                },
                "additionalProperties": {
                  "type": "string"
                }
              }
            },
            "required": [
              "source",
              "url"
            ]
          },
          {
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "github"
              },
              "repo": {
                "description": "GitHub repository in owner/repo format",
                "type": "string"
              },
              "ref": {
                "description": "Git branch or tag to use (e.g., \"main\", \"v1.0.0\"). Defaults to repository default branch.",
                "type": "string"
              },
              "path": {
                "description": "Path to marketplace.json within repo (defaults to .claude-plugin/marketplace.json)",
                "type": "string"
              },
              "sparsePaths": {
                "description": "Directories to include via git sparse-checkout (cone mode). Use for monorepos where the marketplace lives in a subdirectory. Example: [\".claude-plugin\", \"plugins\"]. If omitted, the full repository is cloned.",
                "type": "array",
                "items": {
                  "type": "string"
                }
              }
            },
            "required": [
              "source",
              "repo"
            ]
          },
          {
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "git"
              },
              "url": {
                "description": "Full git repository URL",
                "type": "string"
              },
              "ref": {
                "description": "Git branch or tag to use (e.g., \"main\", \"v1.0.0\"). Defaults to repository default branch.",
                "type": "string"
              },
              "path": {
                "description": "Path to marketplace.json within repo (defaults to .claude-plugin/marketplace.json)",
                "type": "string"
              },
              "sparsePaths": {
                "description": "Directories to include via git sparse-checkout (cone mode). Use for monorepos where the marketplace lives in a subdirectory. Example: [\".claude-plugin\", \"plugins\"]. If omitted, the full repository is cloned.",
                "type": "array",
                "items": {
                  "type": "string"
                }
              }
            },
            "required": [
              "source",
              "url"
            ]
          },
          {
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "npm"
              },
              "package": {
                "description": "NPM package containing marketplace.json",
                "type": "string"
              }
            },
            "required": [
              "source",
              "package"
            ]
          },
          {
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "file"
              },
              "path": {
                "description": "Local file path to marketplace.json",
                "type": "string"
              }
            },
            "required": [
              "source",
              "path"
            ]
          },
          {
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "directory"
              },
              "path": {
                "description": "Local directory containing .claude-plugin/marketplace.json",
                "type": "string"
              }
            },
            "required": [
              "source",
              "path"
            ]
          },
          {
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "hostPattern"
              },
              "hostPattern": {
                "description": "Regex pattern to match the host/domain extracted from any marketplace source type. For github sources, matches against \"github.com\". For git sources (SSH or HTTPS), extracts the hostname from the URL. Use in strictKnownMarketplaces to allow all marketplaces from a specific host (e.g., \"^github\\.mycompany\\.com$\").",
                "type": "string"
              }
            },
            "required": [
              "source",
              "hostPattern"
            ]
          },
          {
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "pathPattern"
              },
              "pathPattern": {
                "description": "Regex pattern matched against the .path field of file and directory sources. Use in strictKnownMarketplaces to allow filesystem-based marketplaces alongside hostPattern restrictions for network sources. Use \".*\" to allow all filesystem paths, or a narrower pattern (e.g., \"^/opt/approved/\") to restrict to specific directories.",
                "type": "string"
              }
            },
            "required": [
              "source",
              "pathPattern"
            ]
          },
          {
            "description": "Inline marketplace manifest defined directly in settings.json. The reconciler writes a synthetic marketplace.json to the cache; diffMarketplaces detects edits via isEqual on the stored source (the plugins array is inside this object, so edits surface as sourceChanged).",
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "settings"
              },
              "name": {
                "description": "Marketplace name. Must match the extraKnownMarketplaces key (enforced); the synthetic manifest is written under this name. Same validation as PluginMarketplaceSchema plus reserved-name rejection — validateOfficialNameSource runs after the disk write, too late to clean up.",
                "type": "string",
                "minLength": 1
              },
              "plugins": {
                "description": "Plugin entries declared inline in settings.json",
                "type": "array",
                "items": {
                  "type": "object",
                  "properties": {
                    "name": {
                      "description": "Plugin name as it appears in the target repository",
                      "type": "string",
                      "minLength": 1
                    },
                    "source": {
                      "description": "Where to fetch the plugin from. Must be a remote source — relative paths have no marketplace repository to resolve against.",
                      "anyOf": [
                        {
                          "description": "Path to the plugin root, relative to the marketplace root (the directory containing .claude-plugin/, not .claude-plugin/ itself)",
                          "type": "string",
                          "pattern": "^\\.\\/.*"
                        },
                        {
                          "description": "NPM package as plugin source",
                          "type": "object",
                          "properties": {
                            "source": {
                              "type": "string",
                              "const": "npm"
                            },
                            "package": {
                              "description": "Package name (or url, or local path, or anything else that can be passed to `npm` as a package)",
                              "anyOf": [
                                {
                                  "type": "string"
                                },
                                {
                                  "type": "string"
                                }
                              ]
                            },
                            "version": {
                              "description": "Specific version or version range (e.g., ^1.0.0, ~2.1.0)",
                              "type": "string"
                            },
                            "registry": {
                              "description": "Custom NPM registry URL (defaults to using system default, likely npmjs.org)",
                              "type": "string",
                              "format": "uri"
                            }
                          },
                          "required": [
                            "source",
                            "package"
                          ]
                        },
                        {
                          "type": "object",
                          "properties": {
                            "source": {
                              "type": "string",
                              "const": "url"
                            },
                            "url": {
                              "description": "Full git repository URL (https:// or git@)",
                              "type": "string"
                            },
                            "ref": {
                              "description": "Git branch or tag to use (e.g., \"main\", \"v1.0.0\"). Defaults to repository default branch.",
                              "type": "string"
                            },
                            "sha": {
                              "description": "Specific commit SHA to use",
                              "type": "string",
                              "minLength": 40,
                              "maxLength": 40,
                              "pattern": "^[a-f0-9]{40}$"
                            }
                          },
                          "required": [
                            "source",
                            "url"
                          ]
                        },
                        {
                          "type": "object",
                          "properties": {
                            "source": {
                              "type": "string",
                              "const": "github"
                            },
                            "repo": {
                              "description": "GitHub repository in owner/repo format",
                              "type": "string"
                            },
                            "ref": {
                              "description": "Git branch or tag to use (e.g., \"main\", \"v1.0.0\"). Defaults to repository default branch.",
                              "type": "string"
                            },
                            "sha": {
                              "description": "Specific commit SHA to use",
                              "type": "string",
                              "minLength": 40,
                              "maxLength": 40,
                              "pattern": "^[a-f0-9]{40}$"
                            }
                          },
                          "required": [
                            "source",
                            "repo"
                          ]
                        },
                        {
                          "description": "Plugin located in a subdirectory of a larger repository (monorepo). Only the specified subdirectory is materialized; the rest of the repo is not downloaded.",
                          "type": "object",
                          "properties": {
                            "source": {
                              "type": "string",
                              "const": "git-subdir"
                            },
                            "url": {
                              "description": "Git repository: GitHub owner/repo shorthand, https://, or git@ URL",
                              "type": "string"
                            },
                            "path": {
                              "description": "Subdirectory within the repo containing the plugin (e.g., \"tools/claude-plugin\"). Cloned sparsely using partial clone (--filter=tree:0) to minimize bandwidth for monorepos.",
                              "type": "string",
                              "minLength": 1
                            },
                            "ref": {
                              "description": "Git branch or tag to use (e.g., \"main\", \"v1.0.0\"). Defaults to repository default branch.",
                              "type": "string"
                            },
                            "sha": {
                              "description": "Specific commit SHA to use",
                              "type": "string",
                              "minLength": 40,
                              "maxLength": 40,
                              "pattern": "^[a-f0-9]{40}$"
                            }
                          },
                          "required": [
                            "source",
                            "url",
                            "path"
                          ]
                        }
                      ]
                    },
                    "description": {
                      "type": "string"
                    },
                    "version": {
                      "type": "string"
                    },
                    "strict": {
                      "type": "boolean"
                    }
                  },
                  "required": [
                    "name",
                    "source"
                  ]
                }
              },
              "owner": {
                "type": "object",
                "properties": {
                  "name": {
                    "description": "Display name of the plugin author or organization",
                    "type": "string",
                    "minLength": 1
                  },
                  "email": {
                    "description": "Contact email for support or feedback",
                    "type": "string"
                  },
                  "url": {
                    "description": "Website, GitHub profile, or organization URL",
                    "type": "string"
                  }
                },
                "required": [
                  "name"
                ]
              }
            },
            "required": [
              "source",
              "name",
              "plugins"
            ]
          }
        ]
      }
    },
    "blockedMarketplaces": {
      "description": "Enterprise blocklist of marketplace sources. When set in managed settings, these exact sources are blocked from being added as marketplaces. The check happens BEFORE downloading, so blocked sources never touch the filesystem.",
      "type": "array",
      "items": {
        "anyOf": [
          {
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "url"
              },
              "url": {
                "description": "Direct URL to marketplace.json file",
                "type": "string",
                "format": "uri"
              },
              "headers": {
                "description": "Custom HTTP headers (e.g., for authentication)",
                "type": "object",
                "propertyNames": {
                  "type": "string"
                },
                "additionalProperties": {
                  "type": "string"
                }
              }
            },
            "required": [
              "source",
              "url"
            ]
          },
          {
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "github"
              },
              "repo": {
                "description": "GitHub repository in owner/repo format",
                "type": "string"
              },
              "ref": {
                "description": "Git branch or tag to use (e.g., \"main\", \"v1.0.0\"). Defaults to repository default branch.",
                "type": "string"
              },
              "path": {
                "description": "Path to marketplace.json within repo (defaults to .claude-plugin/marketplace.json)",
                "type": "string"
              },
              "sparsePaths": {
                "description": "Directories to include via git sparse-checkout (cone mode). Use for monorepos where the marketplace lives in a subdirectory. Example: [\".claude-plugin\", \"plugins\"]. If omitted, the full repository is cloned.",
                "type": "array",
                "items": {
                  "type": "string"
                }
              }
            },
            "required": [
              "source",
              "repo"
            ]
          },
          {
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "git"
              },
              "url": {
                "description": "Full git repository URL",
                "type": "string"
              },
              "ref": {
                "description": "Git branch or tag to use (e.g., \"main\", \"v1.0.0\"). Defaults to repository default branch.",
                "type": "string"
              },
              "path": {
                "description": "Path to marketplace.json within repo (defaults to .claude-plugin/marketplace.json)",
                "type": "string"
              },
              "sparsePaths": {
                "description": "Directories to include via git sparse-checkout (cone mode). Use for monorepos where the marketplace lives in a subdirectory. Example: [\".claude-plugin\", \"plugins\"]. If omitted, the full repository is cloned.",
                "type": "array",
                "items": {
                  "type": "string"
                }
              }
            },
            "required": [
              "source",
              "url"
            ]
          },
          {
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "npm"
              },
              "package": {
                "description": "NPM package containing marketplace.json",
                "type": "string"
              }
            },
            "required": [
              "source",
              "package"
            ]
          },
          {
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "file"
              },
              "path": {
                "description": "Local file path to marketplace.json",
                "type": "string"
              }
            },
            "required": [
              "source",
              "path"
            ]
          },
          {
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "directory"
              },
              "path": {
                "description": "Local directory containing .claude-plugin/marketplace.json",
                "type": "string"
              }
            },
            "required": [
              "source",
              "path"
            ]
          },
          {
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "hostPattern"
              },
              "hostPattern": {
                "description": "Regex pattern to match the host/domain extracted from any marketplace source type. For github sources, matches against \"github.com\". For git sources (SSH or HTTPS), extracts the hostname from the URL. Use in strictKnownMarketplaces to allow all marketplaces from a specific host (e.g., \"^github\\.mycompany\\.com$\").",
                "type": "string"
              }
            },
            "required": [
              "source",
              "hostPattern"
            ]
          },
          {
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "pathPattern"
              },
              "pathPattern": {
                "description": "Regex pattern matched against the .path field of file and directory sources. Use in strictKnownMarketplaces to allow filesystem-based marketplaces alongside hostPattern restrictions for network sources. Use \".*\" to allow all filesystem paths, or a narrower pattern (e.g., \"^/opt/approved/\") to restrict to specific directories.",
                "type": "string"
              }
            },
            "required": [
              "source",
              "pathPattern"
            ]
          },
          {
            "description": "Inline marketplace manifest defined directly in settings.json. The reconciler writes a synthetic marketplace.json to the cache; diffMarketplaces detects edits via isEqual on the stored source (the plugins array is inside this object, so edits surface as sourceChanged).",
            "type": "object",
            "properties": {
              "source": {
                "type": "string",
                "const": "settings"
              },
              "name": {
                "description": "Marketplace name. Must match the extraKnownMarketplaces key (enforced); the synthetic manifest is written under this name. Same validation as PluginMarketplaceSchema plus reserved-name rejection — validateOfficialNameSource runs after the disk write, too late to clean up.",
                "type": "string",
                "minLength": 1
              },
              "plugins": {
                "description": "Plugin entries declared inline in settings.json",
                "type": "array",
                "items": {
                  "type": "object",
                  "properties": {
                    "name": {
                      "description": "Plugin name as it appears in the target repository",
                      "type": "string",
                      "minLength": 1
                    },
                    "source": {
                      "description": "Where to fetch the plugin from. Must be a remote source — relative paths have no marketplace repository to resolve against.",
                      "anyOf": [
                        {
                          "description": "Path to the plugin root, relative to the marketplace root (the directory containing .claude-plugin/, not .claude-plugin/ itself)",
                          "type": "string",
                          "pattern": "^\\.\\/.*"
                        },
                        {
                          "description": "NPM package as plugin source",
                          "type": "object",
                          "properties": {
                            "source": {
                              "type": "string",
                              "const": "npm"
                            },
                            "package": {
                              "description": "Package name (or url, or local path, or anything else that can be passed to `npm` as a package)",
                              "anyOf": [
                                {
                                  "type": "string"
                                },
                                {
                                  "type": "string"
                                }
                              ]
                            },
                            "version": {
                              "description": "Specific version or version range (e.g., ^1.0.0, ~2.1.0)",
                              "type": "string"
                            },
                            "registry": {
                              "description": "Custom NPM registry URL (defaults to using system default, likely npmjs.org)",
                              "type": "string",
                              "format": "uri"
                            }
                          },
                          "required": [
                            "source",
                            "package"
                          ]
                        },
                        {
                          "type": "object",
                          "properties": {
                            "source": {
                              "type": "string",
                              "const": "url"
                            },
                            "url": {
                              "description": "Full git repository URL (https:// or git@)",
                              "type": "string"
                            },
                            "ref": {
                              "description": "Git branch or tag to use (e.g., \"main\", \"v1.0.0\"). Defaults to repository default branch.",
                              "type": "string"
                            },
                            "sha": {
                              "description": "Specific commit SHA to use",
                              "type": "string",
                              "minLength": 40,
                              "maxLength": 40,
                              "pattern": "^[a-f0-9]{40}$"
                            }
                          },
                          "required": [
                            "source",
                            "url"
                          ]
                        },
                        {
                          "type": "object",
                          "properties": {
                            "source": {
                              "type": "string",
                              "const": "github"
                            },
                            "repo": {
                              "description": "GitHub repository in owner/repo format",
                              "type": "string"
                            },
                            "ref": {
                              "description": "Git branch or tag to use (e.g., \"main\", \"v1.0.0\"). Defaults to repository default branch.",
                              "type": "string"
                            },
                            "sha": {
                              "description": "Specific commit SHA to use",
                              "type": "string",
                              "minLength": 40,
                              "maxLength": 40,
                              "pattern": "^[a-f0-9]{40}$"
                            }
                          },
                          "required": [
                            "source",
                            "repo"
                          ]
                        },
                        {
                          "description": "Plugin located in a subdirectory of a larger repository (monorepo). Only the specified subdirectory is materialized; the rest of the repo is not downloaded.",
                          "type": "object",
                          "properties": {
                            "source": {
                              "type": "string",
                              "const": "git-subdir"
                            },
                            "url": {
                              "description": "Git repository: GitHub owner/repo shorthand, https://, or git@ URL",
                              "type": "string"
                            },
                            "path": {
                              "description": "Subdirectory within the repo containing the plugin (e.g., \"tools/claude-plugin\"). Cloned sparsely using partial clone (--filter=tree:0) to minimize bandwidth for monorepos.",
                              "type": "string",
                              "minLength": 1
                            },
                            "ref": {
                              "description": "Git branch or tag to use (e.g., \"main\", \"v1.0.0\"). Defaults to repository default branch.",
                              "type": "string"
                            },
                            "sha": {
                              "description": "Specific commit SHA to use",
                              "type": "string",
                              "minLength": 40,
                              "maxLength": 40,
                              "pattern": "^[a-f0-9]{40}$"
                            }
                          },
                          "required": [
                            "source",
                            "url",
                            "path"
                          ]
                        }
                      ]
                    },
                    "description": {
                      "type": "string"
                    },
                    "version": {
                      "type": "string"
                    },
                    "strict": {
                      "type": "boolean"
                    }
                  },
                  "required": [
                    "name",
                    "source"
                  ]
                }
              },
              "owner": {
                "type": "object",
                "properties": {
                  "name": {
                    "description": "Display name of the plugin author or organization",
                    "type": "string",
                    "minLength": 1
                  },
                  "email": {
                    "description": "Contact email for support or feedback",
                    "type": "string"
                  },
                  "url": {
                    "description": "Website, GitHub profile, or organization URL",
                    "type": "string"
                  }
                },
                "required": [
                  "name"
                ]
              }
            },
            "required": [
              "source",
              "name",
              "plugins"
            ]
          }
        ]
      }
    },
    "forceLoginMethod": {
      "description": "Force a specific login method: \"claudeai\" for Claude Pro/Max, \"console\" for Console billing",
      "type": "string",
      "enum": [
        "claudeai",
        "console"
      ]
    },
    "forceLoginOrgUUID": {
      "description": "Organization UUID to require for OAuth login. Accepts a single UUID string or an array of UUIDs (any one is permitted). When set in managed settings, login fails if the authenticated account does not belong to a listed organization.",
      "anyOf": [
        {
          "type": "string"
        },
        {
          "type": "array",
          "items": {
            "type": "string"
          }
        }
      ]
    },
    "forceRemoteSettingsRefresh": {
      "description": "When set in managed settings, the CLI blocks startup until remote managed settings are freshly fetched, and exits if the fetch fails",
      "type": "boolean"
    },
    "otelHeadersHelper": {
      "description": "Path to a script that outputs OpenTelemetry headers",
      "type": "string"
    },
    "outputStyle": {
      "description": "Controls the output style for assistant responses",
      "type": "string"
    },
    "viewMode": {
      "description": "Default transcript view mode on startup",
      "type": "string",
      "enum": [
        "default",
        "verbose",
        "focus"
      ]
    },
    "language": {
      "description": "Preferred language for Claude responses and voice dictation (e.g., \"japanese\", \"spanish\")",
      "type": "string"
    },
    "skipWebFetchPreflight": {
      "description": "Skip the WebFetch blocklist check for enterprise environments with restrictive security policies",
      "type": "boolean"
    },
    "sandbox": {
      "type": "object",
      "properties": {
        "enabled": {
          "type": "boolean"
        },
        "failIfUnavailable": {
          "description": "Exit with an error at startup if sandbox.enabled is true but the sandbox cannot start (missing dependencies or unsupported platform). When false (default), a warning is shown and commands run unsandboxed. Intended for managed-settings deployments that require sandboxing as a hard gate.",
          "type": "boolean"
        },
        "autoAllowBashIfSandboxed": {
          "type": "boolean"
        },
        "allowUnsandboxedCommands": {
          "description": "Allow commands to run outside the sandbox via the dangerouslyDisableSandbox parameter. When false, the dangerouslyDisableSandbox parameter is completely ignored and all commands must run sandboxed. Default: true.",
          "type": "boolean"
        },
        "network": {
          "type": "object",
          "properties": {
            "allowedDomains": {
              "type": "array",
              "items": {
                "type": "string"
              }
            },
            "deniedDomains": {
              "description": "Domains that are always blocked, even if matched by allowedDomains. Supports the same wildcard syntax as allowedDomains. Merged from all settings sources regardless of allowManagedDomainsOnly.",
              "type": "array",
              "items": {
                "type": "string"
              }
            },
            "allowManagedDomainsOnly": {
              "description": "When true (and set in managed settings), only allowedDomains and WebFetch(domain:...) allow rules from managed settings are respected. User, project, local, and flag settings domains are ignored. Denied domains are still respected from all sources.",
              "type": "boolean"
            },
            "allowUnixSockets": {
              "description": "macOS only: Unix socket paths to allow. Ignored on Linux (seccomp cannot filter by path).",
              "type": "array",
              "items": {
                "type": "string"
              }
            },
            "allowAllUnixSockets": {
              "description": "If true, allow all Unix sockets (disables blocking on both platforms).",
              "type": "boolean"
            },
            "allowLocalBinding": {
              "type": "boolean"
            },
            "allowMachLookup": {
              "description": "macOS only: Additional XPC/Mach service names to allow looking up. Supports trailing-wildcard prefix matching (e.g., \"com.apple.coresimulator.*\"). Needed for tools that communicate via XPC such as the iOS Simulator or Playwright.",
              "type": "array",
              "items": {
                "type": "string"
              }
            },
            "httpProxyPort": {
              "type": "number"
            },
            "socksProxyPort": {
              "type": "number"
            }
          }
        },
        "filesystem": {
          "type": "object",
          "properties": {
            "allowWrite": {
              "description": "Additional paths to allow writing within the sandbox. Merged with paths from Edit(...) allow permission rules.",
              "type": "array",
              "items": {
                "type": "string"
              }
            },
            "denyWrite": {
              "description": "Additional paths to deny writing within the sandbox. Merged with paths from Edit(...) deny permission rules.",
              "type": "array",
              "items": {
                "type": "string"
              }
            },
            "denyRead": {
              "description": "Additional paths to deny reading within the sandbox. Merged with paths from Read(...) deny permission rules.",
              "type": "array",
              "items": {
                "type": "string"
              }
            },
            "allowRead": {
              "description": "Paths to re-allow reading within denyRead regions. Takes precedence over denyRead for matching paths.",
              "type": "array",
              "items": {
                "type": "string"
              }
            },
            "allowManagedReadPathsOnly": {
              "description": "When true (set in managed settings), only allowRead paths from policySettings are used.",
              "type": "boolean"
            }
          }
        },
        "ignoreViolations": {
          "type": "object",
          "propertyNames": {
            "type": "string"
          },
          "additionalProperties": {
            "type": "array",
            "items": {
              "type": "string"
            }
          }
        },
        "enableWeakerNestedSandbox": {
          "type": "boolean"
        },
        "enableWeakerNetworkIsolation": {
          "description": "macOS only: Allow access to com.apple.trustd.agent in the sandbox. Needed for Go-based CLI tools (gh, gcloud, terraform, etc.) to verify TLS certificates when using httpProxyPort with a MITM proxy and custom CA. **Reduces security** — opens a potential data exfiltration vector through the trustd service. Default: false",
          "type": "boolean"
        },
        "excludedCommands": {
          "type": "array",
          "items": {
            "type": "string"
          }
        },
        "ripgrep": {
          "description": "Custom ripgrep configuration for bundled ripgrep support",
          "type": "object",
          "properties": {
            "command": {
              "type": "string"
            },
            "args": {
              "type": "array",
              "items": {
                "type": "string"
              }
            }
          },
          "required": [
            "command"
          ]
        }
      },
      "additionalProperties": {}
    },
    "feedbackSurveyRate": {
      "description": "Probability (0–1) that the session quality survey appears when eligible. 0.05 is a reasonable starting point.",
      "type": "number",
      "minimum": 0,
      "maximum": 1
    },
    "spinnerTipsEnabled": {
      "description": "Whether to show tips in the spinner",
      "type": "boolean"
    },
    "spinnerVerbs": {
      "description": "Customize spinner verbs. mode: \"append\" adds verbs to defaults, \"replace\" uses only your verbs.",
      "type": "object",
      "properties": {
        "mode": {
          "type": "string",
          "enum": [
            "append",
            "replace"
          ]
        },
        "verbs": {
          "type": "array",
          "items": {
            "type": "string"
          }
        }
      },
      "required": [
        "mode",
        "verbs"
      ]
    },
    "spinnerTipsOverride": {
      "description": "Override spinner tips. tips: array of tip strings. excludeDefault: if true, only show custom tips (default: false).",
      "type": "object",
      "properties": {
        "excludeDefault": {
          "type": "boolean"
        },
        "tips": {
          "type": "array",
          "items": {
            "type": "string"
          }
        }
      },
      "required": [
        "tips"
      ]
    },
    "syntaxHighlightingDisabled": {
      "description": "Whether to disable syntax highlighting in diffs",
      "type": "boolean"
    },
    "terminalTitleFromRename": {
      "description": "Whether /rename updates the terminal tab title (defaults to true). Set to false to keep auto-generated topic titles.",
      "type": "boolean"
    },
    "alwaysThinkingEnabled": {
      "description": "When false, thinking is disabled. When absent or true, thinking is enabled automatically for supported models.",
      "type": "boolean"
    },
    "effortLevel": {
      "description": "Persisted effort level for supported models.",
      "type": "string",
      "enum": [
        "low",
        "medium",
        "high",
        "xhigh"
      ]
    },
    "autoCompactWindow": {
      "description": "Auto-compact window size",
      "type": "integer",
      "minimum": 100000,
      "maximum": 1000000
    },
    "advisorModel": {
      "description": "Advisor model for the server-side advisor tool.",
      "type": "string"
    },
    "fastMode": {
      "description": "When true, fast mode is enabled. When absent or false, fast mode is off.",
      "type": "boolean"
    },
    "fastModePerSessionOptIn": {
      "description": "When true, fast mode does not persist across sessions. Each session starts with fast mode off.",
      "type": "boolean"
    },
    "promptSuggestionEnabled": {
      "description": "When false, prompt suggestions are disabled. When absent or true, prompt suggestions are enabled.",
      "type": "boolean"
    },
    "awaySummaryEnabled": {
      "description": "@internal When false, the session recap (shown when you return after being away for 5+ minutes) is disabled. When absent or true, recap is enabled. Hidden from public SDK types until external launch.",
      "type": "boolean"
    },
    "showClearContextOnPlanAccept": {
      "description": "When true, the plan-approval dialog offers a \"clear context\" option. Defaults to false.",
      "type": "boolean"
    },
    "agent": {
      "description": "Name of an agent (built-in or custom) to use for the main thread. Applies the agent's system prompt, tool restrictions, and model.",
      "type": "string"
    },
    "companyAnnouncements": {
      "description": "Company announcements to display at startup (one will be randomly selected if multiple are provided)",
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "pluginConfigs": {
      "description": "Per-plugin configuration including MCP server user configs, keyed by plugin ID (plugin@marketplace format)",
      "type": "object",
      "propertyNames": {
        "type": "string"
      },
      "additionalProperties": {
        "type": "object",
        "properties": {
          "mcpServers": {
            "description": "User configuration values for MCP servers keyed by server name",
            "type": "object",
            "propertyNames": {
              "type": "string"
            },
            "additionalProperties": {
              "type": "object",
              "propertyNames": {
                "type": "string"
              },
              "additionalProperties": {
                "anyOf": [
                  {
                    "type": "string"
                  },
                  {
                    "type": "number"
                  },
                  {
                    "type": "boolean"
                  },
                  {
                    "type": "array",
                    "items": {
                      "type": "string"
                    }
                  }
                ]
              }
            }
          },
          "options": {
            "description": "Non-sensitive option values from plugin manifest userConfig, keyed by option name. Sensitive values go to secure storage instead.",
            "type": "object",
            "propertyNames": {
              "type": "string"
            },
            "additionalProperties": {
              "anyOf": [
                {
                  "type": "string"
                },
                {
                  "type": "number"
                },
                {
                  "type": "boolean"
                },
                {
                  "type": "array",
                  "items": {
                    "type": "string"
                  }
                }
              ]
            }
          }
        }
      }
    },
    "remote": {
      "description": "Remote session configuration",
      "type": "object",
      "properties": {
        "defaultEnvironmentId": {
          "description": "Default environment ID to use for remote sessions",
          "type": "string"
        }
      }
    },
    "autoUpdatesChannel": {
      "description": "Release channel for auto-updates (latest or stable)",
      "type": "string",
      "enum": [
        "latest",
        "stable",
        "rc"
      ]
    },
    "minimumVersion": {
      "description": "Minimum version to stay on - prevents downgrades when switching to stable channel",
      "type": "string"
    },
    "plansDirectory": {
      "description": "Custom directory for plan files, relative to project root. If not set, defaults to ~/.claude/plans/",
      "type": "string"
    },
    "tui": {
      "description": "Terminal UI renderer. \"fullscreen\" uses the flicker-free alt-screen renderer with virtualized scrollback (equivalent to CLAUDE_CODE_NO_FLICKER=1). \"default\" uses the classic main-screen renderer.",
      "type": "string",
      "enum": [
        "default",
        "fullscreen"
      ]
    },
    "voice": {
      "description": "Voice mode settings (hold-to-talk / tap-to-toggle dictation)",
      "type": "object",
      "properties": {
        "enabled": {
          "type": "boolean"
        },
        "mode": {
          "description": "'hold' (default): hold to talk. 'tap': tap to start, tap to stop+submit.",
          "type": "string",
          "enum": [
            "hold",
            "tap"
          ]
        },
        "autoSubmit": {
          "description": "Submit the prompt when hold-to-talk is released (hold mode only)",
          "type": "boolean"
        }
      }
    },
    "channelsEnabled": {
      "description": "Teams/Enterprise opt-in for channel notifications (MCP servers with the claude/channel capability pushing inbound messages). Default off. Set true to allow; users then select servers via --channels.",
      "type": "boolean"
    },
    "allowedChannelPlugins": {
      "description": "Teams/Enterprise allowlist of channel plugins. When set, replaces the default Anthropic allowlist — admins decide which plugins may push inbound messages. Undefined falls back to the default. Requires channelsEnabled: true.",
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "marketplace": {
            "type": "string"
          },
          "plugin": {
            "type": "string"
          }
        },
        "required": [
          "marketplace",
          "plugin"
        ]
      }
    },
    "prefersReducedMotion": {
      "description": "Reduce or disable animations for accessibility (spinner shimmer, flash effects, etc.)",
      "type": "boolean"
    },
    "autoMemoryEnabled": {
      "description": "Enable auto-memory for this project. When false, Claude will not read from or write to the auto-memory directory.",
      "type": "boolean"
    },
    "autoMemoryDirectory": {
      "description": "Custom directory path for auto-memory storage. Supports ~/ prefix for home directory expansion. Ignored if set in projectSettings (checked-in .claude/settings.json) for security. When unset, defaults to ~/.claude/projects/<sanitized-cwd>/memory/.",
      "type": "string"
    },
    "autoDreamEnabled": {
      "description": "Enable background memory consolidation (auto-dream). When set, overrides the server-side default.",
      "type": "boolean"
    },
    "showThinkingSummaries": {
      "description": "Show thinking summaries in the transcript view (ctrl+o). Default: false.",
      "type": "boolean"
    },
    "skipDangerousModePermissionPrompt": {
      "description": "Whether the user has accepted the bypass permissions mode dialog",
      "type": "boolean"
    },
    "disableAutoMode": {
      "description": "Disable auto mode",
      "type": "string",
      "enum": [
        "disable"
      ]
    },
    "sshConfigs": {
      "description": "SSH connection configurations for remote environments. Typically set in managed settings by enterprise administrators to pre-configure SSH connections for team members.",
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "id": {
            "description": "Unique identifier for this SSH config. Used to match configs across settings sources.",
            "type": "string"
          },
          "name": {
            "description": "Display name for the SSH connection",
            "type": "string"
          },
          "sshHost": {
            "description": "SSH host in format \"user@hostname\" or \"hostname\", or a host alias from ~/.ssh/config",
            "type": "string"
          },
          "sshPort": {
            "description": "SSH port (default: 22)",
            "type": "integer",
            "minimum": -9007199254740991,
            "maximum": 9007199254740991
          },
          "sshIdentityFile": {
            "description": "Path to SSH identity file (private key)",
            "type": "string"
          },
          "startDirectory": {
            "description": "Default working directory on the remote host. Supports tilde expansion (e.g. ~/projects). If not specified, defaults to the remote user home directory. Can be overridden by the [dir] positional argument in `claude ssh <config> [dir]`.",
            "type": "string"
          }
        },
        "required": [
          "id",
          "name",
          "sshHost"
        ]
      }
    },
    "claudeMdExcludes": {
      "description": "Glob patterns or absolute paths of CLAUDE.md files to exclude from loading. Patterns are matched against absolute file paths using picomatch. Only applies to User, Project, and Local memory types (Managed/policy files cannot be excluded). Examples: \"/home/user/monorepo/CLAUDE.md\", \"**/code/CLAUDE.md\", \"**/some-dir/.claude/rules/**\"",
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "pluginTrustMessage": {
      "description": "Custom message to append to the plugin trust warning shown before installation. Only read from policy settings (managed-settings.json / MDM). Useful for enterprise administrators to add organization-specific context (e.g., \"All plugins from our internal marketplace are vetted and approved.\").",
      "type": "string"
    },
    "theme": {
      "description": "Color theme for the UI",
      "anyOf": [
        {
          "type": "string",
          "enum": [
            "auto",
            "dark",
            "light",
            "light-daltonized",
            "dark-daltonized",
            "light-ansi",
            "dark-ansi"
          ]
        },
        {
          "type": "string",
          "pattern": "^custom:.*"
        }
      ]
    },
    "editorMode": {
      "description": "Key binding mode for the prompt input",
      "type": "string",
      "enum": [
        "normal",
        "vim"
      ]
    },
    "verbose": {
      "description": "Show full tool output instead of truncated summaries",
      "type": "boolean"
    },
    "preferredNotifChannel": {
      "description": "Preferred OS notification channel",
      "type": "string",
      "enum": [
        "auto",
        "iterm2",
        "iterm2_with_bell",
        "terminal_bell",
        "kitty",
        "ghostty",
        "notifications_disabled"
      ]
    },
    "autoCompactEnabled": {
      "description": "Automatically compact conversation when context fills",
      "type": "boolean"
    },
    "autoScrollEnabled": {
      "description": "Auto-scroll the conversation view to bottom (fullscreen mode only)",
      "type": "boolean"
    },
    "fileCheckpointingEnabled": {
      "description": "Snapshot files before edits so /rewind can restore them",
      "type": "boolean"
    },
    "showTurnDuration": {
      "description": "Show \"Cooked for Nm Ns\" after each assistant turn",
      "type": "boolean"
    },
    "showMessageTimestamps": {
      "description": "Stamp each assistant message with its arrival time",
      "type": "boolean"
    },
    "terminalProgressBarEnabled": {
      "description": "Emit OSC 9;4 progress sequences during long operations",
      "type": "boolean"
    },
    "todoFeatureEnabled": {
      "description": "Enable the todo / task tracking panel",
      "type": "boolean"
    },
    "teammateMode": {
      "description": "How spawned teammates execute (tmux, in-process, auto)",
      "type": "string",
      "enum": [
        "auto",
        "tmux",
        "in-process"
      ]
    },
    "remoteControlAtStartup": {
      "description": "Start Remote Control bridge automatically each session",
      "type": "boolean"
    },
    "autoUploadSessions": {
      "description": "Mirror local sessions to claude.ai as view-only (no remote control)",
      "type": "boolean"
    },
    "inputNeededNotifEnabled": {
      "description": "Push to mobile when a permission prompt or question is waiting",
      "type": "boolean"
    },
    "agentPushNotifEnabled": {
      "description": "Allow Claude to push proactive mobile notifications",
      "type": "boolean"
    },
    "skipAutoPermissionPrompt": {
      "description": "Whether the user has accepted the auto mode opt-in dialog",
      "type": "boolean"
    },
    "useAutoModeDuringPlan": {
      "description": "Whether plan mode uses auto mode semantics when auto mode is available (default: true)",
      "type": "boolean"
    },
    "autoMode": {
      "description": "Auto mode classifier prompt customization",
      "type": "object",
      "properties": {
        "allow": {
          "description": "Rules for the auto mode classifier allow section. Include the literal string \"$defaults\" to inherit the built-in rules at that position.",
          "type": "array",
          "items": {
            "type": "string"
          }
        },
        "soft_deny": {
          "description": "Rules for the auto mode classifier deny section. Include the literal string \"$defaults\" to inherit the built-in rules at that position.",
          "type": "array",
          "items": {
            "type": "string"
          }
        },
        "environment": {
          "description": "Entries for the auto mode classifier environment section. Include the literal string \"$defaults\" to inherit the built-in entries at that position.",
          "type": "array",
          "items": {
            "type": "string"
          }
        }
      }
    },
    "disableDeepLinkRegistration": {
      "description": "Prevent claude-cli:// protocol handler registration with the OS",
      "type": "string",
      "enum": [
        "disable"
      ]
    },
    "voiceEnabled": {
      "description": "Enable voice mode (hold-to-talk dictation)",
      "type": "boolean"
    },
    "defaultView": {
      "description": "Default transcript view: chat (SendUserMessage checkpoints only) or transcript (full)",
      "type": "string",
      "enum": [
        "chat",
        "transcript"
      ]
    }
  },
  "additionalProperties": {}
}
```

## User Request

グローバル settings.json (`C:/Users/msp/.claude/settings.json`) の env フィールドに `ENABLE_TOOL_SEARCH: "false"` を追加してください。これは Claude Code v2.1.116 以降の regression（GitHub Issue #51736）の回避策で、custom MCP server (session-recall 等) のツールが deferred tools に出ないバグを回避するため、deferred mechanism を無効化して全ツール upfront 読み込みに切り替えるためのものです。永続化することで毎回 `ENABLE_TOOL_SEARCH=false` を打たなくて済みます。

↓
(作業)
↓

🤖 Claude
**変更内容:**
- `~/.claude/settings.json` の `env` フィールドに `"ENABLE_TOOL_SEARCH": "false"` を追加
- 既存の permissions/hooks/enabledPlugins 等は全部温存
- JSON 整合性確認済み
- これで毎回環境変数を打たなくても、Claude Code 起動時に自動でセットされる

このまま **`/exit` → `claude --resume`**（普通の resume でOK）で起動して、`mcp__session-recall__*` がツールとして使えるか確認してください。

↓
(作業)
↓

🧑 あなた
もどったー。どう？

🤖 Claude
📡

おかえり！deferred tools リスト表示が消えてる = `ENABLE_TOOL_SEARCH=false` 効いてるサイン。直接 MCP ツール呼んでみる。

↓
(作業)
↓

🤖 Claude
env は効いてる（subshell の echo で `false` 確認）し、deferred mechanism は無効化されてる（ToolSearch も "no matching" を返す）。**でも MCP ツールが upfront tools にも出てきていない** = 回避策が外れた。Issue #51736 はもっと深い、MCP ツール露出パス全体が壊れてる可能性。

↓
(作業)
↓

🤖 Claude
詰みっぽい。`ENABLE_TOOL_SEARCH=false` は効いてるのに MCP ツールが upfront にも出ない、Claude Code 2.1.119 が既に最新（アップデートしても変わらない）、かつ `claude mcp list` は Connected と言い張る — これは Claude Code 側の regression が深く、当面の修正待ちパターン。

**実用面の朗報:**
- `bash _claude-sync/session-recall/search.sh "キーワード"` 直叩きは常に動く（MCP 不要）
- グローバル CLAUDE.md にも「フォールバック手段（MCP tool が使えないとき）」として書いてあるので、俺（Claude）は MCP がダメでも bash 経由で過去セッション検索できる
- セマンティック検索は server.py を直接叩く形になるけど、これも実装可能

**提案する着地点:**
1. session-recall プロジェクトとしては「Phase 6 まで完成、実用は bash 経由でカバー、MCP 自動呼び出しは Claude Code v2.1.120+ で regression 修正される可能性を待つ」で一旦区切る
2. HANDOFF.md を「2.1.120 以降が出たら ENABLE_TOOL_SEARCH=false なしで再テスト」と書いて締める
3. 1〜2 週間に 1 回くらい Claude Code を `npm update -g @anthropic-ai/claude-code` で更新して、出てたら再試験

これで一旦セッション終わりにする？それとも他の手を試したい？（user スコープ + project スコープ両方併存とか、まだ試してない組み合わせはあるけど、効く保証なし）

🧑 あなた
使えないツールがあって、検索能力は劣ってしまうってこと？

↓
(作業)
↓

🤖 Claude
## 検索能力の現状（正直整理）

| 検索方式 | MCP 経由 | bash 直叩き | 実用面 |
|---|---|---|---|
| **キーワード AND 検索**（明確な語） | ✗ 使えない | ✅ `search.sh` で動く | **全く問題なし** |
| **セマンティック検索**（曖昧クエリ） | ✗ 使えない | ✗ CLI 未実装 | **今はロスト** |

**結論:** キーワード検索は完全に温存（CLAUDE.md にもフォールバック手順が書いてあって俺が普通に呼べる）。一方、セマンティック検索（「あのボタン配置で議論した時」みたいな曖昧クエリ）は **今このままだと使えない**。理由は単純で、semantic は server.py の中にしかなくて、それが MCP プロトコル経由でしか叩けない作りだから。

**すぐ直せる:** server.py のセマンティック検索ロジックを切り出して bash CLI ラッパー（`semantic.sh` 的なやつ）を 30 行くらいで作れば、MCP regression が直るまでの代替になる。やる？

選択肢:
- **A) 今すぐ semantic CLI ラッパーを作る** → セマンティック検索能力を完全復元、Claude Code 修正待ちの間も実用フル稼働
- **B) 当面キーワード検索だけで済ませる** → 大半のケースはこれで十分、修正待ち
- **C) 後回しにして今日は終了** → /end して次セッション以降に判断

🧑 あなた
ん？どゆこと？Ａ案なら何の機能も損なわず、自動で君が、必要に応じて検索できるようにできる、てこと？

🤖 Claude
ほぼその通り。ただし正直に言うと **微妙な劣化が 1 個ある** ので明確にする。

## A 案の実態

### ✅ 機能・自動呼び出しは完全復元
- キーワード検索: bash 経由で叩ける（既に動いてる）
- セマンティック検索: bash CLI 新設で叩ける（30 行で作れる）
- 俺が判断して呼ぶフローは変わらない（CLAUDE.md の「過去参照を匂わせる発言があったら検索する」は MCP でも bash でも同じ。CLAUDE.md にセマンティック用の bash 手順を追記するだけ）
- ユーザー体験：「Claude が過去セッションを思い出して答えてくれる」は同じ

### ⚠️ ただしセマンティック検索は遅くなる
- **MCP 経由（理想）**: server.py が常駐 → embedding モデルがメモリに乗ったまま → クエリは 100〜300ms で返る
- **bash CLI 経由（A 案）**: 呼ぶたびに python プロセス起動 → embedding モデル（multilingual-e5-small）を毎回ディスクから読み込む → **初回 5〜10 秒**かかる可能性

つまり「機能的には完全」「速度は劣化」。キーワード検索（search.sh）はサイズ小さいから 1 秒以内で問題なし、セマンティック（semantic.sh）は重いモデルを毎回ロードする副作用で待ち時間が増える。

### 緩和策（A 案 + α）
- A 案だけでも実用上は十分（曖昧クエリは滅多に使わない、回数少なければ 5〜10 秒待ちは許容範囲）
- もしストレスなら、別途「semantic 用の常駐 daemon」を立てる手もあるが、それやるなら Claude Code 修正待った方が早い

**結論:** A 案で機能ロスはゼロ、自動呼び出しも維持、ただしセマンティック検索の体感速度がやや落ちる。Claude Code の regression が直ったら MCP に戻せば速度も完全復元。

これで進める？

🧑 あなた
regression 本当に治るかなぁ

🤖 Claude
正直、わからん。希望と現実を分けて評価する。

## 楽観材料
- Issue #51736 は **すべての custom MCP ユーザーに影響する critical regression** → Anthropic 側のインセンティブは強い
- MCP は Anthropic の主力機能、ここを壊し続けるのは商業的にも痛い
- v2.1.116 で混入 → 既に複数のバージョン跨いでるので、内部では認識済みで修正中の可能性

## 悲観材料
- v2.1.116 → 2.1.119 まで進んでも未修正（少なくとも 2〜3 リリース分は放置されてる）
- Windows + Git Bash + 日本語パスという特殊環境の組み合わせも踏んでる可能性、優先度低めに見られるかも
- Anthropic のリリースノートに「MCP fix」が出ない限り、毎週バージョン確認しても外れ続けるリスク

## 結論として正直に言うと
- 「2 週間以内に直る」は楽観的すぎる
- 「半年放置」もあり得る
- ということは **A 案 = 短期的回避策 だけじゃなく、長期的保険にもなる**

更に冷静に考えると、A 案で作る semantic.sh は **MCP regression が直っても不要にはならない**：
- 別 PC で MCP セットアップが面倒なときの代替
- ターミナルから直接デバッグするときに便利
- session-recall システムが MCP 依存単一障害点にならない

つまり「regression が直るかどうか」の賭けに頼らず、**A 案は単独で投資価値がある**。30 行で作れて永続的に資産化する。

regression が直ったら → MCP に戻して速度復元。直らなくても → bash 経由で機能維持。どっちに転んでも損しない。

やる方向でいい？

🧑 あなた
そだね。やろう。

↓
(作業)
↓

🧑 あなた
MACは正常版フル稼働で、Windowsのみ、その方式になるんでしょ？

🧑 あなた
[Request interrupted by user]

🤖 Claude
そう、その理解で正しい。整理する。

## 現状の前提

| PC | MCP 状態 | semantic.sh の用途 |
|---|---|---|
| **Mac** | ✅ フル稼働（HANDOFF #8 で Mac A ↔ Mac B 等価性実証済み） | 不要（保険として置くだけ） |
| **Windows** | ❌ regression 直撃 | **メイン経路**として使う |

Claude（俺）が判断して呼ぶフローも OS で分岐する形になる:
- Mac セッション → MCP `mcp__session-recall__session_recall_semantic` を呼ぶ
- Windows セッション → bash semantic.sh を呼ぶ
- これは CLAUDE.md のフォールバック節で「MCP が使えないとき」と書いておけば、俺が状況見て自動判断できる

## ただし正直に補足する不安要素 1 個

Mac での MCP 動作確認は **HANDOFF #8** の時点（4/24 頃）。その後 Claude Code は 2.1.119 まで上がってる。**今この瞬間 Mac でも同じ regression を踏んでないかは未確認**。

理論的には:
- Issue #51736 が「Windows 限定」とは書かれてない（OS 非依存の可能性あり）
- Mac でも /exit → 起動して同じ症状が出る可能性ゼロではない
- 直近 Mac セッションがいつだったか覚えてないけど、もし 2.1.116 以降に上がってからの Mac 起動経験がないなら、Mac も同じく踏んでる可能性あり

→ 結論: **semantic.sh は OS 共通で書いておくのが正解**（クロスプラットフォーム、両方で動く）。Mac 側は次回起動時に MCP 動作確認してから判断、もし Mac も regression 踏んでたら semantic.sh が両 OS で活躍する。

書き方としては Mac/Win 両対応の bash スクリプト + Python（既存 search.sh と同じスタイル）で進める方針で問題なし。実装続けていい？

🧑 あなた
つまり、無事に動けば今まで通り、ダメそうなら保険発動、ってことね？MACでも。

🤖 Claude
その通り。完璧な要約。

- MCP が deferred tools に出てる → 今まで通り MCP 呼ぶ（速い）
- 出てない（regression 踏んでる）→ 保険の bash semantic.sh 呼ぶ（やや遅いが機能フル）
- 俺が起動時に「mcp__session-recall__* が手元にあるか」を見て自動判断

これを Mac/Win 両 OS 共通のコードで実装する。実装入っていい？

🧑 あなた
うん、頼むよ

↓
(作業)
↓

🤖 Claude
完璧に動いた。出力フォーマットも server.py と一致、関連性スコアも妥当（距離 0.4 前後）。

CLAUDE.md のフォールバック節を更新して、`semantic.sh` を呼ぶ手順を追記する。

↓
(作業)
↓

🤖 Claude
完了。

## やったことまとめ

**新規ファイル（`_claude-sync/session-recall/` 配下、Drive 同期で全 PC 自動配布）:**
- `semantic.py` (4.5KB) — セマンティック検索の CLI 単体実装
- `semantic.sh` (1.8KB) — Mac/Win 両対応 bash ラッパー

**動作確認済み:**
```
$ bash semantic.sh "claude-mem を撤去した経緯" --limit 3
→ Memolette-Flutter / session-recall から距離 0.4 前後で関連段落 3 件を 17 秒で返却
```

**CLAUDE.md フォールバック節に追記:**
- semantic.sh の bash コマンドテンプレート
- 「MCP があれば MCP 経由（速い）、無ければ bash 経由（遅いが機能フル）」の自動判断ルール

**HANDOFF.md 更新:**
- Phase 7 として記録、Mac での次回起動時に Mac も regression 踏んでないか必ず確認する旨を明記

**git push 済み**（コミット `0af685a`）。Mac 側は次回 Drive 同期で `_claude-sync/session-recall/semantic.*` を受け取り、git pull で session-recall HANDOFF を最新化すれば完全等価。

これで MCP regression が直っても直らなくても、検索能力は完全維持される状態。一旦区切って `/end` する？

🧑 あなた
そだね。あと2台のWindowsで導入済ませてから、Macに戻って最終テストするよ。それもメモしておいて。一旦終わろう。

🤖 Claude
📡

了解、/end 処理する。HANDOFF に「残 Windows 2台 → Mac 最終テスト」の計画を明記してから全部並列で締める。

↓
(作業)
↓
