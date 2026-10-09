# Dextero

Dextero is an experimental local computer agent built with Dart, Flutter, and
Serverpod. The current MVP provides one chat conversation backed by
Anthropic, Codex, or Gemini and shows the same ordered history in the Flutter
app and terminal client.

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
     ├──> generated client ──> server ──> core ──> Anthropic, Codex, or Gemini
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
- An Anthropic API key, a Gemini API key, or the Codex CLI authenticated with
  `codex login`
- OpenSSL and curl

Start the server and web app:

```sh
cp .env.example .env
make bootstrap
make dev
```

Make loads local provider settings and credentials from the ignored `.env`
file. Keep values unquoted because the file uses Make assignment syntax. Add
the keys for the API providers you want to offer:

```sh
ANTHROPIC_API_KEY=your-anthropic-key
GEMINI_API_KEY=your-gemini-key
```

Before the first message, the app and TUI offer provider/model combinations in
this order:

1. Anthropic · `claude-haiku-4-5` (initial choice when a key is configured)
2. Anthropic · `claude-sonnet-5-5`
3. Gemini · `gemini-2.5-flash` (initial choice without an Anthropic key)
4. Codex · `gpt-5.3-codex-spark` (initial choice without either key)
5. Codex · `default` (uses the authenticated Codex CLI's configured model)

Each choice shows its credential source: `Anthropic API key`, `Gemini API
key`, or `Codex CLI login`. Anthropic and Gemini are omitted when their keys
are empty. Codex choices require an
installed, authenticated Codex CLI; model access is checked when a run starts.
If Spark is unavailable to your account, choose `codex:default` before sending.
There is no automatic retry with another provider or model after a run fails.

Anthropic and Gemini use Dextero's harness tools. Codex also has its configured
Codex tools;
its existing read-only sandbox and instructions to use the harness for file
and command operations still apply.

`DEXTERO_MODEL_PROVIDER=anthropic|codex|gemini` overrides the initial provider
without hiding the others. `DEXTERO_ANTHROPIC_MODEL`, `DEXTERO_CODEX_MODEL`,
and `DEXTERO_GEMINI_MODEL` override initial models. Comma-separated
`DEXTERO_ANTHROPIC_MODELS`, `DEXTERO_CODEX_MODELS`, and `DEXTERO_GEMINI_MODELS`
override each provider's advertised models; the initial model is always
included. `ANTHROPIC_BASE_URL` points the Anthropic adapter at another
Messages API endpoint. Credentials stay on the host.

### Anthropic

The Anthropic adapter calls the Messages API directly with streaming. Text
streams into history in paragraph-sized `assistantDelta` entries. Tool calls
use Dextero's tools and approval policy. A denied approval is returned to
Claude as an error tool result. Thinking blocks are replayed unchanged within a
run.

- Each response is capped at 32,000 output tokens. Requests time out after 60
  seconds without response headers, 90 seconds without stream data, or 10
  minutes in total.
- Rate limits (429), overload (529), other 5xx responses, timeouts, and
  connection failures are retried up to three times. Retries honour
  `retry-after` and otherwise back off from 1 second. A request is not retried
  after its text has started streaming. Each retry appears as a warning.
- Requests cache the tools and system prompt with an explicit breakpoint, and
  the growing conversation with automatic caching. Prefixes below the model's
  minimum cacheable size are not cached.
- Each run ends with a `usage` history entry. It records provider, model,
  credential source, input, cache-read, cache-write, and output tokens, request
  count, and estimated cost from first-party list prices. Prices are known for
  `claude-haiku-4-5`, `claude-sonnet-5-5`, and `claude-opus-5-5`; other models
  show `cost unavailable`. Failed runs record usage for completed requests.
  Cancelled runs record none.
- Credit-balance, billing, and workspace usage-limit errors are shown as `Out of
  credit`, rejected keys as `Key rejected`, and rate limits that persist after
  retries as `Rate limited`. These entries carry a typed `errorCode`.
- Batch processing and server-side refusal fallbacks are not used. A refusal or
  output-limit stop fails the run with a specific message.

Use a key from a dedicated Anthropic Console workspace with a workspace spend
limit, so Dextero's spend is separately visible and bounded.

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

Usage entries include a `usage` object, and categorized failures include an
`error_code`.

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

API keys remain in the server process. Gemini keys are sent in the
`x-goog-api-key` header and Anthropic keys in the `x-api-key` header. Keys are
not placed in request URLs, chat history, error messages, or tool subprocess
environments. They are read from the environment, normally the ignored `.env`
file; Dextero does not yet have an encrypted secret store.

## Serverpod changes

Models live in `packages/server/lib/src/control`. The control endpoint exposes
typed `selectModel`, `submitMessage`, `history`, `streamHistory`, `approveWork`,
and `cancelRun` operations.
The status contract includes typed `modelOptions`, each with an `authSource`;
submissions require `modelProvider` as well as `modelName`. Chat entries may
carry a typed `usage` receipt and `errorCode`. Update server and clients
together for these contract changes.
Generated server, client, and test code is committed. After changing an
endpoint or `.spy.yaml` model, run:

```sh
make generate
make check
```
