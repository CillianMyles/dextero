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
├── app/     Flutter web and macOS app
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
safe tool activity, lifecycle, and errors append to the same ordered history.

## Run

Requirements:

- Dart 3.10+
- Flutter with web support and Chrome
- Full Xcode installation for optional macOS native runs
- Codex CLI authenticated with `codex login`, or a Gemini API key
- OpenSSL

Start the server and web app:

```sh
make bootstrap
make dev
```

To use Gemini instead of Codex, provide the key when starting the host. A
non-empty key selects Gemini automatically:

```sh
GEMINI_API_KEY="your-key" make dev
```

The default model is `gemini-3.7-flash`. Set `DEXTERO_GEMINI_MODEL` to use a
different Gemini model. `DEXTERO_MODEL_PROVIDER=codex|gemini` overrides the
automatic provider choice; explicitly choosing Gemini requires
`GEMINI_API_KEY`. The Flutter app and CLI show the active provider and model
reported by the server.

Use the native macOS app for local development or platform checks:

```sh
make dev-macos
```

When the server is already running, use `make app-web` or `make app-macos` to
start only the corresponding client. The local bearer token and control URL are
passed to Flutter as compile-time defines so the same entrypoint works on web
and macOS.

Start an interactive terminal chat in a second terminal while the server is
running. Use `/exit` to leave:

```sh
make server
make cli
```

Cancel a known run from another terminal with
`dart run packages/cli/bin/dextero.dart --cancel <run-id>`.

Send one message non-interactively:

```sh
make cli PROMPT="Inspect this workspace and summarize its architecture"
```

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
`DEXTERO_WORKSPACE`. Serverpod 3.4.13 may bind beyond loopback, so keep port
8080 firewalled from untrusted networks.

Chat history stores bounded, redacted tool summaries instead of raw arguments
or results. The current in-memory implementation loses its single conversation
when the server restarts; no Postgres service is required.

Gemini credentials remain in the server process and are sent in the
`x-goog-api-key` request header. They are not placed in request URLs, chat
history, or tool subprocess environments.

## Serverpod changes

Models live in `packages/server/lib/src/control`. The control endpoint exposes
typed `submitMessage`, `history`, and `streamHistory` operations. Generated
server, client, and test code is committed. After changing an endpoint or
`.spy.yaml` model, run:

```sh
make generate
make check
```
