# Dextero

**A local-first, opinionated computer agent built in Dart.**

Dextero is an early-stage harness for agents that can work across a computer
while remaining visible, controllable, and auditable. It is intended to become
a general-purpose computer agent—not a coding agent with a few extra tools.

Coding is an important capability, but not the product boundary. Dextero can
use focused primitives directly and will delegate deeper repository work to
specialist agents such as Codex or Pi. The same orchestration model can later
support browser automation, research, communication, media, and native desktop
adapters.

> The intelligence can come from different models and specialists. Dextero's
> job is to coordinate them safely on the user's computer.

## Status

Dextero is a working agent-kernel spike, not yet a complete computer agent.

Implemented today:

- typed tool definitions, calls, and results;
- a provider-neutral, bounded model → tool → model loop;
- workspace-confined file reading, listing, and exact single-match editing;
- direct argv-based process execution;
- an explicit, timeout-bounded shell tool with output caps;
- a Codex app-server adapter that leaves subscription authentication and token
  refresh with the Codex CLI;
- deterministic demos and focused tests for tool and protocol failure modes;
- a database-free Serverpod Mini control plane with bearer-token auth, a typed
  status RPC, and a streamed demo-task lifecycle;
- AOT compilation to a small, fast-starting native executable.

The path from this kernel to the product is documented in [VISION.md](VISION.md)
and [ROADMAP.md](ROADMAP.md).

## Why Dart?

Dart is a strong fit for the product as a whole:

- a typed, fast-starting native host and CLI;
- shared contracts between the harness, control plane, and clients;
- Serverpod-generated endpoints, models, and streams;
- Flutter controllers for mobile, desktop, and web;
- straightforward process, HTTP, WebSocket, FFI, and MCP adapters.

Dart does not need to be the best ecosystem for every capability. Dextero uses
a hybrid adapter model: Dart owns orchestration, policy, state, and product
surfaces while specialist tools, MCP servers, subprocesses, and native adapters
provide capabilities where another ecosystem is stronger.

## Architecture direction

```text
Flutter controllers
mobile • desktop • web
          │ generated typed client
          ▼
Local Serverpod control plane
pairing • commands • approvals • task streams
          │ shared Dart models and events
          ▼
Dextero harness
policy • sessions • tools • delegation • audit
     │             │              │
     ▼             ▼              ▼
Pure Dart tools  MCP/process   Specialist agents
files • HTTP     adapters      Codex • Pi • others
```

The controlled computer remains the authority. The local host is expected to
use Serverpod Mini without requiring Postgres; lightweight persistence can be
added with SQLite/Drift. Latency-sensitive screen, audio, and input traffic
belongs on WebRTC rather than the Serverpod control stream.

## Try the current kernel

Requirements:

- Dart SDK 3.10 or newer;
- Codex CLI only for the optional subscription-authenticated demo.

Install dependencies and run the test suite:

```sh
dart pub get
dart test
dart analyze
```

### Run the local control plane

The Serverpod Mini service requires no Postgres or Redis process. It keeps MVP
state in memory and requires a bootstrap bearer token for every Dextero
endpoint:

```sh
export DEXTERO_CONTROL_TOKEN="$(openssl rand -hex 32)"
dart run packages/dextero_server/bin/main.dart
```

Serverpod listens on port `8080` by default. Serverpod 3.4.13 binds its API
listener to all IPv6 interfaces even though its default public host is
`localhost`; do not treat the hostname as a network boundary. Keep the port
firewalled from untrusted networks. The token is an MVP bootstrap mechanism,
not a replacement for the planned cryptographic device-pairing flow.

The generated Dart client lives in `packages/dextero_client`. After changing a
`.spy.yaml` model or endpoint, regenerate both sides with:

```sh
serverpod generate --directory packages/dextero_server
```

With the server running, exercise the generated client and method stream from
another terminal using the same token:

```sh
dart run packages/dextero_client/bin/control_demo.dart
```

Run the deterministic agent demo:

```sh
dart run bin/agent_demo.dart
```

Run the original structured process harness:

```sh
dart run bin/harness.dart --run 'printf dextero-ok'
```

Expected output on macOS:

```json
{"platform":"macos","exitCode":0,"stdout":"dextero-ok","stderr":""}
```

Build a native executable for the current machine:

```sh
mkdir -p build
dart compile exe bin/harness.dart -o build/dextero
./build/dextero --run 'printf dextero-ok'
```

### Codex app-server demo

OpenAI subscription authentication stays behind the supported Codex boundary.
Dextero launches `codex app-server` over JSONL stdio and never reads Codex's
cached credentials directly.

```sh
codex login
codex login status
dart run bin/codex_oauth_demo.dart
```

The dynamic-tool protocol used by this adapter is experimental, so it remains
isolated from the provider-neutral kernel.

## Safety model

Current path confinement, exact-match editing, timeouts, and output caps are
guardrails—not an OS security boundary. Dextero does not yet have its planned
permission engine, approval policy, sandbox adapters, secret filtering, or
durable audit log. Run the spike only in environments where you understand and
accept the authority granted to its tools.

## Project principles

- **Local authority:** the controlled computer owns execution and policy.
- **Typed boundaries:** tools, events, approvals, and delegation use explicit
  contracts.
- **Least privilege:** capabilities are scoped; consequential actions require
  clear approval.
- **Specialists over imitation:** delegate deep domain work instead of
  rebuilding every expert harness.
- **Adapters over purity:** use MCP, processes, WebRTC, and native APIs when
  they are the right boundary.
- **Observable by default:** work should expose progress, decisions, results,
  and failures.

## Contributing

Dextero is still defining its foundations. Issues and focused experiments that
advance the milestones in [ROADMAP.md](ROADMAP.md) are welcome; large capability
expansions should start with a design discussion so the permission and event
contracts remain coherent.
