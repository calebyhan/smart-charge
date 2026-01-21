#!/bin/bash

# Installation script for PowerMetrics helper
# This needs to be run once with sudo to install the privileged helper

set -e

HELPER_ID="com.smartcharge.powermetrics-helper"
HELPER_PLIST="${HELPER_ID}.plist"
HELPER_PATH="/Library/PrivilegedHelperTools/${HELPER_ID}"
LAUNCHD_PLIST="/Library/LaunchDaemons/${HELPER_PLIST}"

echo "=== BatterySmartCharge Helper Installer ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run with sudo"
    echo ""
    echo "Usage: sudo ./install_helper.sh"
    exit 1
fi

# Find the app bundle
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "BatterySmartCharge.app" -type d 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    # Try looking in common locations
    if [ -d "./BatterySmartCharge.app" ]; then
        APP_PATH="./BatterySmartCharge.app"
    elif [ -d "/Applications/BatterySmartCharge.app" ]; then
        APP_PATH="/Applications/BatterySmartCharge.app"
    else
        echo "❌ Cannot find BatterySmartCharge.app"
        echo "Please build the app first in Xcode, or run this script from the directory containing the .app bundle"
        exit 1
    fi
fi

# Find helper binary (handles nested locations)
HELPER_SOURCE=$(find "${APP_PATH}" -name "PowerMetricsHelper" -type f | head -1)

if [ -z "$HELPER_SOURCE" ]; then
    echo "❌ Helper binary not found in app bundle"
    echo "Please rebuild the app in Xcode"
    exit 1
fi

echo "Found app at: $APP_PATH"
echo "Found helper at: $HELPER_SOURCE"
echo ""

# Unload existing helper if it's running
if launchctl list | grep -q "$HELPER_ID"; then
    echo "Unloading existing helper..."
    launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true
fi

# Copy the helper
echo "Installing helper to: $HELPER_PATH"
cp "$HELPER_SOURCE" "$HELPER_PATH"
chmod 544 "$HELPER_PATH"
chown root:wheel "$HELPER_PATH"

# Create launchd plist
echo "Creating launchd plist at: $LAUNCHD_PLIST"
cat > "$LAUNCHD_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${HELPER_ID}</string>
    <key>MachServices</key>
    <dict>
        <key>${HELPER_ID}</key>
        <true/>
    </dict>
    <key>ProgramArguments</key>
    <array>
        <string>${HELPER_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF

chmod 644 "$LAUNCHD_PLIST"
chown root:wheel "$LAUNCHD_PLIST"

# Load the helper
echo "Loading helper into launchd..."
launchctl load "$LAUNCHD_PLIST"

echo ""
echo "✅ Helper installed successfully!"
echo ""
echo "The helper will start automatically when the app needs it."
echo "You can verify the installation with:"
echo "  ls -la $HELPER_PATH"
echo "  sudo launchctl list | grep $HELPER_ID"
echo ""
