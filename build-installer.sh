#!/bin/bash

set -e

# Configuration
PROJECT_NAME="claude-code-router"
NODE_VERSION="20.16.0"
ARCH="x64"

echo "Building ${PROJECT_NAME} standalone installer..."

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
    echo "Error: package.json not found. Please run this script from the project root."
    exit 1
fi

# Get version from package.json
VERSION=$(node -p "require('./package.json').version")
echo "Building version: $VERSION"

# Detect Ubuntu version
UBUNTU_VERSION=""
if [ -f "/etc/os-release" ]; then
    UBUNTU_VERSION=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    echo "Detected Ubuntu version: $UBUNTU_VERSION"
else
    echo "Warning: Could not detect Ubuntu version"
fi

# Clean up previous builds
echo "Cleaning previous builds..."
rm -rf dist/ build/ installer-temp/ claude-router-installer*.tar.gz

# Install dependencies and build the project
echo "Installing dependencies..."
npm install

echo "Building project..."
npm run build

# Create installer temporary directory
echo "Creating installer structure..."
mkdir -p installer-temp

# Download Node.js runtime
NODE_PACKAGE="node-v${NODE_VERSION}-linux-${ARCH}"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_PACKAGE}.tar.xz"

echo "Downloading Node.js runtime v${NODE_VERSION}..."
cd installer-temp

if ! wget -q "${NODE_URL}"; then
    echo "Failed to download Node.js runtime"
    exit 1
fi

echo "Extracting Node.js runtime..."
tar -xf "${NODE_PACKAGE}.tar.xz"
mv "${NODE_PACKAGE}" nodejs
rm "${NODE_PACKAGE}.tar.xz"

# Copy built application
echo "Copying application files..."
mkdir -p app
cp -r ../dist/* ./app/
cp ../README.md ./
cp ../LICENSE ./

# Copy config example if it exists
if [ -f "../config.example.json" ]; then
    cp ../config.example.json ./
fi

# Create launcher script
echo "Creating launcher script..."
cat > ${PROJECT_NAME} << 'EOF'
#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set NODE_PATH to use bundled Node.js
export NODE_PATH="${SCRIPT_DIR}/nodejs/lib/node_modules"
export PATH="${SCRIPT_DIR}/nodejs/bin:${PATH}"

# Run the application
exec "${SCRIPT_DIR}/nodejs/bin/node" "${SCRIPT_DIR}/app/cli.js" "$@"
EOF

chmod +x ${PROJECT_NAME}

# Create installation script
echo "Creating installation script..."
cat > install.sh << 'EOF'
#!/bin/bash

set -e

INSTALL_DIR="/opt/claude-code-router"
BIN_DIR="/usr/local/bin"
SERVICE_NAME="claude-code-router"

echo "Installing Claude Code Router..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)"
    exit 1
fi

# Create installation directory
mkdir -p "${INSTALL_DIR}"

# Copy files
echo "Copying files to ${INSTALL_DIR}..."
cp -r * "${INSTALL_DIR}/"

# Create symlink in PATH
echo "Creating symlink in ${BIN_DIR}..."
ln -sf "${INSTALL_DIR}/claude-code-router" "${BIN_DIR}/ccr"

# Make executable
chmod +x "${INSTALL_DIR}/claude-code-router"
chmod +x "${INSTALL_DIR}/nodejs/bin/node"

# Create systemd service file
echo "Creating systemd service..."
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOSERVICE
[Unit]
Description=Claude Code Router
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/claude-code-router
Restart=always
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOSERVICE

# Reload systemd
systemctl daemon-reload

echo "Installation completed!"
echo ""
echo "Usage:"
echo "  Start service: sudo systemctl start ${SERVICE_NAME}"
echo "  Enable on boot: sudo systemctl enable ${SERVICE_NAME}"
echo "  Check status: sudo systemctl status ${SERVICE_NAME}"
echo "  View logs: sudo journalctl -u ${SERVICE_NAME} -f"
echo ""
echo "Command line usage: ccr --help"
echo ""
echo "Configuration file: ${INSTALL_DIR}/config.example.json"
echo "Copy it to config.json and modify as needed."
EOF

chmod +x install.sh

# Create uninstallation script
echo "Creating uninstallation script..."
cat > uninstall.sh << 'EOF'
#!/bin/bash

set -e

INSTALL_DIR="/opt/claude-code-router"
BIN_DIR="/usr/local/bin"
SERVICE_NAME="claude-code-router"

echo "Uninstalling Claude Code Router..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)"
    exit 1
fi

# Stop and disable service
if systemctl is-active --quiet ${SERVICE_NAME}; then
    echo "Stopping service..."
    systemctl stop ${SERVICE_NAME}
fi

if systemctl is-enabled --quiet ${SERVICE_NAME}; then
    echo "Disabling service..."
    systemctl disable ${SERVICE_NAME}
fi

# Remove service file
if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    echo "Removing service file..."
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
fi

# Remove symlink
if [ -L "${BIN_DIR}/ccr" ]; then
    echo "Removing symlink..."
    rm -f "${BIN_DIR}/ccr"
fi

# Remove installation directory
if [ -d "${INSTALL_DIR}" ]; then
    echo "Removing installation directory..."
    rm -rf "${INSTALL_DIR}"
fi

echo "Uninstallation completed!"
EOF

chmod +x uninstall.sh

# Create README for the installer
echo "Creating installer README..."
cat > README_INSTALLER.md << 'EOF'
# Claude Code Router Standalone Installer

This package contains a standalone installation of Claude Code Router with bundled Node.js runtime for offline environments.

## Installation

1. Extract the installer package:
   ```bash
   tar -xzf claude-router-installer-*.tar.gz
   cd claude-router-installer/
   ```

2. Run the installation script as root:
   ```bash
   sudo ./install.sh
   ```

## Usage

### Command Line
After installation, you can use the `ccr` command:
```bash
ccr --help
```

### As a Service
The installer creates a systemd service that you can manage:

```bash
# Start the service
sudo systemctl start claude-code-router

# Enable auto-start on boot
sudo systemctl enable claude-code-router

# Check service status
sudo systemctl status claude-code-router

# View logs
sudo journalctl -u claude-code-router -f
```

## Configuration

Copy the example configuration file and modify it:
```bash
cd /opt/claude-code-router
sudo cp config.example.json config.json
sudo nano config.json
```

## Uninstallation

To completely remove Claude Code Router:
```bash
cd /opt/claude-code-router
sudo ./uninstall.sh
```

## System Requirements

- Ubuntu 22.04 LTS or Ubuntu 24.04 LTS
- 64-bit architecture (x86_64)
- At least 100MB free disk space
- Root privileges for installation

## Included Components

- Node.js runtime v20.16.0
- Claude Code Router application
- Systemd service configuration
- Installation and uninstallation scripts

EOF

# Go back to project root
cd ..

# Create the final installer package
echo "Creating installer package..."
ARCHIVE_NAME="claude-router-installer"
if [ -n "$UBUNTU_VERSION" ]; then
    ARCHIVE_NAME="claude-router-installer-linux-x64-ubuntu${UBUNTU_VERSION}"
fi

tar -czf "${ARCHIVE_NAME}.tar.gz" -C installer-temp .

# Cleanup
rm -rf installer-temp

echo ""
echo "Standalone installer created: ${ARCHIVE_NAME}.tar.gz"
echo "Ubuntu version: ${UBUNTU_VERSION}"
echo "Node.js version: ${NODE_VERSION}"
echo "Architecture: ${ARCH}"
echo ""
echo "The installer includes:"
echo "  - Bundled Node.js runtime"
echo "  - Application files"
echo "  - Installation script (install.sh)"
echo "  - Uninstallation script (uninstall.sh)"
echo "  - Systemd service configuration"
echo "  - Documentation"

# Show archive size
if [ -f "${ARCHIVE_NAME}.tar.gz" ]; then
    echo ""
    echo "Archive size: $(du -h "${ARCHIVE_NAME}.tar.gz" | cut -f1)"
fi
