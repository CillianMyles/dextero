# Dextero

**AI for the average person, running on a computer they own.**

Dextero is an opinionated, local-first app for getting things done. You ask for
an outcome and it works across the applications and services on a computer you
own. The app is the primary experience; the agent machinery stays underneath.

Dextero also acts as a user-owned gateway to AI: one durable memory and context
across local models, cloud providers, and trusted messaging channels. Read the
full product direction in [VISION.md](VISION.md).

## Repository layout

The repository is currently an early product and infrastructure stack in one
Dart monorepo:

```text
packages/
├── core/    provider-neutral harness, tools, and Codex app-server adapter
├── server/  local Serverpod host, auth, HTTP/WebSocket API, generated client
├── app/     Flutter desktop client
└── cli/     interactive terminal client
```

The dependency flow is deliberately one-way:

```text
app ─┐
     ├── generated client surface ──> server ──> core ──> Codex
cli ─┘                                  │
                                       └── local workspace tools
```

`packages/server/lib/dextero_client.dart` is the client-only Serverpod surface.
The two frontends import it without importing or launching the server runtime.

## Get started

Requirements: Dart 3.10+, Flutter with macOS desktop support, Codex CLI, and
OpenSSL. Authenticate Codex once with `codex login`, then:

```sh
make bootstrap
make dev
```

`make dev` creates a stable, git-ignored development token, starts the local
Serverpod host, waits for it to accept connections, and launches the Flutter
app. `Ctrl-C` stops both processes.

For the terminal UI, use two terminals:

```sh
# terminal 1
make server

# terminal 2
make cli
```

You can also pass a prompt without the interactive question:

```sh
make cli PROMPT="Inspect this workspace and summarize its architecture"
```

Run `make help` for all commands. The usual pre-review quality gate is:

```sh
make check
```

## How a task runs

1. The app or CLI calls the authenticated Serverpod `runTask` method stream.
2. The server invokes `CodexTaskRunner` against `DEXTERO_WORKSPACE`.
3. Core launches `codex app-server` and supplies workspace-scoped Dart tools.
4. Queued, running, output, completed, and failed events stream back to the
   initiating client over Serverpod's WebSocket transport.

Server state and the bootstrap token model are intentionally MVP-grade. The
token authenticates controllers, but it does not replace device pairing or an
OS sandbox. Core currently exposes file editing and process execution inside
the configured workspace, so run the host only where that authority is
appropriate. Serverpod 3.4.13 may bind its API listener beyond loopback; keep
port 8080 firewalled from untrusted networks.

## Protocol changes

Serverpod models live in `packages/server/lib/src/control`. Generated server,
client, and test code is checked in. After changing an endpoint or `.spy.yaml`
model, run:

```sh
make generate
make check
```

The product philosophy and delivery milestones are documented in
[VISION.md](VISION.md) and [ROADMAP.md](ROADMAP.md).
