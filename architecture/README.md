# Velox Architecture

This directory contains the architectural model for **Velox**, a federated, end-to-end-encrypted chat platform. The C4 files (`*.c4`) describe the visual model — actors, containers, services, data stores, and the relationships between them. This README is the architectural guide that explains the **why** behind those diagrams.

The C4 diagrams are intentionally minimal: they are a visual reference, not the source of truth for design decisions. All long-form explanation lives in this document.

> **Status:** Initial architecture draft. MIMI conformance work is tracked separately and is explicitly marked **(WIP)** wherever it appears.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Diagrams & Viewing the Model](#2-diagrams--viewing-the-model)
3. [Core Design Decisions](#3-core-design-decisions)
   1. [End-to-end encryption with MLS](#31-end-to-end-encryption-with-mls)
   2. [Key encryption key (KEK) and login](#32-key-encryption-key-kek-and-login)
   3. [The epoch lease — a Velox-specific MLS optimisation](#33-the-epoch-lease--a-velox-specific-mls-optimisation)
   4. [Federation: hub-and-follower replication](#34-federation-hub-and-follower-replication)
   5. [Federation trust: mTLS + ed25519](#35-federation-trust-mtls--ed25519)
   6. [Why Federation Edge and Interconnect are split](#36-why-federation-edge-and-interconnect-are-split)
   7. [Consent before first contact](#37-consent-before-first-contact)
   8. [Stateless services, dedicated data stores](#38-stateless-services-dedicated-data-stores)
   9. [Admin plane separation](#39-admin-plane-separation)
   10. [Plugins (WASM via wazero)](#310-plugins-wasm-via-wazero)
4. [MIMI Alignment (WIP)](#4-mimi-alignment-wip)
5. [Services](#5-services)
   1. [Frontends — Web, Desktop, Mobile](#51-frontends--web-desktop-mobile)
   2. [API](#52-api)
   3. [Delivery](#53-delivery)
   4. [Store](#54-store)
   5. [Identity](#55-identity)
   6. [Federation Edge](#56-federation-edge)
   7. [Interconnect](#57-interconnect)
   8. [Push Gateway](#58-push-gateway)
   9. [Admin UI & Admin API](#59-admin-ui--admin-api)
6. [Data Plane](#6-data-plane)
   1. [Postgres instances](#61-postgres-instances)
   2. [Valkey instances](#62-valkey-instances)
   3. [Scylla](#63-scylla)
   4. [Kafka topics](#64-kafka-topics)
7. [Federation Edge Routing Table](#7-federation-edge-routing-table)
8. [Flows](#8-flows)
   1. [Login & key unlock](#81-login--key-unlock)
   2. [Send message — local chat](#82-send-message--local-chat)
   3. [Send message — federated chat](#83-send-message--federated-chat)
   4. [Add member — federated, post-consent](#84-add-member--federated-post-consent)
   5. [Federated consent (MIMI, WIP)](#85-federated-consent-mimi-wip)
   6. [Plugin install](#86-plugin-install)
9. [Diagram Legend](#9-diagram-legend)
   1. [Element colours](#91-element-colours)
   2. [Relationship line styles](#92-relationship-line-styles)
10. [Glossary](#10-glossary)
11. [Notes on Consistency & Open Items](#11-notes-on-consistency--open-items)

---

## 1. Overview

Velox is a federated, end-to-end-encrypted chat system. Its three defining properties:

- **True E2EE via MLS (RFC 9420).** Every chat is an MLS group. All encryption, decryption, and commit construction happens client-side; the server never sees plaintext or private key material.
- **Federation.** Chats can span multiple independently operated Velox instances. Replication follows the MIMI hub/follower model: each chat has one designated hub instance that orders MLS commits.
- **Stateless services + dedicated data stores.** Backend services are horizontally scalable and own their own Postgres / Valkey instances. Scylla and Kafka are intentionally shared (single canonical message store, single event bus).

The user-facing protocol is **WebTransport (QUIC)** for realtime traffic and **HTTPS** for management. Cross-instance traffic is **mTLS + ed25519-signed payloads**.

---

## 2. Diagrams & Viewing the Model

The model is authored in [LikeC4](https://likec4.dev/). Layout is determined by LikeC4 from the `.c4` source.

To view interactively:

```bash
cd architecture
pnpm install
pnpm preview        # open http://localhost:5173
```

Each view is one `.c4` file in `views/`. The full file list:

| File | View | Purpose |
|---|---|---|
| `views/landscape.c4` | Landscape | C4 Level 1 — actors, external systems, Velox as one box. |
| `views/containers.c4` | Containers | C4 Level 2 — every container inside Velox. |
| `views/legend.c4` | Legend | Colour and line-style reference. |
| `views/external.c4` | External / Integrations | Outbound connections to third-party services. |
| `views/admin-plane.c4` | Admin Plane | Operator console + plugin registry deployment. |
| `views/frontend.c4` | Frontend Surface | How clients reach user-facing services. |
| `views/service-api.c4` | API service | API + direct neighbours. |
| `views/service-delivery.c4` | Delivery service | Delivery + direct neighbours. |
| `views/service-store.c4` | Store service | Store + direct neighbours. |
| `views/service-identity.c4` | Identity service | Identity + direct neighbours. |
| `views/service-federation-edge.c4` | Federation Edge | Inbound federation gateway. |
| `views/service-interconnect.c4` | Interconnect service | Outbound federation + hub coordination. |
| `views/service-push.c4` | Push Gateway | Push notification dispatch. |
| `views/flow-login.c4` | Flow: Login | Sequence — login + KEK unlock. |
| `views/flow-send-message.c4` | Flow: Send (local) | Sequence — local chat send. |
| `views/flow-federated-message.c4` | Flow: Send (federated) | Sequence — federated chat send. |
| `views/flow-federated-member-add.c4` | Flow: Add member (federated) | Sequence — adding a remote user. |
| `views/flow-federated-consent.c4` | Flow: Federated consent (WIP) | Sequence — MIMI consent round-trip. |
| `views/flow-plugin-install.c4` | Flow: Plugin install | Sequence — admin uploads + hot-reload. |

### Embedding diagrams in this README

GitHub-flavoured Markdown does **not** render `.c4` files. There is no `likec4` code-block renderer in the same way Mermaid has one. Two practical options:

1. **Export and commit images.** Run `pnpm exec likec4 export png -o images/` (or `svg`) and reference the generated files: `![Containers](images/containers.png)`. Re-run after model changes; CI can automate it.
2. **Use the [LikeC4 GitHub Action](https://github.com/likec4/actions)** to publish the interactive model and link to it from the README.

This README does not embed images today — that's deliberate, to avoid stale screenshots drifting from the model. Use `pnpm preview` for the live diagrams.

---

## 3. Core Design Decisions

### 3.1 End-to-end encryption with MLS

Velox uses **MLS (RFC 9420)** for all chats. Consequences:

- All encryption and decryption happens **client-side**. The server only ever sees ciphertext.
- MLS state — commits and ratchet tree snapshots — lives in **Scylla**. It is opaque to the server.
- Client commit construction is **client-side**; the server never holds private key material.

### 3.2 Key encryption key (KEK) and login

The user's passphrase derives a **Key Encryption Key (KEK)** client-side via a memory-hard KDF (e.g. Argon2). The KEK never leaves the client. Identity stores the **passphrase-wrapped encryption key** server-side and returns it after a successful KEK challenge. The client unwraps locally.

Login is two factors:

1. **First-factor** — username + password hash (and optionally OTP). Verified by Identity.
2. **KEK challenge** — Identity issues a random nonce; client signs it with the KEK; Identity verifies. The KEK itself is never transmitted.

> **TODO (security decision required):** The exact verification mechanism is undecided. Option A (HMAC/symmetric): Identity stores the verifier secret — full DB compromise allows offline passphrase brute-force. Option B (asymmetric signing): the KEK derives a keypair and Identity stores only the public part — the server cannot brute-force the passphrase from the DB alone. Must be decided before security review.

OIDC is an **opt-in convenience path** (e.g. Google, Okta) for commercial deployments. The client must still complete a local KEK unlock — the IdP cannot grant access to encrypted data.

### 3.3 The epoch lease — a Velox-specific MLS optimisation

RFC 9420 leaves **commit ordering** to client-side resolution: when two clients commit at the same epoch, the loser retries. That's correct but wasteful.

Velox adds a **per-chat epoch lease** stored in Delivery Valkey via **Compare-And-Swap (CAS)**:

```
{ epoch: N, holder: clientId, expires: TTL }
```

A client must hold the lease before submitting a commit; Delivery advances `N → N+1` only if the CAS still matches. This serialises concurrent commits and avoids wasted client work.

The lease is **spec-compatible.** RFC 9420 §3.2 explicitly sanctions server-side orchestration ("a promise from an orchestration server"). Pure client-side resolution remains the **fallback path** if the lease store is unavailable.

### 3.4 Federation: hub-and-follower replication

Chats are replicated across all participating instances. Per chat, **one instance is the hub** (MIMI terminology — replaces our earlier "leader election" language). The hub:

- Orders MLS commits for that chat.
- Defaults to **the chat creator's instance**.
- Transfers only via **explicit hub-transfer state events** (no dynamic election).

Non-hub instances forward local client MLS ops to the peer hub via Interconnect. This matches `draft-ietf-mimi-protocol`'s hub/follower model.

### 3.5 Federation trust: mTLS + ed25519

Two layers:

1. **mutual TLS** for channel and hostname authentication, per federated domain (MIMI-conformant).
2. **ed25519 instance signing key** over canonicalised request bodies for **hop-independent payload authenticity** — even if a peer terminates TLS at a load balancer, the signature can't be stripped.

Discovery: **DNS SRV** (`_velox._tcp.<domain>`) + `https://<domain>/.well-known/velox/server` JSON containing endpoint + ed25519 public key. DNSSEC recommended. Migrating to `.well-known/mimi-protocol-directory` as MIMI-conformant peers appear (WIP).

### 3.6 Why Federation Edge and Interconnect are split

Inbound and outbound federation are intentionally split across two services. Three reasons:

1. **Trust boundary.** Federation Edge is internet-facing and terminates mTLS from arbitrary, untrusted peers. Keeping it free of the instance ed25519 private key, Kafka access, and Valkey **limits the blast radius** if it is ever compromised. Interconnect runs entirely inside the internal network and is the **sole keeper of the private instance key**.
2. **Stateless router vs stateful coordinator.** Edge is a thin path-based router: zero storage, no key material, no Kafka access. Interconnect owns the ed25519 private key, the per-chat hub lease (in Interconnect Valkey), and outbound retry state — fundamentally different operational requirements.
3. **Different scaling profiles.** Edge is stateless and L4-routable with no session affinity. Interconnect's hub-lease coordination uses CAS + fencing tokens, so horizontal scaling requires care.

### 3.7 Consent before first contact

MIMI requires **explicit recipient consent** before a peer instance will release a user's KeyPackage. Without it, a remote instance could enumerate users on a peer by asking for KeyPackages.

Identity owns the **consent store** (`identityPostgres`) and the consent endpoints (`/requestConsent`, `/updateConsent`). Before Alice@velox1 can fetch Bob@velox2's KeyPackage, Bob's instance MUST have recorded an explicit consent decision.

See [§8.5 Federated consent flow](#85-federated-consent-mimi-wip).

### 3.8 Stateless services, dedicated data stores

- All compute services are **stateless**. An external load balancer fronts each (not modelled as a container).
- Each Postgres / Valkey instance is **owned by exactly one service**. Databases are never shared.
- **Scylla and Kafka are shared by design** — Scylla is the single canonical message store; Kafka is the single cross-service event bus.

### 3.9 Admin plane separation

The Admin UI + Admin API are a **separate deployment** from the user-facing services. They handle:

- Plugin registry mutations.
- Feature-flag CRUD.
- IdP configuration.
- RBAC for operator actions.
- Append-only audit log (Admin Postgres).

Centralising these in a dedicated plane keeps user-facing services free of operator-tier RBAC code paths.

### 3.10 Plugins (WASM via wazero)

Plugins ship as **WASM artifacts** stored in the object store. They run inside a **wazero** host (pure-Go, no CGo) embedded in Go services. Each plugin runs in a sandboxed module with a scoped capability ABI.

**Hot-reload** is driven by the Kafka `plugin-events` topic: when Admin API registers a new plugin, every WASM-capable service fetches the artifact from object storage and swaps in the new module without restart. In-flight requests finish against the old module. Artifact integrity is verified against a sha256 stored in the registry row.

> **Push-notification payload schema** is intentionally undefined here and will be specified during implementation. It must remain compatible with E2EE (no plaintext).

---

## 4. MIMI Alignment (WIP)

Velox targets interoperability with the IETF **MIMI** protocol (`draft-ietf-mimi-protocol`, currently `-05`, Oct 2025). **Both the MIMI spec AND Velox's MIMI conformance are work-in-progress.**

- MIMI is an Internet-Draft, not yet an RFC. Endpoint paths, wire formats (TLS presentation language), identifier schemes (`mimi://` URIs), consent flows, and hub-transfer semantics may change before publication.
- Velox implements the **MIMI-shaped architecture first**; on-the-wire conformance (mTLS, TLS presentation encoding, `mimi://` URIs, `draft-ietf-mimi-content` message format) is planned iteratively and tracked per endpoint.
- Until MIMI stabilises, Federation Edge also accepts the **legacy Velox-native federation envelope** for backward compatibility with peers that have not yet adopted MIMI.
- Compatibility with **Matrix** is intentionally pursued via MIMI's **Linearized Matrix** bridge (`draft-ralston-mimi-linearized-matrix`), **not** by implementing the Matrix S2S API / event DAG / state-resolution directly.

Every element / flow referencing MIMI in the model carries a **NOTE (WIP)** marker.

---

## 5. Services

### 5.1 Frontends — Web, Desktop, Mobile

| Frontend | Tech | Notes |
|---|---|---|
| **Web UI** | React, Next.js | Browser client. Derives KEK, runs MLS client. |
| **Desktop App** | Tauri / native | May cache wrapped keys locally. |
| **Mobile App** | React Native / native | Registers APNs/FCM device tokens via Identity. |

All three independently derive the KEK and unwrap encryption keys locally. Private key material **never** leaves the client.

### 5.2 API

Management-only service. Handles **chat and membership CRUD** and delegates history reads to Store. **Not on the message hot path** — Delivery owns that.

API also hosts WASM plugin points for message lifecycle hooks (e.g. content moderation, webhooks). Permission checks are RBAC-style against Identity before any chat operation.

When a user is added/removed, API records the change in `apiPostgres`, fetches the new member's KeyPackage (local via Identity, or remote via Interconnect), and returns it to the client for inclusion in an MLS Add/Remove commit.

### 5.3 Delivery

Realtime hub over **bidirectional WebTransport (QUIC)**. Clients construct MLS commits client-side and send them through Delivery; Delivery validates the per-chat **epoch lease** and forwards the commit to Kafka. On a successful commit:

- Publishes to `messages` (for Store + other Delivery pods to consume).
- Publishes to `push-notifications` (for Push Gateway).
- Publishes to `federation-egress` if the chat has remote participants.
- Publishes to `user-state` for ephemeral signals (presence, typing, read receipts).

Delivery never sees plaintext. It only validates the lease and forwards ciphertext.

> **Note.** A pod-local in-memory ratchet-tree cache is being considered to remove the Valkey ratchet-tree copy and reduce attack surface.

### 5.4 Store

**Sole persistent sink** for all chat data. Consumes the Kafka `messages` topic and writes MLS commits + ciphertext to **Scylla**. Exposes a paginated history-read gRPC API used by API on behalf of reconnecting clients.

Store reads `messages` as a **consumer group** so replicas share load without double-writing. Data is partitioned by `(chat_id, epoch)`; commits are append-only and never mutated.

### 5.5 Identity

Auth gate, key vault, KeyPackage directory, and the federation-facing user directory. Stores:

- Username / password hash / OTP secrets / challenge artifacts.
- **Passphrase-wrapped encryption keys.**
- Per-client MLS **KeyPackages** (single-use, pre-published).
- Per-user **consent records** for remote KeyPackage release.

Issues JWTs after a successful KEK challenge. Optionally federates to external IdPs (still gated by KEK unlock).

Acts as the MLS **Authentication Service** (RFC 9420 §5.3.1) for **local users only**. Remote-user credentials are validated client-side via the peer instance's ed25519 signature on the federation response plus the KeyPackage self-signature.

### 5.6 Federation Edge

**Stateless inbound federation gateway.** Terminates mTLS from peer instances, verifies the ed25519 signature, parses the MIMI endpoint path, and routes the call to the internal service that owns it.

- **Holds no private keys.**
- **No durable storage.**
- **No session state.**
- Pods scale horizontally behind an L4/L7 load balancer with no session affinity.
- Retries and idempotency are delegated to the owning service.

Routing table: see [§7](#7-federation-edge-routing-table).

### 5.7 Interconnect

**Outbound federation transport + per-chat hub coordinator.** Narrowed scope (inbound termination moved to Federation Edge; inbound KeyPackage serving moved to Identity).

Responsibilities:

- Consumes `federation-egress` from Kafka; signs each payload with the **instance ed25519 private key** and delivers to the peer's Federation Edge over mTLS. **The only service that holds the private key.**
- Makes outbound MIMI calls on behalf of local services (remote KeyPackage fetch, consent request, identifier query).
- Runs per-chat **hub coordination** (lease + fencing token in `interconnectValkey`):
  - When this instance is **NOT** the hub: forwards local client MLS ops to the peer hub via gRPC.
  - When it **IS** the hub: forwards commit acknowledgements and hub coordination signals back to local services. Inbound peer commits still arrive via Federation Edge → Delivery → Kafka (Delivery is the sole `messages` producer).
- Discovers peer endpoints via DNS (SRV + `.well-known`), migrating to `.well-known/mimi-protocol-directory` as MIMI peers appear (WIP).

The **fencing token** (monotonically increasing integer, issued with each lease) prevents a stale hub from writing after its lease expires.

### 5.8 Push Gateway

Consumes `push-notifications` and dispatches to **APNs** (HTTP/2), **FCM** (HTTP v1), and **Web Push** (VAPID, RFC 8030 / RFC 8292). Kept separate from Delivery to isolate third-party vendor dependencies.

Mobile clients register **device tokens** with Identity at login; Push Gateway looks them up to address a specific device. **Silent push** is used to wake the app and trigger MLS state sync before the visible notification appears, so the decrypted preview is ready immediately.

### 5.9 Admin UI & Admin API

Separate deployment.

- **Admin UI** — Operator console (React, Next.js).
- **Admin API** — Stateless Go backend. Centralises RBAC, audit logging, feature-flag CRUD, plugin registry mutations.

After a plugin is registered, Admin API publishes to `plugin-events`; WASM-capable services hot-load (see [§3.10](#310-plugins-wasm-via-wazero)).

---

## 6. Data Plane

### 6.1 Postgres instances

| Instance | Owner | Contents |
|---|---|---|
| `apiPostgres` | API | Chat metadata + membership only. (No MLS state — that's in Scylla.) |
| `identityPostgres` | Identity | Identity records, password hashes, OTP secrets, challenge artifacts, passphrase-wrapped encryption keys, KeyPackages, consent records. |
| `adminPostgres` | Admin API | Runtime config, feature flags, plugin registry metadata, audit log. |

### 6.2 Valkey instances

| Instance | Owner | Contents |
|---|---|---|
| `apiValkey` | API | Query cache, session cache, API-side rate-limit counters. |
| `identityValkey` | Identity | Auth session state, OTP verification state, login rate limits. |
| `deliveryValkey` | Delivery | Per-chat epoch lease (CAS), ratchet tree hot cache, ephemeral user-state, per-connection rate limits, WebTransport session hints. |
| `interconnectValkey` | Interconnect | Per-chat hub lease + fencing token (CAS), outbound federation retry state, peer-reachability hints. |

### 6.3 Scylla

Single canonical store for **all** chat data: MLS commits, message ciphertext, group state snapshots. Partitioned by `(chat_id, epoch)`; append-only. **Store is the only service that reads or writes it.**

### 6.4 Kafka topics

Logical topics on the central event bus:

| Topic | Producers | Consumers |
|---|---|---|
| `messages` | Delivery | Store, Delivery |
| `federation-egress` | Delivery | Interconnect |
| `user-state` | Delivery | Delivery |
| `push-notifications` | Delivery | Push Gateway |
| `consent-events` | Identity | API |
| `admin-events` | Admin API | (services that read flags) |
| `plugin-events` | Admin API | API, Delivery (any WASM-capable service) |

Inbound federation is verified by Federation Edge and ends up in `messages` directly — no separate ingress topic.

---

## 7. Federation Edge Routing Table

Federation Edge is intentionally dumb. It does not implement MIMI semantics, does not touch Scylla, does not hold the ed25519 private key. Each internal service remains the authoritative owner of its endpoints.

> **WIP.** Endpoint paths track `draft-ietf-mimi-protocol`. Names and payload formats may evolve.

| Endpoint | Routed to | Notes |
|---|---|---|
| `/keyMaterial/{user}` | Identity | Subject to consent check. |
| `/identifierQuery/{domain}` | Identity | Scoped by searchability policy. |
| `/requestConsent/{targetDomain}` | Identity | Records inbound consent request. |
| `/updateConsent/{requesterDomain}` | Identity | Records a consent decision. |
| `/update/{roomId}` | Delivery | MLS commit / proposal ingest. |
| `/submitMessage/{roomId}` | Delivery | Encrypted application message. |
| `/notify/{roomId}` | Delivery | Inbound fan-out from peer hub. |
| `/groupInfo/{roomId}` | API | GroupInfo for external joins. |
| `/reportAbuse/{roomId}` | API | Abuse report with franked message. |
| hub-coordination forward (peer assumed us hub) | Interconnect | Handoff when role changed. |

After authentication and routing, verified Commits land in the local `messages` Kafka topic via Delivery — there is no separate ingress topic.

---

## 8. Flows

Each subsection corresponds to a `flow-*.c4` view. Open the file or run `pnpm preview` for the full sequence diagram.

### 8.1 Login & key unlock

**File:** `views/flow-login.c4`

User authenticates, completes the KEK challenge, and unwraps their encryption key locally. Round-trip:

1. Client requests a login challenge from Identity.
2. Identity issues a challenge **nonce**.
3. Client derives the **KEK** from the passphrase (Argon2), signs the nonce.
4. Client submits password hash + OTP + signed challenge.
5. Identity verifies, creates a session, returns a **JWT** + the **passphrase-wrapped encryption key**.
6. Client unwraps the key locally with the KEK.

The KEK never leaves the client. The server cannot decrypt user data even with full database access.

### 8.2 Send message — local chat

**File:** `views/flow-send-message.c4`

Chat where all participants live on this instance.

- **Write path:** client → WebTransport → Delivery → Kafka.
- **Sequencing:** Delivery holds the per-chat epoch lease via Valkey CAS.
- **Persistence:** Store consumes `messages` and writes ciphertext to Scylla (sole permanent store).
- **Live fan-out:** Delivery pods consume `messages` to push to other online recipients; Push Gateway consumes `push-notifications` for offline ones.

Kafka is **transit only**; the canonical message store is Scylla.

### 8.3 Send message — federated chat

**File:** `views/flow-federated-message.c4`

Chat with participants on another instance, where **this instance is the hub**.

Same write path as local. Additionally:

- Delivery publishes a `federation-egress` event.
- Interconnect consumes it, performs DNS SRV + `.well-known` lookup, signs the payload with the instance ed25519 key, and `POST`s it to the peer's Federation Edge as `/notify/{roomId}` over mTLS.
- Peer's Federation Edge verifies the signature and routes to the peer's Delivery.

No Identity call is needed per commit — the ratchet tree on both sides already contains every member's credential.

If the local instance is **not** the hub, the local client's op is forwarded to the peer hub via Interconnect **before** commit; otherwise the flow is identical.

### 8.4 Add member — federated, post-consent

**File:** `views/flow-federated-member-add.c4`

An existing chat member adds a user from another Velox instance. **Pre-condition:** consent has already been recorded on the peer (see [§8.5](#85-federated-consent-mimi-wip)).

1. API verifies local consent cache (short-circuits to consent flow if missing — returns `202 Accepted`).
2. API asks Interconnect to fetch the remote KeyPackage (`/keyMaterial`).
3. Interconnect performs DNS lookup, mTLS POST to the peer's Federation Edge.
4. Peer returns an **ed25519-signed KeyPackage**.
5. Interconnect verifies the peer signature **and** the KeyPackage self-signature.
6. API records membership and returns the KeyPackage to the client.
7. Client constructs **both** an MLS Add Commit **and** a Welcome message (RFC 9420 §12.4 requires both).
8. Delivery publishes Commit → `messages` (for existing members) and Commit + Welcome → `federation-egress` (targeted at the peer for the new joiner).
9. Peer's Federation Edge receives, verifies, routes to peer's Delivery; the Welcome is delivered directly to the new joiner so they can reconstruct group state at the new epoch.

**Authentication Service (RFC 9420 §5.3.1) for a remote user is the *remote* instance's Identity** — its authority is proxied through the ed25519 signature on the federation response. No local Identity involvement for remote credentials.

### 8.5 Federated consent (MIMI, WIP)

**File:** `views/flow-federated-consent.c4`

First-contact consent round-trip between two Velox instances. Required before a remote KeyPackage can be fetched.

1. Alice tries to add Bob (`bob@otherVelox`); local consent cache is empty.
2. API returns `202 Accepted` to the client and asks Interconnect to call `/requestConsent` on `otherVelox`.
3. `otherVelox` queues the request and surfaces it in Bob's UI.
4. Bob decides; `otherVelox` calls our Federation Edge with `/updateConsent` carrying the decision and an opaque consent token.
5. Our Federation Edge verifies the ed25519 signature and routes to our Identity.
6. Identity stores the token keyed by `(local-user, remote-user-or-domain)`.
7. The original add-member operation resumes automatically.

**Triggers:** first attempt to add a remote user where the consent cache is empty/expired, or an explicit "request chat" / "start DM" UX action.

### 8.6 Plugin install

**File:** `views/flow-plugin-install.c4`

Operator uploads a `.wasm` plugin via Admin UI. Admin API stores the artifact in object storage and a registry row (`id`, `version`, `sha256`) in Admin Postgres. After commit, Admin API publishes `plugin-events`. All WASM-capable services (API, Delivery) consume the event, fetch the artifact from object storage, verify the sha256, and hot-load into wazero. In-flight requests finish against the old module.

---

## 9. Diagram Legend

### 9.1 Element colours

Colours are driven by tags applied in `model.c4` and bound in `styles.c4`.

| Colour | Tag | What it marks |
|---|---|---|
| Blue | `#frontend` | Client apps — Web UI, Desktop App, Mobile App. |
| Amber | `#backend` | Internal services — API, Delivery, Identity, Store, … |
| Gray | `#data` | Data stores — Postgres, Valkey, Scylla, Kafka. |
| Indigo | `#adminPlane` | Operator-facing services — Admin UI, Admin API. |
| Green | `#federation` | Federation-facing services and peer instances. |

Actor and system colours:

| Colour | Element | Why |
|---|---|---|
| Primary | `user` | End user — neutral, no subsystem affiliation. |
| Indigo | `adminOperator` | Consistent with `#adminPlane`. |
| Green | `otherVelox` | Consistent with `#federation`. |
| Primary | `velox` | The Velox system itself (landscape view only). |
| Muted | External systems | Third-party dependencies (APNs, FCM, IdP, object storage). |

### 9.2 Relationship line styles

Defined in `specification.c4`.

| Style | Kind | Meaning |
|---|---|---|
| Amber dotted ◇ | `async` | Kafka pub/sub — fire-and-forget, no response. |
| Green dashed | `federation` | Cross-instance over mTLS + ed25519 payload signing. |
| Indigo solid | `realtime` | Bidirectional WebTransport / QUIC (persistent). |
| Default solid | (sync) | Synchronous request/response — gRPC or HTTPS. |

> Amber is overloaded — element backgrounds for `#backend` and edge style for `async`. These are visually distinct contexts (box vs edge), so the overlap is acceptable.

---

## 10. Glossary

**Add proposal + Commit** — MLS operation introducing a new leaf into the ratchet tree. Broadcast to existing members.

**APNs (Apple Push Notification service)** — Apple's push channel for iOS/macOS. HTTP/2 API.

**AS (Authentication Service)** — RFC 9420 §5.3.1 concept. Identity is the AS for local users; remote-user credentials are validated client-side via the peer's ed25519 signature plus the KeyPackage self-signature.

**Append-only** — MLS commits are written once and never updated. History is reconstructed by replaying commits in epoch order.

**Audit log** — Append-only record of operator actions in Admin Postgres.

**CAS (Compare-And-Swap)** — Atomic Valkey operation enforcing epoch ordering and hub-lease correctness.

**Challenge nonce** — Random value issued by Identity at login start, signed with the KEK to prove passphrase knowledge without ever transmitting the KEK.

**Consent (WIP, MIMI)** — Per-user, per-requester permission to release a KeyPackage. See [§3.7](#37-consent-before-first-contact).

**Consent token** — Opaque blob returned in `/updateConsent`. Cached locally so subsequent calls skip re-prompting until expiry.

**CQL (Cassandra Query Language)** — Used by Store to read/write Scylla.

**Credential** — Identity-specific assertion binding a user identifier to their MLS signing key.

**Device token** — Platform-specific identifier registered by mobile app with Identity at login.

**DNS SRV** — `_velox._tcp.<domain>` discovery record for federation, paired with `.well-known/velox/server`. DNSSEC recommended.

**E2EE (End-to-End Encryption)** — Only communicating clients hold the keys. The server stores and forwards ciphertext only.

**ed25519** — Edwards-curve signature scheme. Each instance signs outbound federation payloads; the public key is published in `.well-known/velox/server`.

**Epoch** — A versioned state of an MLS group. Each Commit advances the epoch by exactly 1.

**Epoch Lease** — Velox-specific, RFC 9420-compatible optimisation: short-lived `{epoch, holder, expires}` grant in Delivery Valkey admitting one committer per epoch.

**FCM (Firebase Cloud Messaging)** — Google's push channel for Android and web. HTTP v1 API.

**Feature flag** — Runtime toggle stored in Admin Postgres. Propagated via `admin-events`.

**Federation** — Matrix-style replication: chats span multiple Velox instances; each instance handles messages for its own members.

**Federation Edge** — Stateless inbound gateway for federation traffic. See [§5.6](#56-federation-edge).

**federation-egress** — Kafka topic carrying outbound federation traffic (Commits, Welcomes, KeyPackage requests, consent requests).

**Fencing token** — Monotonically increasing integer issued with each hub lease. Prevents a stale hub from writing after lease expiry.

**Hot-reload** — WASM plugin swap without process restart, driven by `plugin-events`.

**Hub (MIMI, WIP)** — The instance responsible for ordering MLS commits for a chat. Defaults to the chat creator's instance; transfers via explicit hub-transfer state events.

**JWT (JSON Web Token)** — Signed bearer token issued after the KEK challenge. Validated independently by other services.

**KEK (Key Encryption Key)** — Derived client-side from the user's passphrase. Wraps the real encryption key. Never transmitted.

**KeyPackage** — Pre-published, single-use signed bundle (RFC 9420) containing a client's credential + HPKE public key.

**MIMI** — More Instant Messaging Interoperability. IETF WG draft (`draft-ietf-mimi-protocol`). MLS-based federation protocol Velox targets for cross-provider interop. **WIP.**

**`mimi://` URIs (WIP)** — MIMI's canonical identifier scheme (`mimi://domain/u/user`).

**MLS (Messaging Layer Security)** — RFC 9420. Cryptographic group key-agreement.

**mTLS (mutual TLS)** — Channel + hostname authentication for federation.

**OIDC (OpenID Connect)** — Optional external IdP path. Convenience layer; KEK unlock still required.

**OTP (One-Time Password)** — Optional TOTP second factor (RFC 6238).

**Passphrase-wrapped key** — The real MLS encryption key, encrypted with the KEK. Server-side storage.

**Pre-signed URL** — Short-lived scoped URL from S3-compatible storage. Clients upload/download encrypted media directly, bypassing Velox backend services.

**Ratchet Tree** — MLS internal data structure tracking group membership.

**RBAC (Role-Based Access Control)** — Operator access model enforced by Admin API.

**Silent push** — Push that wakes the app in the background without a banner; used to trigger MLS state sync before the visible notification.

**user-state** — Umbrella Kafka topic + Valkey namespace for ephemeral per-user signals (presence, typing, read receipts).

**VAPID** — Voluntary Application Server Identification (RFC 8292). Authenticates Web Push without a vendor account.

**wazero** — Pure-Go WebAssembly runtime (no CGo) hosting WASM plugins inside Velox services.

**Welcome message** — RFC 9420 §12.4. Required alongside the Commit when adding a member; carries GroupInfo + ratchet tree so the new member can reconstruct group state at the new epoch.

**WebTransport** — Bidirectional QUIC-based protocol used for realtime client ↔ Delivery traffic.

---

## 11. Architectural Notes & Open Decisions

1. **Push payload schema** must remain E2EE-compatible. Current intent: **silent push only** — the APNs/FCM/Web Push payload carries no sender ID, chat ID, or message content; it only wakes the app to trigger an MLS state sync.

2. **Pod-local ratchet-tree cache** is being considered as a replacement for the Valkey ratchet-tree copy in Delivery Valkey, to reduce attack surface. Not yet a decision.

3. **Legacy Velox-native federation envelope** is accepted by Federation Edge alongside MIMI as long as MIMI is in draft. Plan a deprecation pass once MIMI stabilises.

4. **MIMI directory migration** — `.well-known/velox/server` → `.well-known/mimi-protocol-directory`. Will need a discovery fallback period.

5. **"All services stateless"** in §3.8 is a slight simplification: Interconnect owns hub-lease state in its Valkey. The compute layer is stateless (Valkey holds the state).

### Threat-model TODOs (design decisions outstanding)

These require an explicit decision before a security review. They are annotated in the model where applicable.

- **KEK challenge verification** (§3.2) — HMAC vs. asymmetric signing. See the TODO block in §3.2 above.
- **Multi-device key bootstrapping** — How does a second device receive the passphrase-wrapped encryption key? Cross-device KEK provisioning / device cross-signing is not yet modeled.
- **Key transparency / KeyPackage poisoning** — Identity is a fully trusted root for local KeyPackages. A compromised Identity can substitute keys. An append-only verifiable log (à la KT / CONIKS) is not currently modeled; if required, this would be a significant addition.
- **Sealed-sender / in-instance metadata privacy** — Sender identity within a Velox instance is visible to the server. If Signal-style sealed sender or equivalent metadata minimisation is desired, it must be explicitly designed.
- **Plugin signing / provenance** — Plugin WASM artifacts are verified by sha256 only. This protects integrity-from-storage corruption but not authenticity (a compromised Admin API could register a malicious plugin). Cosign / Sigstore / vendor key pinning is not yet modeled.
- **Member-add commit ordering** — In `flow-federated-member-add`, the API records the new membership in `apiPostgres` before the MLS Add commit is acknowledged. Whether this row should be conditional on commit success needs to be specified.
- **Welcome routing for local-only adds** — The federated member-add flow covers remote new members (Welcome via `federation-egress`). The path for a Welcome to a *local* new member is not yet modeled.
- **Inbound peer-commit lease semantics** — When a peer hub sends a commit to a follower Delivery, it is unclear whether Delivery enforces its local epoch lease for the peer-originated commit (risking deadlock) or treats hub-serialised commits as pre-ordered. Must be specified.
