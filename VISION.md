# Vision

Dextero is a local-first computer agent for people who do not want to learn
agent terminology. It runs on a computer the user owns and, with permission,
acts through the applications and services available there.

The app is the main product surface. Technical details stay out of the way by
default, while advanced users can inspect, configure, and extend the system.

## Product principles

- **Local authority:** the controlled computer owns execution and remains
  useful without a cloud service.
- **Durable memory:** conversations, tasks, preferences, artifacts, and
  outcomes persist locally, remain searchable, and retain provenance.
- **Safe autonomy:** permissions are scoped; consequential actions require
  approval; work can be inspected, cancelled, and audited.
- **One identity:** the app and trusted messaging channels share conversations,
  tasks, policy, and memory.
- **Interoperability:** built-in views synchronize with services people already
  use rather than becoming isolated replacements.
- **Progressive disclosure:** simple defaults do not remove advanced control.

## AI gateway

Dextero owns the user's memory, context, permissions, and tools; models are
replaceable. It can route work to local models, cloud providers, or specialist
agents based on capability, privacy, latency, availability, cost, and user
preference.

Users should be able to see:

- which model or provider handled a task;
- why it was selected;
- what context was shared;
- what it cost.

Provider credentials and routing policy remain under user control. Selecting a
cloud model must not copy the full memory store to that provider.

### Families

Household profiles may provide separate identities, memories, permissions,
budgets, and age-appropriate controls. Parents can see clear usage and safety
summaries. Monitoring must be explicit to every family member, not covert.

## Product surfaces

The app owns conversation, tasks, approvals, artifacts, memory, settings, and
native views such as calendar. Trusted messaging services provide another way
into the same identity and task state; they are transports, not separate
agents.

Dextero should synchronize with personal systems already in use. For example,
an event created in Dextero should appear in the calendar on the user's phone,
and external changes should flow back.

## Memory

“Never forget” means continuity by default, with user-controlled correction,
retention, export, and deletion. The implementation requires:

- an append-only source record for conversations and task events;
- structured facts, preferences, relationships, and task state;
- full-text and semantic/vector search over messages and artifacts;
- retrieval that supplies relevant context without loading the full archive;
- provenance for inspection and correction;
- explicit private-data boundaries.

## Architecture

Dextero separates responsibilities into three layers:

1. **Core orchestrator:** owns memory, model routing, policy, delegation, and
   audit.
2. **Control plane:** runs a web server that exposes the core's capabilities
   over HTTP.
3. **Product surfaces:** the app and CLI/TUI today, plus trusted channels such
   as messaging services in the future.

Coding is a specialist capability. Dextero should supervise Codex, Pi, or
another coding agent rather than reproduce a weaker coding harness.

```text
┌───────────────────────────────────────────────────────┐
│ Product surfaces                                      │
│ app • CLI/TUI • trusted channels (future)             │
└──────────────────────────┬────────────────────────────┘
                           │
                           │ requests • events • streams
                           │
┌──────────────────────────▼────────────────────────────┐
│ Control plane                                         │
│ pairing • authorization • commands • streams          │
└──────────────────────────┬────────────────────────────┘
                           │
                           │ capability invocation
                           │
┌──────────────────────────▼────────────────────────────┐
│ Core orchestrator                                     │
│ memory • model routing • policy • delegation • audit  │
└────────────┬─────────────────┬─────────────────┬──────┘
             │                 │                 │
             ▼                 ▼                 ▼
           tools        specialist agents       system access
```

## Deployment

The initial host uses:

- Serverpod Mini beside the core;
- in-memory state for the current MVP;
- SQLite/Drift when durable host state is added;
- cryptographic device pairing and per-device authorization;
- LAN, private-overlay, or direct WebRTC connectivity.

An optional managed service may later provide accounts, discovery,
notifications, rendezvous, and relay fallback. It must not control local
execution. Postgres may suit that service but is not required on user machines.

## Capabilities and extensions

Every action is a capability with a resource, operation, scope, risk,
approval policy, timeout, cancellation behaviour, events, and provenance. The
same rules apply to Dart tools, MCP servers, native adapters, and specialist
agents.

- Trusted Dart packages may ship at compile time.
- Executable and MCP adapters use a small, versioned runtime protocol.
- Platform automation sits behind stable macOS, Windows, and Linux interfaces.
- Browser automation prefers DOM and CDP semantics over screenshot clicking.
- Desktop coordinates are an adapter detail, not a core abstraction.

## User experience

1. The user states an outcome.
2. Dextero works within existing authority or asks for a specific approval.
3. Structured events show progress.
4. The user can steer, cancel, inspect artifacts, or take over.
5. Tasks survive reconnects and recover predictably from failure.
6. Results state what changed, what failed, and what authority was used.
7. Useful history remains searchable.

Remote controllers use the same permissions and task state; they are not an
unrestricted command channel.

## Non-goals

- Replacing specialist agents.
- Exposing an agent harness as the product.
- An unrestricted shell behind chat.
- Requiring a cloud account for local use.
- Using screenshot automation where semantic interfaces exist.
- Implementing every platform capability in pure Dart.
- Claiming production safety before permissions, approvals, sandboxing, and
  audit are enforceable.
