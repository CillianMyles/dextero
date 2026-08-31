# Dextero

Dextero is an experimental local computer agent built with Dart, Flutter, and
Serverpod. The current MVP runs Codex tasks against a configured workspace and
streams task events to a desktop app and terminal client.

See [VISION.md](VISION.md) for product direction and [ROADMAP.md](ROADMAP.md)
for planned work.

## Repository layout

```text
packages/
├── core/    agent loop, tools, and Codex adapter
├── server/  Serverpod host, API, and generated client
├── app/     Flutter web and macOS app
└── cli/     terminal client
```

Dependency flow:

```text
app ─┐
     ├──> generated client ──> server ──> core ──> Codex
cli ─┘
```

The app and CLI use the generated client without importing or launching the
server runtime.

## Run

Requirements:

- Dart 3.10+
- Flutter with web support and Chrome
- Full Xcode installation for optional macOS native runs
- Codex CLI, authenticated with `codex login`
- OpenSSL

Start the server and web app:

```sh
make bootstrap
make dev
```

Use the native macOS app for local development or platform checks:

```sh
make dev-macos
```

When the server is already running, use `make app-web` or `make app-macos` to
start only the corresponding client. The local bearer token and control URL are
passed to Flutter as compile-time defines so the same entrypoint works on web
and macOS.

Start the CLI in a second terminal while the server is running:

```sh
make server
make cli
```

Pass a prompt directly:

```sh
make cli PROMPT="Inspect this workspace and summarize its architecture"
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

## Serverpod changes

Models live in `packages/server/lib/src/control`. Generated server, client, and
test code is committed. After changing an endpoint or `.spy.yaml` model, run:

```sh
make generate
make check
```
