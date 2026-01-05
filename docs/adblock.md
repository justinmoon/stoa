# Ad Blocking in CEF

How to replicate uBlock Origin's functionality inside our CEF browser pane.

## TL;DR: Feasibility

| uBlock Feature | CEF Support | Difficulty |
|----------------|-------------|------------|
| Network request blocking | ✅ Full | Easy |
| Cosmetic filtering (CSS hiding) | ✅ Full | Easy |
| Scriptlet injection | ✅ Full | Medium |
| Procedural filters | ✅ Full | Medium |
| HTML filtering | ⚠️ Partial | Hard |
| Header modification | ⚠️ Limited | Medium |
| YouTube ad blocking | ✅ Yes | Medium |
| CNAME uncloaking | ❌ No | N/A |

**Bottom line:** We can implement 90%+ of uBlock Origin's functionality. The hard parts (CNAME uncloaking) are edge cases.

---

## uBlock Origin Blocking Types

### 1. Network Request Blocking (Core)

**What it does:** Blocks HTTP requests before they're made.

**uBlock implementation:** Uses `webRequest.onBeforeRequest` API to intercept and cancel requests matching filter patterns.

**CEF equivalent:** `CefResourceRequestHandler::OnBeforeResourceLoad()`

```zig
// In stoa-browser (Zig)
fn onBeforeResourceLoad(
    browser: *CefBrowser,
    frame: *CefFrame,
    request: *CefRequest,
) CefReturnValue {
    const url = request.getUrl();
    const resource_type = request.getResourceType();

    if (filter_engine.shouldBlock(url, resource_type)) {
        return .cancel;  // Block the request
    }
    return .continue;  // Allow the request
}
```

**Supported resource types in CEF:**
- `RT_MAIN_FRAME` - Top-level page
- `RT_SUB_FRAME` - Iframes
- `RT_STYLESHEET` - CSS
- `RT_SCRIPT` - JavaScript
- `RT_IMAGE` - Images
- `RT_FONT_RESOURCE` - Fonts
- `RT_MEDIA` - Audio/video
- `RT_WORKER` - Web workers
- etc.

**Verdict:** ✅ Full support. This is the easy part.

---

### 2. Cosmetic Filtering (Element Hiding)

**What it does:** Hides page elements using CSS selectors without blocking network requests.

**Examples:**
```
##.ad-banner           → Hide elements with class "ad-banner"
##div[id^="google_ads"] → Hide divs with id starting with "google_ads"
youtube.com##.ytp-ad-module → YouTube-specific hiding
```

**CEF implementation:** Inject CSS via JavaScript at context creation.

```zig
// In CefRenderProcessHandler::OnContextCreated
fn onContextCreated(browser: *CefBrowser, frame: *CefFrame, context: *CefV8Context) void {
    const css_rules = cosmetic_engine.getRulesForHostname(frame.getUrl());

    const inject_script = std.fmt.allocPrint(
        \\const style = document.createElement('style');
        \\style.textContent = `{s}`;
        \\(document.head || document.documentElement).appendChild(style);
    , .{css_rules});

    frame.executeJavaScript(inject_script, "", 0);
}
```

**Timing options:**
- `OnContextCreated` - Earliest, before any page JS runs
- `OnLoadStart` - After navigation commits
- `OnLoadEnd` - After page fully loads (too late for cosmetic)

**Verdict:** ✅ Full support. Inject CSS early via `OnContextCreated`.

---

### 3. Scriptlet Injection

**What it does:** Injects JavaScript to intercept/modify page behavior at runtime.

**Examples:**
```
###+js(set-constant, isAdBlockerEnabled, false)
###+js(prevent-fetch, url:ads)
###+js(json-prune, playerResponse.adPlacements)
```

**uBlock scriptlets** (26 core files):
- `set-constant.js` - Set variables to fixed values
- `prevent-fetch.js` - Block fetch() calls matching patterns
- `json-prune.js` - Remove properties from JSON responses
- `prevent-setTimeout.js` - Block setTimeout matching patterns
- `abort-on-property-read.js` - Throw when property accessed
- etc.

**CEF implementation:** Same as cosmetic - inject at `OnContextCreated`.

```zig
fn onContextCreated(browser: *CefBrowser, frame: *CefFrame, context: *CefV8Context) void {
    const hostname = parseHostname(frame.getUrl());
    const scriptlets = scriptlet_engine.getScriptletsForHostname(hostname);

    for (scriptlets) |scriptlet| {
        // Inject before page scripts run
        frame.executeJavaScript(scriptlet.code, "", 0);
    }
}
```

**Critical:** Must inject at `OnContextCreated` (before page JS runs) to intercept globals.

**Verdict:** ✅ Full support. Key for YouTube ad blocking.

---

### 4. Procedural Filters

**What it does:** Complex CSS selectors with special operators for DOM traversal.

**Examples:**
```
##.video-ads:has(> .ad-showing)
##div:has-text(Advertisement)
##.container:if-not(.legitimate-content)
##article:min-text-length(100)
```

**Operators:**
- `:has()` - Check for child elements
- `:has-text()` - Match text content
- `:if()` / `:if-not()` - Conditional matching
- `:matches-css()` - Match CSS properties
- `:nth-ancestor()` - Select parent elements
- `:upward()` - Move up DOM tree
- `:min-text-length()` / `:max-text-length()`

**CEF implementation:** Inject JavaScript that implements these selectors + MutationObserver.

```javascript
// Injected procedural filter runtime
function applyProceduralFilters(filters) {
    const observer = new MutationObserver((mutations) => {
        for (const filter of filters) {
            const elements = evaluateProceduralSelector(filter.selector);
            for (const el of elements) {
                el.style.setProperty('display', 'none', 'important');
            }
        }
    });
    observer.observe(document, { childList: true, subtree: true });
}
```

**Verdict:** ✅ Full support. Requires shipping a procedural filter runtime (~500 lines JS).

---

### 5. HTML Filtering

**What it does:** Removes HTML elements from the response before parsing.

**Syntax:** `##^html(script[src*="ads"])`

**uBlock implementation:** Uses `webRequest.filterResponseData()` to modify HTML stream.

**CEF equivalent:** `CefResponseFilter` - but it's byte-level, not DOM-level.

```cpp
// CefResponseFilter::Filter() receives raw bytes
// Would need to parse HTML, modify, re-serialize
// Complex and error-prone
```

**Alternative:** Use DOM manipulation after parsing instead:
```javascript
// Injected at OnContextCreated
new MutationObserver((mutations) => {
    document.querySelectorAll('script[src*="ads"]').forEach(el => el.remove());
}).observe(document, { childList: true, subtree: true });
```

**Verdict:** ⚠️ Partial. Use DOM manipulation instead of response filtering. Works for most cases.

---

### 6. Header Modification

**What it does:** Removes/modifies HTTP response headers.

**Syntax:** `##^responseheader(x-tracking-id)`

**CEF support:** `CefResourceRequestHandler::OnResourceResponse()` - but it's **read-only**.

```cpp
// CEF doesn't allow modifying response headers after the fact
// Can only observe them
```

**Workaround:** For CSP headers specifically, could inject meta tag override:
```javascript
// Loosen CSP via meta tag (limited effectiveness)
const meta = document.createElement('meta');
meta.httpEquiv = 'Content-Security-Policy';
meta.content = "...";
document.head.appendChild(meta);
```

**Verdict:** ⚠️ Limited. Can observe but not modify most headers. Usually not critical for ad blocking.

---

### 7. YouTube Ad Blocking (The Hard One)

YouTube ads are tricky because:
1. Ads are served from same domain (`youtube.com`, `googlevideo.com`)
2. Ad/content URLs are similar
3. Ads load via JavaScript, not separate requests
4. YouTube actively fights ad blockers

**How uBlock blocks YouTube ads:**

1. **Scriptlet injection** to intercept player initialization:
```
youtube.com##+js(json-prune, playerResponse.adPlacements)
youtube.com##+js(set-constant, ytInitialPlayerResponse.adPlacements, undefined)
```

2. **Cosmetic filters** to hide ad UI:
```
youtube.com##.ytp-ad-module
youtube.com##.video-ads
youtube.com##.ytp-ad-overlay-slot
```

3. **Network blocking** for known ad endpoints:
```
||youtube.com/api/stats/ads$xhr
||youtube.com/pagead/
```

**CEF implementation:**

```zig
// 1. Block known ad URLs in OnBeforeResourceLoad
fn onBeforeResourceLoad(request: *CefRequest) CefReturnValue {
    const url = request.getUrl();
    if (std.mem.indexOf(u8, url, "/pagead/") != null or
        std.mem.indexOf(u8, url, "/api/stats/ads") != null) {
        return .cancel;
    }
    return .continue;
}

// 2. Inject scriptlets at OnContextCreated
fn onContextCreated(frame: *CefFrame) void {
    if (isYouTube(frame.getUrl())) {
        frame.executeJavaScript(youtube_adblock_scriptlet, "", 0);
    }
}
```

**The critical scriptlet** (simplified):
```javascript
// Intercept player response to remove ad placements
const originalParse = JSON.parse;
JSON.parse = function(text) {
    const obj = originalParse(text);
    if (obj && obj.adPlacements) {
        delete obj.adPlacements;
    }
    if (obj && obj.playerAds) {
        delete obj.playerAds;
    }
    return obj;
};
```

**Verdict:** ✅ Yes, but requires maintaining YouTube-specific scriptlets. uBlock's filter lists already have these.

---

### 8. CNAME Uncloaking

**What it does:** Resolves CNAME DNS records to detect first-party-disguised trackers.

**Example:** `tracker.example.com` → CNAME → `tracker.adtech.com`

**uBlock implementation:** Uses DNS resolution APIs available in Firefox.

**CEF support:** ❌ No DNS resolution API exposed.

**Workaround:** None practical. Would need external DNS resolver.

**Verdict:** ❌ Not supported. Edge case - most blocking works without it.

---

## Implementation Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    stoa-browser (Zig)                       │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  FilterEngine                                         │  │
│  │    ├── NetworkFilter (EasyList patterns)              │  │
│  │    ├── CosmeticFilter (CSS selectors per hostname)    │  │
│  │    └── ScriptletFilter (JS injection per hostname)    │  │
│  └───────────────────────────────────────────────────────┘  │
│                          │                                  │
│  ┌───────────────────────┴───────────────────────────────┐  │
│  │  CEF Hooks                                            │  │
│  │    ├── OnBeforeResourceLoad → NetworkFilter.check()   │  │
│  │    ├── OnContextCreated → inject CSS + scriptlets     │  │
│  │    └── (MutationObserver for procedural filters)      │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Filter List Format

Use standard EasyList/uBlock format. Parse at startup:

```
! Network filters
||ads.example.com^
||tracking.com/pixel$image

! Cosmetic filters
##.ad-banner
example.com##.site-specific-ad

! Scriptlet filters
youtube.com##+js(json-prune, adPlacements)
```

**Parser complexity:** Medium. uBlock's parser is ~4,400 lines. We can start simpler.

## Data Structures

uBlock uses optimized tries for fast matching:
- **HNTrie** - Hostname matching (reversed strings)
- **BidiTrie** - Bidirectional URL pattern matching

For MVP, simpler structures work:
- HashSet of blocked domains
- Regex patterns for URL matching
- HashMap of hostname → CSS rules

Optimize later if needed.

## What We Ship

```
~/.config/stoa/filters/
├── easylist.txt           # Main ad blocking list
├── easyprivacy.txt        # Tracker blocking
├── ublock-filters.txt     # uBlock-specific filters
├── ublock-badware.txt     # Malware domains
└── custom.txt             # User's custom filters
```

**Update mechanism:** Fetch lists periodically (weekly), diff and reload.

## Effort Estimate

| Component | Effort | Notes |
|-----------|--------|-------|
| Network blocking | 1-2 days | OnBeforeResourceLoad + pattern matching |
| Filter list parser | 2-3 days | Parse EasyList format |
| Cosmetic filtering | 1-2 days | CSS injection at context creation |
| Scriptlet injection | 2-3 days | Port key scriptlets, inject early |
| Procedural filters | 3-5 days | JS runtime for :has(), :has-text(), etc. |
| YouTube blocking | 1-2 days | Specific scriptlets, test thoroughly |
| **Total MVP** | **~2 weeks** | Core blocking working |

## What Won't Work

1. **CNAME uncloaking** - No DNS API in CEF
2. **Response header modification** - CEF is read-only
3. **Service worker interception** - Limited CEF support
4. **Extension-based filter updates** - We handle this ourselves

## References

- `~/code/ublock` - uBlock Origin source (reference for filter parsing, scriptlets)
- `~/code/cef` - CEF source (API reference)
- [EasyList](https://easylist.to/) - Primary filter lists
- [uBlock filter syntax](https://github.com/gorhill/uBlock/wiki/Static-filter-syntax)
