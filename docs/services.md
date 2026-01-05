# Stoa Services Architecture

## Vision

Stoa provides **environment-level services** that apps consume. Apps stay lean; Stoa owns shared infrastructure.

```
┌─────────────────────────────────────────────────────────────┐
│                         Stoa                                │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  StoaServices                                         │  │
│  │    ├── LspRegistry      (language servers)            │  │
│  │    ├── PasswordManager  (credentials, yubikey)        │  │
│  │    ├── NostrSigner      (NIP-07, key management)      │  │
│  │    └── (future: git, file watching, search index...)  │  │
│  └───────────────────────────────────────────────────────┘  │
│         ▲              ▲              ▲                     │
│         │              │              │                     │
│    ┌────┴────┐   ┌────┴────┐   ┌────┴─────┐                │
│    │ Editor  │   │ Browser │   │  Agent   │                │
│    │ Pane    │   │ Pane    │   │  Pane    │                │
│    └─────────┘   └─────────┘   └──────────┘                │
└─────────────────────────────────────────────────────────────┘
```

## Why Environment-Level?

If each app owns its own instances:
- 3 editor panes = 3 rust-analyzer processes = 3x memory
- 3 browser panes = 3 separate password stores = sync nightmare
- No cross-app coordination (agent can't see editor's diagnostics)

With Stoa services:
- One rust-analyzer per (workspace, language)
- One password store, accessible from any pane
- Unified state across the environment

---

## Service: LSP Registry

Language servers shared across editors and agents.

### Contract

```rust
pub trait LspClient: Send + Sync + 'static {
    fn completions(&self, file: &Path, content: &str, pos: Point, trigger: Option<String>)
        -> Task<Result<Vec<LspCompletion>>>;
    fn hover(&self, file: &Path, content: &str, pos: Point)
        -> Task<Result<Option<LspHover>>>;
    fn goto_definition(&self, file: &Path, content: &str, pos: Point)
        -> Task<Result<Vec<LspLocation>>>;
    fn subscribe_diagnostics(&self, file: &Path) -> Receiver<Vec<LspDiagnostic>>;
    fn did_open(&self, file: &Path, content: &str, language_id: &str);
    fn did_change(&self, file: &Path, content: &str);
    fn did_close(&self, file: &Path);
}
```

### Implementation

```rust
struct StoaLspRegistry {
    // Key: (workspace_root, language_id)
    servers: HashMap<(PathBuf, String), LspSession>,
}

struct LspSession {
    process: Child,
    connection: JsonRpcConnection,
    open_documents: HashMap<PathBuf, HashSet<PaneId>>,  // refcounted
    subscribers: HashMap<PaneId, DiagnosticCallback>,
}
```

Document lifecycle with refcounting:
- First pane opens file.rs → send `didOpen` to server
- Second pane opens same file → just track subscription
- Last pane closes → send `didClose` to server

### Development Strategy

Two implementations for standalone vs integrated:

| Implementation | Used When | Who Owns Servers |
|----------------|-----------|------------------|
| `DirectLspClient` | Standalone `z` development | z binary |
| `StoaLspClient` | Running inside Stoa | Stoa |

```rust
let lsp_client: Arc<dyn LspClient> = if let Ok(socket) = env::var("STOA_LSP_SOCKET") {
    Arc::new(StoaLspClient::connect(&socket))  // Stoa-hosted
} else {
    Arc::new(DirectLspClient::new())  // Standalone
};
```

---

## Service: Password Manager

Simple, local, yubikey-backed credential store.

### Storage

```
~/.config/stoa/passwords.age
    ↓ (decrypted with yubikey via age)
{
    "github.com": { "user": "...", "pass": "..." },
    "vercel.com": { "user": "...", "pass": "..." }
}
```

### Contract

```rust
pub trait PasswordStore: Send + Sync + 'static {
    fn get(&self, domain: &str) -> Option<Credential>;
    fn set(&self, domain: &str, credential: Credential);
    fn list_domains(&self) -> Vec<String>;
}

pub struct Credential {
    pub username: String,
    pub password: String,
}
```

### Browser Integration

1. User hits hotkey (Cmd+.)
2. Stoa looks up current URL's domain
3. Injects credentials into focused inputs

```javascript
// Injected by Stoa into browser pane
document.querySelector('input[type="email"], input[name="user"]').value = username;
document.querySelector('input[type="password"]').value = password;
```

### Alternative: `pass` Integration

Could shell out to existing `pass` CLI:

```rust
fn get(&self, domain: &str) -> Option<Credential> {
    let output = Command::new("pass").arg("show").arg(domain).output()?;
    // Parse output
}
```

---

## Service: Nostr Signer

NIP-07 implementation for Nostr authentication.

### Contract

```rust
pub trait NostrSigner: Send + Sync + 'static {
    fn get_public_key(&self) -> String;
    fn sign_event(&self, event: NostrEvent) -> SignedEvent;
    fn nip04_encrypt(&self, pubkey: &str, plaintext: &str) -> String;
    fn nip04_decrypt(&self, pubkey: &str, ciphertext: &str) -> String;
}
```

### Browser Integration

Stoa injects `window.nostr` into all browser panes:

```javascript
window.nostr = {
    async getPublicKey() {
        return await stoaBridge.call('nostr.getPublicKey');
    },
    async signEvent(event) {
        return await stoaBridge.call('nostr.signEvent', event);
    },
    nip04: {
        async encrypt(pubkey, plaintext) {
            return await stoaBridge.call('nostr.encrypt', { pubkey, plaintext });
        },
        async decrypt(pubkey, ciphertext) {
            return await stoaBridge.call('nostr.decrypt', { pubkey, ciphertext });
        }
    }
};
```

### Key Storage

Same pattern as passwords - age-encrypted, yubikey-backed:

```
~/.config/stoa/nostr.age
    ↓
{ "private_key": "nsec1..." }
```

---

## IPC Pattern

All services use the same IPC pattern:

| Method | Pros | Cons |
|--------|------|------|
| Unix socket + JSON-RPC | Simple, debuggable | Serialization overhead |
| Shared memory | Fast, zero-copy | Complex |
| Direct FFI | Fastest | Requires static linking |

Start with Unix socket for all services. Easy to debug, consistent pattern.

---

## Open Questions

1. **Service discovery**: How do apps find services? Env vars? Well-known socket paths?
2. **Lifecycle**: Start services on demand? Keep running? Timeout idle services?
3. **Config**: stoa.toml? Nix? Per-service config files?
4. **Permissions**: Can any app access any service? Sandboxing?

---

## Zed Editor Integration Note

Zed's Editor uses trait objects, not concrete implementations:

```rust
pub struct Editor {
    completion_provider: Option<Rc<dyn CompletionProvider>>,
    semantics_provider: Option<Rc<dyn SemanticsProvider>>,
}
```

We implement adapters that wrap Stoa's `LspClient` and implement Zed's traits. The editor stays lean.
