# Vision

## AI for the average person

Dextero is a general-purpose, opinionated computer agent expressed as an
intuitive and fun consumer app. It runs on a computer the user owns and, with
their permission, should eventually be able to do anything they can do on that
computer: use applications, move information, communicate, create, organize,
research, and coordinate work across connected services.

The app is the product. The harness, models, tools, specialists, and control
plane should recede into the background. A person should not need to understand
agent loops, MCP, context windows, or orchestration to get something useful
done.

This does not mean sanding away the power that attracts technical early
adopters. Dextero should use progressive disclosure: a calm default experience
for anyone, with deeper visibility, control, configuration, and extension when
someone wants it. Usability across every level of technical proficiency is a
product constraint, not a later accessibility pass.

The differentiator is not a bigger bag of tools. It is the control system
around them:

- durable task and session state;
- explicit permissions and risk-aware approvals;
- observable progress and structured results;
- scoped delegation to specialist agents;
- recoverability, cancellation, and auditability;
- useful defaults that keep authority local.

Opinionated means Dextero makes coherent product choices on the user's behalf:
one primary app, one continuous identity, durable memory, safe autonomy, and
interoperability with the tools already present in their life. It does not mean
forcing every user into one rigid workflow.

## Product thesis

Most agent harnesses are shaped around a model or a domain. Coding agents are
excellent at repositories; browser agents are optimized for web pages; desktop
automation tools drive pixels and windows. A useful computer agent should not
poorly reproduce all of them. It should understand the task, choose the right
specialist, constrain its authority, supervise its work, and combine the
result into one coherent user experience.

Behind the product, Dextero has three roles:

1. **Local control plane** — owns permissions, approvals, session state,
   capability discovery, and the audit record.
2. **Orchestrator** — decomposes work, invokes tools or specialists, streams
   progress, handles failure, and incorporates results.
3. **Product surface** — provides the primary app and lets trusted secondary
   channels inspect work, approve actions, steer tasks, and continue the same
   relationship.

Coding is the first specialist delegation because mature coding harnesses
already exist. Dextero should invoke and supervise Codex, Pi, or another coding
agent when deep repository work is needed, while retaining lightweight local
file and process tools for small or cross-domain tasks.

## One product, many doors

The Dextero app should be where most people meet and use the product. It owns
the complete experience: conversation, tasks, approvals, artifacts, memory,
settings, and useful native views such as a calendar.

The app is not the only entrance. A user should also be able to text Dextero
from a trusted messaging service, close the desktop app, reconnect from another
device, and continue the same task and relationship. Channels are transports,
not separate agents: they share identity, policy, conversation state, memory,
and task history.

Dextero should coexist with the products a person already relies on. If it
creates an event in its own calendar experience, that event should also appear
in the calendar they use on their phone. The same principle applies to tasks,
contacts, files, messages, and other personal systems: provide a coherent
Dextero surface while synchronizing through supported APIs and adapters rather
than building an isolated replacement for everything.

## Memory as a product promise

Dextero should not casually forget. Messages, decisions, preferences, tasks,
artifacts, outcomes, and the provenance connecting them should persist locally
and remain searchable across time.

That requires more than dumping chat transcripts into prompts:

- an append-only source record for conversations and task events;
- structured facts, preferences, relationships, and task state;
- full-text and semantic/vector search over messages and artifacts;
- deliberate retrieval that supplies relevant context without flooding the
  model;
- provenance so remembered information can be inspected and corrected;
- user-controlled export, retention, deletion, and private-data boundaries.

“Never forget” is the default continuity promise, not a claim that data can
never be corrected or erased. The user remains the authority over what Dextero
keeps, and durable memory must not become silent surveillance or mandatory
cloud storage.

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
│ Dextero product surfaces                                    │
│ conversation • tasks • memory • calendar • approvals        │
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

1. The user states an outcome in the app or a trusted messaging channel.
2. Dextero proposes or begins a safe plan within already granted authority.
3. Progress appears as structured events, not a wall of hidden reasoning.
4. Consequential actions pause with a specific, understandable approval.
5. The user can steer, cancel, inspect artifacts, or take over.
6. The task can survive reconnects and recover from process failure.
7. The final result includes what changed, what failed, and what authority was
   exercised.
8. The conversation, result, and useful lessons remain searchable later, and
   changes to connected systems are reflected in the products the user already
   uses.

Remote control should strengthen this model, not bypass it. A phone controller
is a secure window into the same approvals and task state—not a second,
unrestricted command channel.

## What Dextero is not

- It is not a replacement for Codex, Pi, or every other specialist agent.
- It is not an agent harness presented as a consumer product.
- It is not an unrestricted shell with a chat interface.
- It is not dependent on a cloud account to control the local computer.
- It is not committed to screenshot-based automation when semantic interfaces
  exist.
- It is not promising one pure-Dart implementation for every operating-system
  capability.
- It is not production-safe until permissions, approvals, sandboxing, and
  auditability exist as enforceable boundaries.

## The destination

Dextero succeeds when an ordinary person can ask it to get something done
without learning agent terminology; when an expert can still inspect, extend,
and control the machinery; when either can move between the app and messaging
without losing continuity; and when Dextero remembers their shared history and
works with the services already on their phone—all while the controlled
computer and its authority remain theirs.
