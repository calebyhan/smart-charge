#!/bin/bash
# Create a .pkg installer for BatterySmartCharge
# This installer will:
# 1. Install the app to /Applications
# 2. Install and load the privileged helper automatically

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="BatterySmartCharge"
APP_NAME="${PROJECT_NAME}.app"
HELPER_ID="com.smartcharge.powermetrics-helper"
VERSION="2.0.8"
IDENTIFIER="com.smartcharge.BatterySmartCharge.installer"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  BatterySmartCharge Installer Builder"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Find the built app (prefer Release, then Debug, exclude Index builds)
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "${APP_NAME}" -type d -path "*/Build/Products/Release/*" 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "${APP_NAME}" -type d -path "*/Build/Products/Debug/*" 2>/dev/null | head -1)
fi

if [ -z "$APP_PATH" ]; then
    echo -e "${RED}❌ Cannot find ${APP_NAME}${NC}"
    echo "Please build the app in Xcode first (Cmd+B)"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found app at: ${APP_PATH}"

# Find helper binary (it might be in a nested location due to build phase)
HELPER_PATH=$(find "${APP_PATH}" -name "PowerMetricsHelper" -type f | head -1)
if [ -z "$HELPER_PATH" ]; then
    echo -e "${RED}❌ Helper binary not found in app bundle${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found helper binary at: ${HELPER_PATH}"

# Check for battery CLI
BATTERY_CLI_SOURCE="${SCRIPT_DIR}/resources/battery"
if [ ! -f "$BATTERY_CLI_SOURCE" ]; then
    # Try to copy from system if not in resources
    if [ -f "/usr/local/bin/battery" ]; then
        mkdir -p "${SCRIPT_DIR}/resources"
        cp /usr/local/bin/battery "$BATTERY_CLI_SOURCE"
        echo -e "${YELLOW}⚠${NC} Copied battery CLI from system installation"
    else
        echo -e "${RED}❌ battery CLI not found${NC}"
        echo "Please install it first: brew install battery"
        echo "Or place it in: ${SCRIPT_DIR}/resources/battery"
        exit 1
    fi
fi

echo -e "${GREEN}✓${NC} Found battery CLI at: ${BATTERY_CLI_SOURCE}"

# Create build directory
BUILD_DIR="${SCRIPT_DIR}/build/installer"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/root/Applications"
mkdir -p "${BUILD_DIR}/root/usr/local/bin"
mkdir -p "${BUILD_DIR}/scripts"
mkdir -p "${SCRIPT_DIR}/dist"

echo -e "${GREEN}✓${NC} Created build directory"

# Copy app to payload
echo "Copying app bundle..."
cp -R "${APP_PATH}" "${BUILD_DIR}/root/Applications/"

# Copy battery CLI to payload
echo "Copying battery CLI..."
cp "${BATTERY_CLI_SOURCE}" "${BUILD_DIR}/root/usr/local/bin/battery"
chmod 755 "${BUILD_DIR}/root/usr/local/bin/battery"

# Create postinstall script that installs the helper
cat > "${BUILD_DIR}/scripts/postinstall" << 'EOF'
#!/bin/bash
# Post-installation script
# Installs the privileged helper from the app bundle

set -e

APP_PATH="/Applications/BatterySmartCharge.app"
HELPER_ID="com.smartcharge.powermetrics-helper"
HELPER_PATH="/Library/PrivilegedHelperTools/${HELPER_ID}"
LAUNCHD_PLIST="/Library/LaunchDaemons/${HELPER_ID}.plist"
BATTERY_CLI="/usr/local/bin/battery"
VISUDO_FOLDER="/private/etc/sudoers.d"
VISUDO_FILE="${VISUDO_FOLDER}/battery"

echo "=== BatterySmartCharge Installation ==="
echo ""

# Install battery CLI with proper permissions
echo "Configuring battery CLI..."
if [ -f "$BATTERY_CLI" ]; then
    chmod 755 "$BATTERY_CLI"

    # Set up passwordless sudo for battery CLI (required for SMC access)
    mkdir -p "$VISUDO_FOLDER"

    # Create sudoers file for battery CLI
    cat > "$VISUDO_FILE" << SUDOERS
# Sudo rules for battery CLI - created by BatterySmartCharge installer
%admin ALL=NOPASSWD: ${BATTERY_CLI} maintain *
%admin ALL=NOPASSWD: ${BATTERY_CLI} charging *
%admin ALL=NOPASSWD: ${BATTERY_CLI} adapter *
%admin ALL=NOPASSWD: ${BATTERY_CLI} charge *
%admin ALL=NOPASSWD: ${BATTERY_CLI} discharge *
%admin ALL=NOPASSWD: ${BATTERY_CLI} status
%admin ALL=NOPASSWD: ${BATTERY_CLI} visudo
SUDOERS

    chmod 440 "$VISUDO_FILE"
    echo "✓ Battery CLI configured with sudo permissions"
else
    echo "⚠ Warning: battery CLI not found, charging control may not work"
fi

echo ""
echo "Installing PowerMetrics helper..."

# Find helper binary in app bundle (handles nested locations)
HELPER_SOURCE=$(find "${APP_PATH}" -name "PowerMetricsHelper" -type f | head -1)
if [ -z "$HELPER_SOURCE" ]; then
    echo "Error: Helper binary not found in app bundle"
    exit 1
fi

echo "Found helper at: $HELPER_SOURCE"

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
echo "Creating launchd plist..."
cat > "$LAUNCHD_PLIST" << PLIST
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
PLIST

chmod 644 "$LAUNCHD_PLIST"
chown root:wheel "$LAUNCHD_PLIST"

# Load the helper
echo "Loading helper into launchd..."
launchctl load "$LAUNCHD_PLIST"

echo "✓ Helper installed successfully!"

exit 0
EOF

chmod +x "${BUILD_DIR}/scripts/postinstall"

echo -e "${GREEN}✓${NC} Created postinstall script"

# Build the component package
echo "Building component package..."
pkgbuild --root "${BUILD_DIR}/root" \
         --scripts "${BUILD_DIR}/scripts" \
         --identifier "${IDENTIFIER}" \
         --version "${VERSION}" \
         --install-location "/" \
         "${BUILD_DIR}/${PROJECT_NAME}-component.pkg" > /dev/null

echo -e "${GREEN}✓${NC} Built component package"

# Create distribution XML for a more polished installer
cat > "${BUILD_DIR}/distribution.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>BatterySmartCharge</title>
    <organization>com.smartcharge</organization>
    <domains enable_localSystem="true"/>
    <options customize="never" require-scripts="true" rootVolumeOnly="true" />
    <welcome file="welcome.html" mime-type="text/html" />
    <conclusion file="conclusion.html" mime-type="text/html" />
    <pkg-ref id="${IDENTIFIER}"/>
    <options customize="never" require-scripts="false"/>
    <choices-outline>
        <line choice="default">
            <line choice="${IDENTIFIER}"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="${IDENTIFIER}" visible="false">
        <pkg-ref id="${IDENTIFIER}"/>
    </choice>
    <pkg-ref id="${IDENTIFIER}" version="${VERSION}" onConclusion="none">${PROJECT_NAME}-component.pkg</pkg-ref>
</installer-gui-script>
EOF

# Create welcome message
cat > "${BUILD_DIR}/welcome.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; font-size: 13px; }
        h1 { font-size: 24px; font-weight: 300; }
        p { line-height: 1.6; }
    </style>
</head>
<body>
    <h1>Welcome to BatterySmartCharge</h1>
    <p>This installer will install BatterySmartCharge and its privileged helper tool.</p>
    <p>The helper tool requires administrator privileges to monitor power metrics. You will be prompted for your password during installation.</p>
    <p><strong>What will be installed:</strong></p>
    <ul>
        <li>BatterySmartCharge.app → /Applications/</li>
        <li>PowerMetrics Helper → /Library/PrivilegedHelperTools/</li>
        <li>battery CLI → /usr/local/bin/ (for charging control)</li>
    </ul>
</body>
</html>
EOF

# Create conclusion message
cat > "${BUILD_DIR}/conclusion.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; font-size: 13px; }
        h1 { font-size: 24px; font-weight: 300; color: #00A000; }
        p { line-height: 1.6; }
    </style>
</head>
<body>
    <h1>Installation Complete!</h1>
    <p>BatterySmartCharge has been successfully installed.</p>
    <p>You can now launch the app from your Applications folder.</p>
    <p>The PowerMetrics helper has been installed and configured to run automatically when needed.</p>
</body>
</html>
EOF

echo -e "${GREEN}✓${NC} Created installer resources"

# Build the final product archive
echo "Building final installer package..."
productbuild --distribution "${BUILD_DIR}/distribution.xml" \
             --resources "${BUILD_DIR}" \
             --package-path "${BUILD_DIR}" \
             "${SCRIPT_DIR}/dist/${PROJECT_NAME}-${VERSION}.pkg" > /dev/null

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Installer created successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Installer location:"
echo "  ${SCRIPT_DIR}/dist/${PROJECT_NAME}-${VERSION}.pkg"
echo ""
echo "File size: $(du -h "${SCRIPT_DIR}/dist/${PROJECT_NAME}-${VERSION}.pkg" | cut -f1)"
echo ""
echo "To test the installer:"
echo "  open ${SCRIPT_DIR}/dist/${PROJECT_NAME}-${VERSION}.pkg"
echo ""
