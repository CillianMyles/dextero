# Vision

## A computer agent the user remains in control of

Dextero is a general-purpose, opinionated computer agent. It should be able to
take a goal, coordinate the right capabilities, and carry work across local
applications and connected services without turning the user's computer into
an opaque remote shell.

The differentiator is not a bigger bag of tools. It is the control system
around them:

- durable task and session state;
- explicit permissions and risk-aware approvals;
- observable progress and structured results;
- scoped delegation to specialist agents;
- recoverability, cancellation, and auditability;
- useful defaults that keep authority local.

## Product thesis

Most agent harnesses are shaped around a model or a domain. Coding agents are
excellent at repositories; browser agents are optimized for web pages; desktop
automation tools drive pixels and windows. A useful computer agent should not
poorly reproduce all of them. It should understand the task, choose the right
specialist, constrain its authority, supervise its work, and combine the
result into one coherent user experience.

Dextero therefore has three roles:

1. **Local control plane** — owns permissions, approvals, session state,
   capability discovery, and the audit record.
2. **Orchestrator** — decomposes work, invokes tools or specialists, streams
   progress, handles failure, and incorporates results.
3. **Remote product surface** — lets a user securely pair a controller, inspect
   work, approve actions, steer tasks, and take over when needed.

Coding is the first specialist delegation because mature coding harnesses
already exist. Dextero should invoke and supervise Codex, Pi, or another coding
agent when deep repository work is needed, while retaining lightweight local
file and process tools for small or cross-domain tasks.

## Why Dart, Flutter, and Serverpod

The language decision is about the whole product, not just the agent loop.

Dart provides a typed orchestration core, native CLI distribution, strong
process and networking primitives, and a clean bridge to FFI or out-of-process
adapters. Flutter turns the same ecosystem into polished controller apps for
phones, tablets, desktops, and the web. Serverpod provides generated Dart
models and clients, endpoint contracts, and streaming methods between those
surfaces.

Together they make contract changes visible at compile time across the host
and controller instead of leaving the system connected by informal JSON.

The architecture remains deliberately hybrid:

```text
┌─────────────────────────────────────────────────────────────┐
│ Flutter controllers                                         │
│ task view • approvals • logs • files • remote control       │
└───────────────────────────┬─────────────────────────────────┘
                            │ generated typed client
┌───────────────────────────▼─────────────────────────────────┐
│ Local Serverpod control plane                               │
│ pairing • authorization • commands • streams • signalling   │
└───────────────────────────┬─────────────────────────────────┘
                            │ shared models and event contracts
┌───────────────────────────▼─────────────────────────────────┐
│ Dextero orchestration core                                  │
│ sessions • policy • approvals • delegation • audit          │
└─────────────┬──────────────────┬──────────────────┬─────────┘
              │                  │                  │
      Pure Dart tools       MCP/process        Native adapters
      files • HTTP          specialists        AX • UIA • AT-SPI
              │                  │                  │
              └──────────────────┴──────────────────┘
                    applications and services

WebRTC: direct low-latency screen • audio • pointer • keyboard
```

Serverpod is the control plane, not the media plane. Ordinary commands,
approvals, logs, presence, and task events fit typed endpoint calls and
WebSocket streams. Screen video, audio, and high-frequency input require a
purpose-built low-latency transport such as WebRTC; Serverpod can authenticate
the peers and carry signalling.

## Local-first deployment

The controlled computer is the execution authority and should remain useful
without a mandatory cloud service.

The default host shape is:

- Serverpod Mini beside the harness;
- no required Postgres installation;
- in-memory state for the earliest vertical slice;
- SQLite/Drift when durable host state is introduced;
- custom cryptographic device pairing and per-device authorization;
- direct LAN, private-overlay, or WebRTC connectivity.

An optional managed service may later provide accounts, device discovery,
notifications, rendezvous, and relay fallback. It must not silently become the
authority over local execution. A full Serverpod/Postgres deployment is a
reasonable fit for that service, but an unreasonable prerequisite for every
consumer computer.

## Capability model

Dextero treats every action as a capability, not as ambient authority.

A capability should declare:

- what resource and operation it covers;
- the scope granted to the current task or specialist;
- its risk and approval requirements;
- cancellation and timeout behaviour;
- the events and artifacts it produces;
- enough identity and provenance for an audit record.

This model should apply equally to a Dart tool, an MCP server, a native desktop
adapter, and a delegated coding agent. A specialist receives only the task,
context, and capabilities it needs. The parent can monitor, steer, cancel, and
incorporate the structured result.

## Extension strategy

Dextero is not an all-Dart purity project.

- **Compile-time extensions** are trusted Dart packages shipped with a release.
- **Runtime extensions** are executable or MCP adapters isolated behind a
  small, versioned protocol.
- **Native platform work** sits behind stable interfaces for macOS
  accessibility, Windows UI Automation, and Linux accessibility APIs.
- **Browser work** prefers DOM and Chrome DevTools Protocol semantics over
  screenshot clicking.
- **Desktop coordinates** are a last-mile adapter detail, never the core
  abstraction.

This gives Dextero access to mature Python, TypeScript, Rust, and native
ecosystems without weakening the typed policy boundary.

## Trust and user experience

The ideal interaction is calm and legible:

1. The user states an outcome.
2. Dextero proposes or begins a safe plan within already granted authority.
3. Progress appears as structured events, not a wall of hidden reasoning.
4. Consequential actions pause with a specific, understandable approval.
5. The user can steer, cancel, inspect artifacts, or take over.
6. The task can survive reconnects and recover from process failure.
7. The final result includes what changed, what failed, and what authority was
   exercised.

Remote control should strengthen this model, not bypass it. A phone controller
is a secure window into the same approvals and task state—not a second,
unrestricted command channel.

## What Dextero is not

- It is not a replacement for Codex, Pi, or every other specialist agent.
- It is not an unrestricted shell with a chat interface.
- It is not dependent on a cloud account to control the local computer.
- It is not committed to screenshot-based automation when semantic interfaces
  exist.
- It is not promising one pure-Dart implementation for every operating-system
  capability.
- It is not production-safe until permissions, approvals, sandboxing, and
  auditability exist as enforceable boundaries.

## The destination

Dextero succeeds when a user can start a task from any trusted controller,
watch it coordinate local tools and specialist agents, approve only the actions
that matter, disconnect without losing the work, and return to a complete,
auditable result—while the controlled computer remains theirs.
