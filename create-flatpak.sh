#!/bin/bash
# Audio Connection Manager Flatpak Builder
# This script packages all audio management tools into a Flatpak application

set -e

APP_ID="com.audioshare.Manager"
APP_NAME="AudioShare Manager"
VERSION="1.0.0"
BUILD_DIR="flatpak-build"

echo "======================================"
echo "Audio Connection Manager Flatpak Builder"
echo "======================================"
echo ""

# Check dependencies
echo "Checking dependencies..."
missing_deps=()
for cmd in flatpak flatpak-builder ostree; do
    if ! command -v "$cmd" &>/dev/null; then
        missing_deps+=("$cmd")
    fi
done

if [ ${#missing_deps[@]} -gt 0 ]; then
    echo "ERROR: Missing dependencies: ${missing_deps[*]}"
    echo "Install with: sudo apt install flatpak flatpak-builder ostree"
    exit 1
fi

# Check if Flathub is configured
echo "Checking Flatpak remotes..."
if ! flatpak remotes | grep -q "flathub"; then
    echo "Flathub remote not found. Adding Flathub..."
    flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo
    echo "Flathub added successfully."
fi

# Check and install required runtimes
echo "Checking required runtimes..."
RUNTIME="org.freedesktop.Platform"
SDK="org.freedesktop.Sdk"
VERSION_RUNTIME="23.08"

if ! flatpak list --runtime | grep -q "$RUNTIME.*$VERSION_RUNTIME"; then
    echo "Installing runtime: $RUNTIME//$VERSION_RUNTIME"
    flatpak install --user -y flathub "$RUNTIME/x86_64/$VERSION_RUNTIME" || {
        echo "ERROR: Failed to install runtime"
        echo "You may need to run: flatpak install flathub org.freedesktop.Platform//23.08"
        exit 1
    }
fi

if ! flatpak list --runtime | grep -q "$SDK.*$VERSION_RUNTIME"; then
    echo "Installing SDK: $SDK//$VERSION_RUNTIME"
    flatpak install --user -y flathub "$SDK/x86_64/$VERSION_RUNTIME" || {
        echo "ERROR: Failed to install SDK"
        echo "You may need to run: flatpak install flathub org.freedesktop.Sdk//23.08"
        exit 1
    }
fi

echo "All runtimes installed successfully."
echo ""

# Create build directory structure
echo "Creating build directory structure..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/files"
mkdir -p "$BUILD_DIR/export"

# Copy application files
echo "Copying application files..."
echo "Checking for required files..."

required_files=(
    "audioshare.sh"
    "advanced-mode.sh"
    "volume-control.sh"
    "graph.sh"
    "outputs-to-inputs.py"
    "connect-outputs-to-inputs.sh"
)

missing_files=()
for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        missing_files+=("$file")
    else
        cp "$file" "$BUILD_DIR/files/"
        chmod +x "$BUILD_DIR/files/$file"
        echo "  ✓ Copied $file"
    fi
done

if [ ${#missing_files[@]} -gt 0 ]; then
    echo ""
    echo "ERROR: Missing required files:"
    for file in "${missing_files[@]}"; do
        echo "  ✗ $file"
    done
    echo ""
    echo "Current directory: $(pwd)"
    echo "Available .sh and .py files:"
    ls -1 *.sh *.py 2>/dev/null || echo "  No .sh or .py files found"
    exit 1
fi

# Make scripts executable
chmod +x "$BUILD_DIR/files/"*.sh
chmod +x "$BUILD_DIR/files/"*.py

# Create desktop file
echo "Creating desktop entry..."
cat > "$BUILD_DIR/files/$APP_ID.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=AudioShare Manager
Comment=Manage PipeWire audio connections and routing
Exec=audioshare.sh
Icon=com.audioshare.Manager
Categories=AudioVideo;Audio;Mixer;
Terminal=false
StartupNotify=true
Keywords=audio;pipewire;routing;mixer;
EOF

# Also copy to main build dir for the manifest
cp "$BUILD_DIR/files/$APP_ID.desktop" "$BUILD_DIR/"

# Create application icon (SVG)
echo "Creating application icon..."
cat > "$BUILD_DIR/files/$APP_ID.svg" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg width="128" height="128" version="1.1" viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="grad1" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#3498db;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#2980b9;stop-opacity:1" />
    </linearGradient>
  </defs>
  
  <!-- Background circle -->
  <circle cx="64" cy="64" r="60" fill="url(#grad1)" stroke="#2c3e50" stroke-width="3"/>
  
  <!-- Audio waves -->
  <path d="M 30 64 Q 40 50, 50 64 T 70 64" stroke="#ecf0f1" stroke-width="4" fill="none" stroke-linecap="round"/>
  <path d="M 30 74 Q 40 60, 50 74 T 70 74" stroke="#ecf0f1" stroke-width="4" fill="none" stroke-linecap="round"/>
  
  <!-- Connection nodes -->
  <circle cx="30" cy="64" r="5" fill="#e74c3c"/>
  <circle cx="70" cy="64" r="5" fill="#e74c3c"/>
  <circle cx="30" cy="74" r="5" fill="#2ecc71"/>
  <circle cx="70" cy="74" r="5" fill="#2ecc71"/>
  
  <!-- Mixer icon -->
  <rect x="85" y="45" width="8" height="35" rx="4" fill="#ecf0f1"/>
  <rect x="100" y="55" width="8" height="25" rx="4" fill="#ecf0f1"/>
  <circle cx="89" cy="45" r="4" fill="#e74c3c"/>
  <circle cx="104" cy="55" r="4" fill="#f39c12"/>
</svg>
EOF

# Also copy to main build dir
cp "$BUILD_DIR/files/$APP_ID.svg" "$BUILD_DIR/"

# Create AppStream metadata
echo "Creating AppStream metadata..."
cat > "$BUILD_DIR/files/$APP_ID.appdata.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>$APP_ID</id>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>GPL-3.0+</project_license>
  <name>$APP_NAME</name>
  <summary>Manage PipeWire audio connections and routing</summary>
  
  <description>
    <p>
      AudioShare Manager is a comprehensive suite for managing PipeWire audio connections.
      It provides an intuitive interface for routing audio between applications, creating
      virtual mixers, and monitoring audio levels in real-time.
    </p>
    <p>Features:</p>
    <ul>
      <li>Connect default audio monitor to application inputs</li>
      <li>Advanced port-by-port connection management</li>
      <li>Volume control for monitor sources</li>
      <li>Real-time waveform visualization</li>
      <li>Virtual audio mixer with auto-connect functionality</li>
      <li>Feedback prevention for recording applications</li>
    </ul>
  </description>
  
  <launchable type="desktop-id">$APP_ID.desktop</launchable>
  
  <screenshots>
    <screenshot type="default">
      <caption>Main application window</caption>
    </screenshot>
  </screenshots>
  
  <url type="homepage">https://github.com/yourusername/audioshare</url>
  <url type="bugtracker">https://github.com/yourusername/audioshare/issues</url>
  
  <provides>
    <binary>audioshare.sh</binary>
  </provides>
  
  <releases>
    <release version="$VERSION" date="$(date +%Y-%m-%d)">
      <description>
        <p>Initial release</p>
      </description>
    </release>
  </releases>
  
  <content_rating type="oars-1.1" />
</component>
EOF

# Also copy to main build dir
cp "$BUILD_DIR/files/$APP_ID.appdata.xml" "$BUILD_DIR/"

# Create Flatpak manifest (simplified - uses host system tools)
echo "Creating Flatpak manifest..."
cat > "$BUILD_DIR/$APP_ID.yml" << 'EOF'
app-id: com.audioshare.Manager
runtime: org.freedesktop.Platform
runtime-version: '23.08'
sdk: org.freedesktop.Sdk
command: audioshare.sh

finish-args:
  # X11 and Wayland access
  - --socket=x11
  - --socket=wayland
  - --share=ipc
  
  # PulseAudio/PipeWire access - use host system
  - --socket=pulseaudio
  - --filesystem=xdg-run/pipewire-0
  
  # System DBus for audio
  - --system-talk-name=org.freedesktop.RealtimeKit1
  
  # Session DBus - use talk-name instead of session-talk-name
  - --talk-name=org.pulseaudio.Server
  - --talk-name=org.freedesktop.portal.Desktop
  
  # Access host commands via flatpak-spawn
  - --talk-name=org.freedesktop.Flatpak
  
  # Allow spawning host commands
  - --allow=devel

modules:
  # Python GTK bindings
  - name: pygobject
    buildsystem: meson
    sources:
      - type: archive
        url: https://download.gnome.org/sources/pygobject/3.46/pygobject-3.46.0.tar.xz
        sha256: 481437b05af0a66b7c366ea052710eb3aacbb979d22d30b797f7ec29347ab1e6
  # jq for JSON processing
  - name: jq
    buildsystem: autotools
    sources:
      - type: archive
        url: https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-1.7.1.tar.gz
        sha256: 478c9ca129fd2e3443fe27314b455e211e0d8c60bc8ff7df703873deeee580c2
  
  # Main application
  - name: audioshare
    buildsystem: simple
    build-commands:
      # Modify scripts to use flatpak-spawn for host commands
      - |
        for script in *.sh *.py; do
          if [ -f "$script" ]; then
            sed -i "s|subprocess\.run(\[['\"]\?pactl['\"]\?|subprocess.run(['flatpak-spawn', '--host', 'pactl'|g" "$script"
            sed -i "s|subprocess\.run(\[['\"]\?pw-link['\"]\?|subprocess.run(['flatpak-spawn', '--host', 'pw-link'|g" "$script"
            sed -i "s|subprocess\.run(\[['\"]\?pw-dump['\"]\?|subprocess.run(['flatpak-spawn', '--host', 'pw-dump'|g" "$script"
            sed -i "s|subprocess\.run(\[['\"]\?parec['\"]\?|subprocess.run(['flatpak-spawn', '--host', 'parec'|g" "$script"
            sed -i "s|subprocess\.run(\[['\"]\?which['\"]\?|subprocess.run(['flatpak-spawn', '--host', 'which'|g" "$script"
          fi
        done
      
      # Modify bash script specifically
      - |
        if [ -f "connect-outputs-to-inputs.sh" ]; then
          sed -i 's/pactl /flatpak-spawn --host pactl /g' connect-outputs-to-inputs.sh
          sed -i 's/pw-link /flatpak-spawn --host pw-link /g' connect-outputs-to-inputs.sh
          sed -i 's/pw-dump /flatpak-spawn --host pw-dump /g' connect-outputs-to-inputs.sh
          sed -i 's/jq /flatpak-spawn --host jq /g' connect-outputs-to-inputs.sh
          # Fix command invocations in backticks and $()
          sed -i 's/\$(pactl /$(flatpak-spawn --host pactl /g' connect-outputs-to-inputs.sh
          sed -i 's/\$(pw-link /$(flatpak-spawn --host pw-link /g' connect-outputs-to-inputs.sh
          sed -i 's/\$(pw-dump /$(flatpak-spawn --host pw-dump /g' connect-outputs-to-inputs.sh
        fi
      
      # Install scripts (only if they exist)
      - |
        echo "Current directory: $(pwd)"
        echo "Available files:"
        ls -la
        for script in audioshare.sh advanced-mode.sh volume-control.sh graph.sh outputs-to-inputs.py connect-outputs-to-inputs.sh; do
          if [ -f "$script" ]; then
            install -Dm755 "$script" "/app/bin/$script"
            echo "Installed: $script"
          else
            echo "Warning: $script not found, skipping"
          fi
        done
      
      # Install desktop file and icon
      - |
        if [ -f "com.audioshare.Manager.desktop" ]; then
          install -Dm644 com.audioshare.Manager.desktop /app/share/applications/com.audioshare.Manager.desktop
        fi
      - |
        if [ -f "com.audioshare.Manager.svg" ]; then
          install -Dm644 com.audioshare.Manager.svg /app/share/icons/hicolor/scalable/apps/com.audioshare.Manager.svg
        fi
      - |
        if [ -f "com.audioshare.Manager.appdata.xml" ]; then
          install -Dm644 com.audioshare.Manager.appdata.xml /app/share/metainfo/com.audioshare.Manager.appdata.xml
        fi
    
    sources:
      - type: dir
        path: ../files
EOF

# Build the Flatpak
echo ""
echo "Building Flatpak package..."
echo "This may take a while on first run..."
echo ""

cd "$BUILD_DIR"

# Initialize local repo if needed
if [ ! -d "repo" ]; then
    ostree init --mode=archive-z2 --repo=repo
fi

# Build the application
flatpak-builder --force-clean --repo=repo build-dir "$APP_ID.yml"

if [ $? -eq 0 ]; then
    echo ""
    echo "======================================"
    echo "Build successful!"
    echo "======================================"
    echo ""
    echo "To install locally, run:"
    echo "  flatpak --user remote-add --no-gpg-verify audioshare-repo $PWD/repo"
    echo "  flatpak --user install audioshare-repo $APP_ID"
    echo ""
    echo "To run the application:"
    echo "  flatpak run $APP_ID"
    echo ""
    echo "To create a bundle for distribution:"
    echo "  flatpak build-bundle repo $APP_ID.flatpak $APP_ID"
    echo ""
    echo "To uninstall:"
    echo "  flatpak uninstall $APP_ID"
    echo ""
    echo "NOTE: This Flatpak uses your system's PipeWire installation."
    echo "Make sure pipewire-utils is installed on the host system:"
    echo "  sudo apt install pipewire pipewire-pulse pipewire-alsa wireplumber"
    echo ""
else
    echo ""
    echo "======================================"
    echo "Build failed!"
    echo "======================================"
    exit 1
fi