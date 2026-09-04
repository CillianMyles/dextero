# Dextero

Dextero is an experimental local computer agent built with Dart, Flutter, and
Serverpod. The current MVP provides one chat conversation backed by Codex or
Gemini and shows the same ordered history in the Flutter app and terminal
client.

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
     ├──> generated client ──> server ──> core ──> Codex or Gemini
cli ─┘
```

The app and CLI use the generated client without importing or launching the
server runtime. User messages are stored before assistant work begins; replies,
tool activity, lifecycle, and errors append to the same ordered history.
The host also publishes stable local device, project, workspace, and controller
identities so later permission grants can be attributed without using display
names or filesystem paths as security keys.

## Run

Requirements:

- Dart 3.11+
- Flutter with the intended target platform enabled
- Chrome for web, Android Studio for Android, or Xcode for iOS and macOS
- GTK 3 development libraries for Linux or Visual Studio with Desktop C++ for
  Windows
- GNU Make and Bash; on Windows, run the Make targets from MSYS2 or another
  Bash environment with `bash.exe` available on `PATH`
- Codex CLI authenticated with `codex login`, or a Gemini API key
- OpenSSL and curl

Start the server and web app:

```sh
cp .env.example .env
make bootstrap
make dev
```

Make loads local provider settings and credentials from the ignored `.env`
file. Keep values unquoted because the file uses Make assignment syntax. To use
Gemini instead of Codex, set `DEXTERO_MODEL_PROVIDER=gemini` and add the key:

```sh
GEMINI_API_KEY=your-key
```

`DEXTERO_MODEL_PROVIDER=codex|gemini` overrides the automatic provider choice;
without an explicit provider, a non-empty Gemini key selects Gemini. The
initial models come from `DEXTERO_CODEX_MODEL` and `DEXTERO_GEMINI_MODEL`.
Comma-separated `DEXTERO_CODEX_MODELS` and `DEXTERO_GEMINI_MODELS` values
control the choices clients may select before the first message. The defaults
offer Codex's configured default and `gpt-5.3-codex-spark`; Gemini defaults to
`gemini-2.5-flash`. Spark requires a ChatGPT Pro-authenticated Codex CLI and is
not an API-key model.

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
make cli MODEL=gpt-5.3-codex-spark PROMPT="Run the focused tests"
```

The Flutter header provides the same model chooser. In the interactive TUI,
use `/model <name>` before the first message. Model selection is locked after
the first message so one in-memory conversation uses one model.

Pass `--jsonl` directly to the CLI for schema-v1 line-oriented event output:

```sh
dart run packages/cli/bin/dextero.dart --jsonl "Inspect this workspace"
```

The first JSONL record describes the host, project, workspace, and controller
identities. Human and full-screen terminal headers show their display names;
the Flutter identity badge shows the stable IDs in its tooltip.
Git repositories keep a local incarnation marker in their shared Git metadata,
so linked worktrees share a project identity while a replacement checkout at
the same path receives new project and workspace identities. The host registry
also records the metadata directory's filesystem incarnation, so copying a
repository does not copy its identity while moving it preserves the identity.
Non-Git workspaces use filesystem incarnation metadata in the host-owned
registry, so replacing the directory rotates both identities without writing
identity metadata into the controlled workspace.

Run all checks:

```sh
make check
```

Run `make help` for other commands.

## Security

The MVP uses a bootstrap bearer token; it does not yet provide device pairing
or OS-level sandboxing. Core can edit files and run processes inside
`DEXTERO_WORKSPACE`. File edits pause for explicit approval, but process tools
do not yet have the policy coverage planned for Milestone 3. Every `edit_file`
invocation requests a fresh approval; decisions are not currently remembered.
Controller IDs are persisted by each client and sent with every control call.
They provide stable attribution but are self-asserted, not cryptographic proof
of a device. Until pairing exists, the server must not use them alone to grant
authority.

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

Gemini credentials remain in the server process and are sent in the
`x-goog-api-key` request header. They are not placed in request URLs, chat
history, or tool subprocess environments.

## Serverpod changes

Models live in `packages/server/lib/src/control`. The control endpoint exposes
typed `selectModel`, `submitMessage`, `history`, `streamHistory`, `approveWork`,
and `cancelRun` operations. Each operation requires a typed controller identity;
host status returns the stable local device, project, and workspace identities.
Generated server, client, and test code is committed. After changing an
endpoint or `.spy.yaml` model, run:

```sh
make generate
make check
```
