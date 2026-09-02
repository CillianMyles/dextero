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
safe tool activity, lifecycle, and errors append to the same ordered history.

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
- OpenSSL and curl

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

Chat history stores bounded, redacted tool summaries. Command events include
the command and a capped stdout/stderr excerpt; tool failures include their
display-safe error text. The current in-memory implementation loses its single
conversation when the server restarts; no Postgres service is required.

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
