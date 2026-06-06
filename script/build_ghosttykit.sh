#!/usr/bin/env bash
# Build GhosttyKit.xcframework from the pinned Ghostty source commit.
# Run this once after cloning; re-run after bumping PINNED_COMMIT.
#
# Workaround: Ghostty v1.3.0's xcframework build step (via macOS libtool) silently
# drops the Zig compilation unit (libghostty_zcu.o) due to a misalignment warning,
# leaving the xcframework without the ghostty_app_* API symbols. We detect this and
# manually combine the correct per-arch caches into a self-contained static library.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$REPO_ROOT/Vendor"
PINNED_COMMIT="$(head -1 "$VENDOR_DIR/PINNED_COMMIT")"
GHOSTTY_CLONE="/tmp/ghostty-build-$PINNED_COMMIT"

# Prefer brew zig@0.15; fall back to PATH zig (version check will catch mismatches)
if [ -x "/opt/homebrew/opt/zig@0.15/bin/zig" ]; then
    ZIG="/opt/homebrew/opt/zig@0.15/bin/zig"
elif command -v zig &>/dev/null; then
    ZIG="zig"
else
    echo "error: zig not found — run: brew install zig@0.15"
    exit 1
fi

echo "Using Zig: $($ZIG version) at $ZIG"

# Clone if needed
if [ ! -d "$GHOSTTY_CLONE" ]; then
    echo "Cloning ghostty at $PINNED_COMMIT …"
    git clone --depth 1 "https://github.com/ghostty-org/ghostty.git" "$GHOSTTY_CLONE"
    git -C "$GHOSTTY_CLONE" fetch --depth 1 origin "$PINNED_COMMIT"
    git -C "$GHOSTTY_CLONE" checkout "$PINNED_COMMIT"
fi

# Build the native (arm64) xcframework — universal fails on Apple Silicon due to the
# libtool alignment bug; native-only is sufficient for development on M-series Macs.
echo "Building GhosttyKit (native arm64, this takes several minutes) …"
(cd "$GHOSTTY_CLONE" && "$ZIG" build \
    -Demit-xcframework=true \
    -Dxcframework-target=native \
    -Demit-macos-app=false \
    -Doptimize=ReleaseFast)

# --- Post-build: assemble the correct static library ---
# The native xcframework's libghostty-fat.a is missing the Zig core because macOS
# libtool drops misaligned 64-bit Mach-O members. We collect all macOS arm64 cache
# archives and manually combine them via `ar`.

INCOMPLETE_LIB="$GHOSTTY_CLONE/macos/GhosttyKit.xcframework/macos-arm64/libghostty-fat.a"
CACHE="$GHOSTTY_CLONE/.zig-cache/o"

echo "Locating macOS arm64 Zig core (contains ghostty_app_* API) …"
ZIG_CORE=""
for f in "$CACHE"/*/libghostty.a; do
    nm "$f" 2>/dev/null | grep -q "_ghostty_app_free" || continue
    lipo -info "$f" 2>&1 | grep -q "architecture: arm64" || continue
    first=$(ar -t "$f" 2>/dev/null | head -2 | tail -1)
    [ -n "$first" ] || continue
    ar -p "$f" "$first" > /tmp/_ghostty_plat_check.o 2>/dev/null
    plat=$(otool -l /tmp/_ghostty_plat_check.o 2>/dev/null | grep -A4 "LC_BUILD_VERSION" | awk '/platform/{print $2; exit}')
    [ "$plat" = "1" ] || continue
    ZIG_CORE="$f"
    break
done
[ -n "$ZIG_CORE" ] || { echo "error: could not find macOS arm64 Zig core in cache"; exit 1; }
echo "  Found: $(ls -la "$ZIG_CORE" | awk '{print $5}')B"

echo "Locating macOS arm64 C dependency archives …"
DEP_LIBS=()
for libname in libbreakpad libdcimgui libfreetype libglslang libhighway libintl \
               libmacos liboniguruma libpng libsentry libsimdutf libspirv_cross \
               libutfcpp libz; do
    found=""
    for f in $(find "$CACHE" -name "${libname}.a" 2>/dev/null); do
        lipo -info "$f" 2>&1 | grep -q "architecture: arm64" || continue
        first=$(ar -t "$f" 2>/dev/null | head -2 | tail -1)
        [ -n "$first" ] || continue
        ar -p "$f" "$first" > /tmp/_ghostty_plat_check.o 2>/dev/null
        plat=$(otool -l /tmp/_ghostty_plat_check.o 2>/dev/null | grep -A4 "LC_BUILD_VERSION" | awk '/platform/{print $2; exit}')
        [ "$plat" = "1" ] || continue
        found="$f"
        break
    done
    if [ -n "$found" ]; then
        DEP_LIBS+=("$found")
        echo "  $libname: $(ls -la "$found" | awk '{print $5}')B"
    else
        echo "  warning: $libname not found, skipping"
    fi
done

echo "Combining all archives into a self-contained libghostty-fat.a …"
TMPDIR=$(mktemp -d)
all_libs=("$INCOMPLETE_LIB" "$ZIG_CORE" "${DEP_LIBS[@]}")
i=0
for lib in "${all_libs[@]}"; do
    subdir="$TMPDIR/lib_$i"
    mkdir -p "$subdir"
    (cd "$subdir" && ar -x "$lib" 2>/dev/null; chmod 644 "$subdir"/*.o 2>/dev/null || true)
    i=$((i+1))
done
find "$TMPDIR" -name "*.o" | sort | xargs ar -crs /tmp/_ghostty_combined_arm64.a 2>/dev/null
rm -rf "$TMPDIR"

# Verify the combined library has the API symbols
api_count=$(nm /tmp/_ghostty_combined_arm64.a 2>/dev/null | grep -c "_ghostty_app_free" || true)
[ "$api_count" -gt 0 ] || { echo "error: combined library is missing ghostty_app_* symbols"; exit 1; }
echo "  Combined: $(ls -la /tmp/_ghostty_combined_arm64.a | awk '{print $5}')B — ghostty_app_* symbols present"

# Install into Vendor/
echo "Installing to $VENDOR_DIR/GhosttyKit.xcframework …"
rm -rf "$VENDOR_DIR/GhosttyKit.xcframework"
mkdir -p "$VENDOR_DIR/GhosttyKit.xcframework/macos-arm64/Headers"
cp /tmp/_ghostty_combined_arm64.a "$VENDOR_DIR/GhosttyKit.xcframework/macos-arm64/libghostty-fat.a"
cp -r "$GHOSTTY_CLONE/include/." "$VENDOR_DIR/GhosttyKit.xcframework/macos-arm64/Headers/"

cat > "$VENDOR_DIR/GhosttyKit.xcframework/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AvailableLibraries</key>
    <array>
        <dict>
            <key>BinaryPath</key>
            <string>libghostty-fat.a</string>
            <key>HeadersPath</key>
            <string>Headers</string>
            <key>LibraryIdentifier</key>
            <string>macos-arm64</string>
            <key>LibraryPath</key>
            <string>libghostty-fat.a</string>
            <key>SupportedArchitectures</key>
            <array>
                <string>arm64</string>
            </array>
            <key>SupportedPlatform</key>
            <string>macos</string>
        </dict>
    </array>
    <key>CFBundlePackageType</key>
    <string>XFWK</string>
    <key>XCFrameworkFormatVersion</key>
    <string>1.0</string>
</dict>
</plist>
PLIST

rm -f /tmp/_ghostty_combined_arm64.a /tmp/_ghostty_plat_check.o
echo "Done."
