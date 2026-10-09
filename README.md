# Dextero

Dextero is an experimental local computer agent built with Dart, Flutter, and
Serverpod. The current MVP provides one chat conversation backed by Codex,
Gemini, or Claude Code and shows the same ordered history in the Flutter app
and terminal client.

See [VISION.md](VISION.md) for product direction and [ROADMAP.md](ROADMAP.md)
for planned work.

## Repository layout

```text
packages/
├── core/    agent loop, tools, and model adapters
├── server/  Serverpod host, API, and generated client
├── app/     Flutter app for Android, iOS, Linux, macOS, web, and Windows
└── cli/     terminal client
```

Dependency flow:

```text
app ─┐
     ├──> generated client ──> server ──> core ──> Codex, Gemini, or Claude Code
cli ─┘
```

The app and CLI use the generated client without importing or launching the
server runtime. User messages are stored before assistant work begins; replies,
tool activity, lifecycle, and errors append to the same ordered history.

## Run

Requirements:

- Dart 3.10+
- Flutter with the intended target platform enabled
- Chrome for web, Android Studio for Android, or Xcode for iOS and macOS
- GTK 3 development libraries for Linux or Visual Studio with Desktop C++ for
  Windows
- GNU Make and Bash; on Windows, run the Make targets from MSYS2 or another
  Bash environment with `bash.exe` available on `PATH`
- Codex CLI authenticated with `codex login`, or a Gemini API key
- Optional: Claude Code CLI authenticated with `claude auth login`
- OpenSSL and curl

Start the server and web app:

```sh
cp .env.example .env
make bootstrap
make dev
```

Make loads local provider settings and credentials from the ignored `.env`
file. Keep values unquoted because the file uses Make assignment syntax. To use
Gemini as the initial provider, add the key:

```sh
GEMINI_API_KEY=your-key
```

Before the first message, the app and TUI offer provider/model combinations in
this order:

1. Gemini · `gemini-2.5-flash` (initial choice when a key is configured)
2. Codex · `gpt-5.3-codex-spark` (initial choice without a Gemini key)
3. Codex · `default` (uses the authenticated Codex CLI's configured model)
4. Claude · `opus`
5. Claude · `sonnet`

Each choice shows its auth source: `Gemini API key`, `local Codex CLI login`,
or `local Claude Code subscription`.

Gemini is omitted when `GEMINI_API_KEY` is empty. Claude is omitted unless
`claude auth status` reports a login when the server starts; a stale login is
reported when a run starts. Codex choices require an
installed, authenticated Codex CLI; model access is checked when a run starts.
If Spark is unavailable to your account, choose `codex:default` before sending.
There is no automatic retry with another provider or model after a run fails.

Gemini uses Dextero's harness tools. Codex also has its configured Codex tools;
its existing read-only sandbox and instructions to use the harness for file
and command operations still apply.

Claude runs the installed `claude` CLI in print mode with its built-in tools
disabled and user settings, plugins, and MCP servers skipped. Dextero's harness
tools are offered over the CLI's stream-json control protocol, and Dextero
answers every permission prompt: tools outside the harness are denied, and
`edit_file` still waits for Dextero approval. Later messages in the same
conversation resume the Claude Code session, which Claude Code stores under
`~/.claude/projects`; Codex and Gemini do not yet carry earlier turns.

`DEXTERO_MODEL_PROVIDER=codex|gemini|claude` overrides the initial provider
without hiding the others. `DEXTERO_CODEX_MODEL`, `DEXTERO_GEMINI_MODEL`, and
`DEXTERO_CLAUDE_MODEL` override initial models. Comma-separated
`DEXTERO_CODEX_MODELS`, `DEXTERO_GEMINI_MODELS`, and `DEXTERO_CLAUDE_MODELS`
override each provider's advertised models; the initial model is always
included. Credentials stay on the host.

Use the native client for the current desktop platform:

```sh
make dev-macos
# make dev-linux
# make dev-windows
```

For Android or iOS, choose a target reported by `flutter devices`. Android
debug runs default to the standard emulator host address,
`http://10.0.2.2:8080/`. A physical device needs an authenticated HTTPS proxy
or protected tunnel that reaches this computer:

```sh
make dev-android DEVICE=<device-id> CONTROL_URL=https://<protected-host>/
# make dev-ios DEVICE=<device-id> CONTROL_URL=https://<protected-host>/
```

When the server is already running, replace `dev-` with `app-` in any platform
command to start only the client. The bearer token and control URL are passed
to Flutter as compile-time defines so every platform uses the same entrypoint.
Desktop targets must be run on their matching host operating system.

Start the Nocterm-based interactive TUI in a second terminal while the server
is running. It provides a scrollable activity timeline, Markdown assistant
output, and a focused message editor. Use `/exit` or Ctrl+C to leave:

```sh
make server
make cli
```

Cancel a known run from another terminal with `make cancel RUN_ID=<run-id>`.
Approve a pending file edit with the run and approval IDs shown in history:

```sh
make approve RUN_ID=<run-id> APPROVAL_ID=<approval-id>
```

These targets reuse the development token and `CONTROL_URL`; pass the same
connection overrides used to start the client when they are not in `.env`.

Send one message non-interactively:

```sh
make cli PROMPT="Inspect this workspace and summarize its architecture"
```

One-shot prompts, cancellation, and JSONL remain non-interactive so they can be
used safely from scripts.

Select an advertised model when starting the CLI conversation:

```sh
make cli MODEL=codex:gpt-5.3-codex-spark PROMPT="Run the focused tests"
```

The Flutter header provides the same provider/model chooser with tool descriptions.
In the interactive TUI, use `/models` to list choices and
`/model codex:default` or `/model gemini:gemini-2.5-flash` to select one.
`--model <provider>:<model>` accepts the same choices for one-shot CLI runs;
a bare model name also works when it identifies exactly one advertised choice.
Selection is locked after the first message so one in-memory conversation uses
one provider/model combination. Restart the server to start a fresh conversation.
Clients submit both provider and model, and stale selections are rejected before
any message is stored.

Pass `--jsonl` directly to the CLI for schema-v1 line-oriented event output:

```sh
dart run packages/cli/bin/dextero.dart --jsonl "Inspect this workspace"
```

Run all checks:

```sh
make check
```

Run `make help` for other commands.

## Security

The MVP uses a bootstrap bearer token; it does not yet provide device pairing
or OS-level sandboxing. Core can edit files and run processes inside
`DEXTERO_WORKSPACE`. File edits pause for explicit approval, but process tools
do not yet have the policy coverage planned in the
[permissions roadmap](ROADMAP.md#later--permissions-approvals-and-audit).
Every `edit_file` invocation requests a fresh approval; decisions are not
currently remembered.

The host binds to `127.0.0.1` by default. Set `BIND_ADDRESS` to a numeric IP
only when a protected local-network controller or tunnel needs direct access:

```sh
make server BIND_ADDRESS=192.168.1.20
```

`make dev` points its client at that bind address unless `CONTROL_URL` is set
explicitly.

The bearer token does not encrypt traffic. Keep non-loopback port 8080
firewalled from untrusted networks and use an authenticated HTTPS proxy or
protected tunnel for physical devices.

Chat history includes command and tool activity with capped per-event
stdout/stderr excerpts. Treat it as sensitive diagnostic data, not a security
or retention boundary. The total activity-event count is not currently
bounded. The current in-memory implementation loses its single conversation
when the server restarts; no Postgres service is required.

The Claude Code subprocess receives the same filtered environment as tools,
plus `CLAUDE_CONFIG_DIR` when set. `ANTHROPIC_API_KEY` is not passed, so a
Claude choice always uses the CLI's own login rather than API billing.

Gemini credentials remain in the server process and are sent in the
`x-goog-api-key` request header. They are not placed in request URLs, chat
history, or tool subprocess environments.

## Serverpod changes

Models live in `packages/server/lib/src/control`. The control endpoint exposes
typed `selectModel`, `submitMessage`, `history`, `streamHistory`, `approveWork`,
and `cancelRun` operations.
The status contract includes typed `modelOptions`; submissions require `modelProvider`
as well as `modelName`. Update server and clients together for this contract change.
Generated server, client, and test code is committed. After changing an
endpoint or `.spy.yaml` model, run:

```sh
make generate
make check
```
