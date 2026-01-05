# Stoa - Tiling Window Manager for AI-driven Development

default:
    just --list

# Path to the ghostty repo
ghostty_dir := env_var_or_default("GHOSTTY_DIR", home_directory() / "code" / "ghostty")
zed_dir := env_var_or_default("ZED_ROOT", home_directory() / "code" / "zed")
app_bundle_dir := justfile_directory() / "build" / "Stoa.app"
zed_lib_dir := justfile_directory() / "Libraries" / "ZedKit"

# Build libghostty xcframework from ghostty repo
build-libghostty:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Building libghostty from {{ghostty_dir}}..."
    cd "{{ghostty_dir}}"
    zig build -Dapp-runtime=none -Demit-xcframework
    echo "Built xcframework at {{ghostty_dir}}/zig-out/lib/GhosttyKit.xcframework"

# Copy libghostty artifacts to our project
copy-libghostty: build-libghostty
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf Libraries/GhosttyKit.xcframework
    mkdir -p Libraries/include
    cp -R "{{ghostty_dir}}/macos/GhosttyKit.xcframework" Libraries/
    cp "{{ghostty_dir}}/include/ghostty.h" Libraries/include/
    echo "Copied GhosttyKit.xcframework to Libraries/"

# Fetch CEF SDK into Libraries/CEF (requires cefzig)
fetch-cef:
    ./scripts/fetch_cef.sh

# E2E: launch Chromium pane and verify a rendered frame is produced
e2e-chromium:
    ./scripts/e2e_chromium_render.py
# Build the z editor from the local Zed checkout
build-z:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Building z from {{zed_dir}}..."
    cd "{{zed_dir}}"
    cargo build -p z
    echo "Built z at {{zed_dir}}/target/debug/z"

# Copy zed embedded artifacts to our project
copy-libzed: build-z
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "{{zed_lib_dir}}"
    mkdir -p "{{zed_lib_dir}}"
    cp "{{zed_dir}}/target/debug/libz.a" "{{zed_lib_dir}}/libz.a"
    cp "{{zed_dir}}/crates/z/zed_embed.h" "{{zed_lib_dir}}/zed_embed.h"
    echo "Copied Zed embedded artifacts to {{zed_lib_dir}}"

# Build the Stoa app
build: copy-libghostty copy-libzed
    swift build

# Build for release
build-release: copy-libghostty copy-libzed
    swift build -c release

# Run Stoa
run: build
    bin_path="$(swift build --show-bin-path)"; \
    DYLD_FRAMEWORK_PATH="$PWD/Libraries/CEF" \
      DYLD_LIBRARY_PATH="$PWD/Libraries/CEF/Chromium Embedded Framework.framework/Libraries" \
      "$bin_path/stoa"

# Build a minimal .app bundle for Accessibility permissions
build-app: copy-libghostty copy-libzed
    #!/usr/bin/env bash
    set -euo pipefail
    swift build
    app="{{app_bundle_dir}}"
    contents="$app/Contents"
    macos="$contents/MacOS"
    resources="$contents/Resources"
    bin_path="$(swift build --show-bin-path)/stoa"
    mkdir -p "$macos" "$resources"
    cp -f "$bin_path" "$macos/stoa"
    cat <<'PLIST' > "$contents/Info.plist"
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleName</key>
        <string>Stoa</string>
        <key>CFBundleDisplayName</key>
        <string>Stoa</string>
        <key>CFBundleIdentifier</key>
        <string>com.stoa.dev</string>
        <key>CFBundleExecutable</key>
        <string>stoa</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>CFBundleShortVersionString</key>
        <string>0.1.0</string>
        <key>CFBundleVersion</key>
        <string>0.1.0</string>
        <key>NSHighResolutionCapable</key>
        <true/>
    </dict>
    </plist>
    PLIST
    echo "Built app bundle: $app"

# Run Stoa from the app bundle (needed for Accessibility)
dev-app: build-app
    open "{{app_bundle_dir}}"

# End-to-end embed test (requires Accessibility permission for Stoa.app)
test-embed: build-app
    #!/usr/bin/env bash
    set -euo pipefail
    tmpfile="$(mktemp /tmp/stoa-embed.XXXXXX)"
    echo "embed test" > "$tmpfile"
    STOA_EDITOR_EMBED_TEST=1 STOA_EDITOR_FILE="$tmpfile" "{{app_bundle_dir}}/Contents/MacOS/stoa"

# Run tests
test:
    swift test

# Run all checks before merging
pre-merge: check-deps test e2e-chromium
    @echo "Pre-merge checks complete."

# Clean build artifacts
clean:
    swift package clean
    rm -rf .build
    rm -rf Libraries/GhosttyKit.xcframework
    rm -rf Libraries/include
    rm -rf "{{zed_lib_dir}}"

# Format Swift code (requires swift-format)
format:
    swift-format -i -r Sources Tests Package.swift 2>/dev/null || echo "swift-format not installed"

# Check if all dependencies are available
check-deps:
    @echo "Checking dependencies..."
    @which zig || echo "ERROR: zig not found"
    @which swift || echo "ERROR: swift not found"
    @test -d "{{ghostty_dir}}" || echo "ERROR: ghostty repo not found at {{ghostty_dir}}"
    @echo "All dependencies OK!"
