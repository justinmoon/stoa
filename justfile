# Stoa - Tiling Window Manager for AI-driven Development

default:
    just --list

# Path to the ghostty repo
ghostty_dir := env_var_or_default("GHOSTTY_DIR", home_directory() / "code" / "ghostty")

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

# Build the Stoa app
build: copy-libghostty
    swift build

# Build for release
build-release: copy-libghostty
    swift build -c release

# Run Demo 1: Single Terminal Window
demo-1: copy-libghostty
    swift run stoa-demo-1

# Run tests
test:
    swift test

# Clean build artifacts
clean:
    swift package clean
    rm -rf .build
    rm -rf Libraries/GhosttyKit.xcframework
    rm -rf Libraries/include

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
