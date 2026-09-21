#!/bin/sh
# Build Sources/ into DictationGlow.app, signed with the local identity so the login-item
# registration survives the rebuild, then install it as /Applications/DictationGlow.app.
#
# The bundle is built inside the checkout and installed from there, so a worktree compiles
# without touching the app anyone is running.
#
# Installed to /Applications and never run from a temp directory: an app under /private/tmp
# gets no LaunchServices bundle registration, which SMAppService needs to resolve it.
#
# Signing: create-signing-cert.sh makes a stable self-signed identity the first time it runs.
# Without it the build falls back to ad-hoc, whose code hash changes every build, and the
# login-item registration has to be approved again each time.
#
# DICTATION_GLOW_ADHOC=1 skips the identity entirely, for a build that must not block on a
# keychain dialog.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
APP="$HERE/DictationGlow.app"
BUNDLE_ID="com.raine.dictationglow"
VERSION="0.1"

if [ -n "${DICTATION_GLOW_ADHOC:-}" ]; then
	IDENTITY="-"
else
	IDENTITY=$("$HERE/create-signing-cert.sh" 2>/dev/null || true)
	[ -n "$IDENTITY" ] || IDENTITY="-"
fi

swift build -c release --package-path "$HERE"
BINARY="$(swift build -c release --package-path "$HERE" --show-bin-path)/dictation-glow"
[ -x "$BINARY" ] || { printf 'build produced no binary at %s\n' "$BINARY" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/dictation-glow"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>dictation-glow</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
	<key>CFBundleName</key><string>DictationGlow</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$VERSION</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
PLIST
printf '</plist>\n' >> "$APP/Contents/Info.plist"

# The first build with a new identity puts up a keychain dialog asking to let codesign use the
# key. Wait for it, but not forever: an unattended build should end up ad-hoc rather than hanging.
if [ "$IDENTITY" != "-" ]; then
	printf '==> Signing as "%s" (approve the keychain dialog if one appears)\n' "$IDENTITY" >&2
	codesign --force --sign "$IDENTITY" "$APP" >/dev/null 2>&1 &
	SIGNER=$!
	WAITED=0
	while kill -0 "$SIGNER" 2>/dev/null && [ "$WAITED" -lt 120 ]; do
		sleep 1
		WAITED=$((WAITED + 1))
	done
	if kill -0 "$SIGNER" 2>/dev/null; then
		kill "$SIGNER" 2>/dev/null || true
		printf 'warning: signing timed out waiting for the keychain dialog; falling back to ad-hoc.\n' >&2
		IDENTITY="-"
	elif ! wait "$SIGNER"; then
		printf 'warning: codesign failed; falling back to ad-hoc.\n' >&2
		IDENTITY="-"
	fi
fi

if [ "$IDENTITY" = "-" ]; then
	codesign --force --sign - "$APP" >/dev/null 2>&1 || true
	printf 'note: ad-hoc signed. The login-item registration must be approved again after every build.\n' >&2
fi

printf 'built %s (signed by %s)\n' "$APP" "$IDENTITY"

[ "${1:-}" = "--no-install" ] && exit 0

rm -rf "/Applications/DictationGlow.app"
cp -R "$APP" "/Applications/DictationGlow.app"
printf 'installed /Applications/DictationGlow.app\n'
