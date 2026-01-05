# Browser Architecture

## Decision: CEF over WKWebView

WKWebView works but lacks the killer feature: **Chrome DevTools Protocol (CDP)**.

CDP enables the coding agent to:
- Navigate and interact with web apps
- Fill forms, click buttons, read DOM
- Execute JavaScript, inspect state
- Set breakpoints, profile performance
- Take screenshots, intercept network
- Basically: Puppeteer/Playwright built into Stoa

This is transformative for an AI-native dev environment where agents debug and test web apps.

## Build Approach: Nix + Zig

**Nix** handles CEF acquisition (no official nixpkgs package, so we write a simple derivation):

```nix
# nix/cef.nix
{ fetchurl, stdenv, version, platform }:

stdenv.mkDerivation {
  pname = "cef-minimal";
  inherit version;

  # Spotify CDN hosts official CEF builds
  src = fetchurl {
    url = "https://cef-builds.spotifycdn.com/cef_binary_${version}...${platform}_minimal.tar.bz2";
    sha256 = "...";
  };

  installPhase = ''
    mkdir -p $out/{include,lib,share}
    cp -r include/* $out/include/
    cp -r Release/* $out/lib/
    cp -r Resources/* $out/share/cef/
  '';
}
```

**Reference:** `~/code/cefzig` for platform/version mapping (we don't use its fetcher, just its knowledge of CEF's URL patterns and archive structure).

**Zig** builds the wrapper library:

```
Nix (flake.nix)
├── Fetches CEF SDK (pinned version, verified hash)
├── Provides as derivation
└── Sets CEF_PATH for builds

stoa-browser (Zig)
├── Imports headers from CEF_PATH
├── CEF initialization
├── Offscreen rendering → pixel buffer
├── CDP exposure
├── C API for Swift bridging

Stoa (Swift/AppKit)
├── NSView renders pixel buffer
└── Forwards input events
```

## No Extensions Needed

We don't need Chrome extensions. We replace them with:

1. **Built-in browser features** (ad blocking)
2. **Stoa services** the browser consumes (passwords, nostr signing - see `docs/services.md`)

### Ad Blocking (Built Into Browser)

Ad blocking is a **browser feature**, not a Stoa service. It's built directly into our CEF browser pane.

Implementation via CDP:
```
Network.requestWillBeSent → match URL against filter lists → block or allow
```

Uses standard filter lists (EasyList, EasyPrivacy, etc.) - no uBlock Origin runtime needed.

```zig
// In stoa-browser (Zig)
fn shouldBlock(url: []const u8) bool {
    return filter_list.matches(url);
}

// Hook into CEF's resource request handler
fn onBeforeResourceLoad(request: *CefRequest) CefReturnValue {
    if (shouldBlock(request.getUrl())) {
        return .cancel;
    }
    return .continue;
}
```

Filter lists stored in `~/.config/stoa/filters/`, fetched periodically.

### Stoa Services (Browser Consumes)

The browser pane also integrates with Stoa services:

- **Password Manager** → Hotkey fills credentials (see `docs/services.md`)
- **Nostr Signer** → Injects `window.nostr` for NIP-07 (see `docs/services.md`)

These are services because other apps might use them too (e.g., agent needs nostr identity).

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                          Stoa                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  StoaServices (see docs/services.md)                  │  │
│  │    ├── PasswordManager                                │  │
│  │    └── NostrSigner                                    │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  StoaBrowserService                                   │  │
│  │    ├── CDP connection to all browser panes            │  │
│  │    └── Exposes browser control to agents              │  │
│  └───────────────────────────────────────────────────────┘  │
│         │                                                   │
│    ┌────┴────────────────────────────────────────────────┐  │
│    │  CEF Browser Panes (stoa-browser)                   │  │
│    │    ├── Ad blocking (built-in, filter lists)         │  │
│    │    ├── Password autofill (via Stoa service)         │  │
│    │    └── Nostr signing (via Stoa service)             │  │
│    └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Future: Ladybird

When Ladybird browser matures, evaluate as CEF replacement:
- Truly independent (no Google, no Apple)
- Clean codebase
- But: no CDP equivalent yet, limited compatibility

For now, CEF is the pragmatic choice.

## References

**CEF Integration:**
- `~/code/cefzig` - Zig CEF build tool (reference for URL patterns, version mapping)
- [tauri-apps/cef-rs](https://github.com/tauri-apps/cef-rs) - Rust CEF bindings by Tauri team (good patterns, prefer Zig but useful reference)

**Browser Research:**
- `~/code/helium` - Privacy-focused Chromium (reference for patches)
- `~/code/ungoogled-chromium` - De-googled Chromium patchset
- [helium-flake](https://github.com/amaanq/helium-flake) - Nix packaging for Helium

**Web Services:**
- [NIP-07](https://github.com/nostr-protocol/nips/blob/master/07.md) - Nostr signer spec
- [EasyList](https://easylist.to/) - Ad blocking filter lists
