# Resources

This directory contains external dependencies bundled with the installer.

## battery CLI

The `battery` file is the [battery CLI tool](https://github.com/actuallymentor/battery) by actuallymentor.

**Version**: 1.3.2 (or later)

**Purpose**: Controls macOS battery charging behavior via SMC

**Installation**:
- The `create_installer.sh` script will automatically copy this from your system installation (`/usr/local/bin/battery`)
- If not found, you'll need to install it first: `brew install battery`
- The installer (.pkg) bundles this and installs it to `/usr/local/bin/battery`

**License**: MIT (see https://github.com/actuallymentor/battery)

## Usage

When building the installer, the script will:
1. Check for `resources/battery`
2. If not found, copy from `/usr/local/bin/battery`
3. Bundle it in the .pkg installer
4. Install it with proper sudo permissions
