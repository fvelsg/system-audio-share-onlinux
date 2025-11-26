#!/bin/bash
###############################################################################
# Audio Connection Manager - Flatpak Build Script
# This script automates the complete process of building a Flatpak package
###############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_ID="com.audioshare.AudioConnectionManager"
APP_NAME="Audio Connection Manager"
VERSION="1.0.0"
BUILD_DIR="flatpak-build"
REPO_DIR="flatpak-repo"

# Print colored message
print_msg() {
    echo -e "${GREEN}==>${NC} $1"
}

print_error() {
    echo -e "${RED}ERROR:${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

print_step() {
    echo -e "\n${BLUE}===== $1 =====${NC}\n"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Step 1: Check dependencies
check_dependencies() {
    print_step "Step 1: Checking Dependencies"
    
    local missing_deps=()
    
    if ! command_exists flatpak; then
        missing_deps+=("flatpak")
    fi
    
    if ! command_exists flatpak-builder; then
        missing_deps+=("flatpak-builder")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        echo "Install with: sudo apt install ${missing_deps[*]}"
        exit 1
    fi
    
    print_msg "All required tools are installed"
}

# Step 2: Check for GNOME runtime
check_runtime() {
    print_step "Step 2: Checking GNOME Runtime"
    
    if ! flatpak list --runtime | grep -q "org.gnome.Platform.*46"; then
        print_warning "GNOME Platform 46 not found"
        echo "Installing GNOME Platform and SDK..."
        flatpak install -y flathub org.gnome.Platform//46 org.gnome.Sdk//46
    else
        print_msg "GNOME Platform 46 is installed"
    fi
}

# Step 3: Create project structure
create_structure() {
    print_step "Step 3: Creating Project Structure"
    
    # Create main directory
    mkdir -p "$BUILD_DIR"/{src,files}
    
    print_msg "Created directory: $BUILD_DIR"
    
    # Check if source scripts exist in current directory
    local scripts=("audioshare.sh" "advanced-mode.sh" "volume-control.sh" "graph.sh")
    local missing_scripts=()
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            cp "$script" "$BUILD_DIR/src/"
            chmod +x "$BUILD_DIR/src/$script"
            print_msg "Copied: $script"
        else
            missing_scripts+=("$script")
        fi
    done
    
    if [ ${#missing_scripts[@]} -ne 0 ]; then
        print_warning "Missing scripts: ${missing_scripts[*]}"
        print_msg "Please place these scripts in the current directory"
    fi
}

# Step 4: Create desktop file
create_desktop_file() {
    print_step "Step 4: Creating Desktop Entry"
    
    cat > "$BUILD_DIR/files/$APP_ID.desktop" << EOF
[Desktop Entry]
Name=$APP_NAME
Comment=Manage PipeWire audio connections
Exec=audioshare.sh
Icon=$APP_ID
Terminal=false
Type=Application
Categories=AudioVideo;Audio;Utility;GTK;
Keywords=audio;pipewire;pulseaudio;connection;monitor;share;
StartupNotify=true
EOF
    
    print_msg "Created desktop file"
}

# Step 5: Create AppData XML
create_appdata() {
    print_step "Step 5: Creating AppData Metadata"
    
    cat > "$BUILD_DIR/files/$APP_ID.appdata.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>$APP_ID</id>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>GPL-3.0-or-later</project_license>
  <name>$APP_NAME</name>
  <summary>Manage PipeWire audio connections with a GTK interface</summary>
  
  <description>
    <p>
      Audio Connection Manager is a graphical tool for managing PipeWire audio connections.
      It allows you to easily connect your default audio monitor to application inputs,
      control volume, and visualize audio waveforms in real-time.
    </p>
    <p>Features:</p>
    <ul>
      <li>Connect/disconnect monitor to all inputs automatically</li>
      <li>Advanced mode for selective port connections</li>
      <li>Volume control for monitor source</li>
      <li>Real-time audio waveform visualization</li>
      <li>Easy-to-use GTK3 interface</li>
    </ul>
  </description>
  
  <launchable type="desktop-id">$APP_ID.desktop</launchable>
  
  <screenshots>
    <screenshot type="default">
      <caption>Main window</caption>
    </screenshot>
  </screenshots>
  
  <url type="homepage">https://github.com/yourusername/audioshare</url>
  <url type="bugtracker">https://github.com/yourusername/audioshare/issues</url>
  
  <content_rating type="oars-1.1" />
  
  <releases>
    <release version="$VERSION" date="$(date +%Y-%m-%d)">
      <description>
        <p>Initial Flatpak release</p>
        <ul>
          <li>Audio connection management</li>
          <li>Volume control</li>
          <li>Waveform visualization</li>
          <li>Advanced port selection</li>
        </ul>
      </description>
    </release>
  </releases>
</component>
EOF
    
    print_msg "Created AppData file"
}

# Step 6: Create application icon
create_icon() {
    print_step "Step 6: Creating Application Icon"
    
    # Check if icon.png exists
    if [ -f "icon.png" ]; then
        cp icon.png "$BUILD_DIR/files/$APP_ID.png"
        print_msg "Using existing icon.png"
        return 0
    fi
    
    print_warning "No icon.png found, attempting to create a default icon"
    
    # Try to create a simple icon with ImageMagick
    if command_exists convert; then
        convert -size 256x256 xc:transparent \
            -fill "#4A90E2" -draw "circle 128,128 128,228" \
            -fill white -pointsize 100 -gravity center \
            -annotate +0+0 "♪" \
            "$BUILD_DIR/files/$APP_ID.png" 2>/dev/null && {
                print_msg "Created default icon with ImageMagick"
                return 0
            }
    fi
    
    # If ImageMagick failed or isn't available, create a minimal SVG and convert it
    if command_exists rsvg-convert; then
        cat > "$BUILD_DIR/files/temp-icon.svg" << 'SVGEOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg width="256" height="256" xmlns="http://www.w3.org/2000/svg">
  <circle cx="128" cy="128" r="100" fill="#4A90E2"/>
  <text x="128" y="165" font-size="100" text-anchor="middle" fill="white">♪</text>
</svg>
SVGEOF
        rsvg-convert -w 256 -h 256 "$BUILD_DIR/files/temp-icon.svg" -o "$BUILD_DIR/files/$APP_ID.png" && {
            rm "$BUILD_DIR/files/temp-icon.svg"
            print_msg "Created default icon with rsvg-convert"
            return 0
        }
    fi
    
    print_error "Could not create icon automatically"
    print_msg "Please create a 256x256 PNG icon named 'icon.png' and rebuild"
    exit 1
}

# Step 7: Create Flatpak manifest
create_manifest() {
    print_step "Step 7: Creating Flatpak Manifest"
    
    cat > "$BUILD_DIR/$APP_ID.yaml" << 'EOF'
app-id: com.audioshare.AudioConnectionManager
runtime: org.gnome.Platform
runtime-version: '46'
sdk: org.gnome.Sdk
command: audioshare.sh

finish-args:
  # GUI access
  - --share=ipc
  - --socket=x11
  - --socket=wayland
  
  # Audio access (critical for functionality)
  - --socket=pulseaudio
  - --filesystem=xdg-run/pipewire-0:rw
  
  # Device access
  - --device=all
  
  # System services for audio
  - --system-talk-name=org.freedesktop.RealtimeKit1
  
  # Host filesystem access (needed for PipeWire tools)
  - --filesystem=/usr/bin:ro
  - --filesystem=/run:ro
  - --filesystem=host-os:ro
  - --filesystem=host-etc:ro

modules:
  # Python 3 and GTK bindings (using runtime's Python3-gobject)
  # Note: PyGObject is already included in org.gnome.Platform runtime
  # We just need to ensure our scripts can find it

  # Wrapper script to find host commands
  - name: host-command-wrapper
    buildsystem: simple
    build-commands:
      - mkdir -p /app/bin
      - |
        cat > /app/bin/find-host-command << 'WRAPPER_EOF'
        #!/bin/bash
        # Wrapper to find commands in host or flatpak
        CMD="$1"
        
        # Try various locations
        for path in "/usr/bin/$CMD" "/bin/$CMD" "/app/bin/$CMD" "/var/run/host/usr/bin/$CMD" "/run/host/usr/bin/$CMD"; do
          if [ -x "$path" ]; then
            echo "$path"
            exit 0
          fi
        done
        
        # Fallback to PATH
        which "$CMD" 2>/dev/null || echo "$CMD"
        WRAPPER_EOF
      - chmod +x /app/bin/find-host-command
    sources: []

  # Main application
  - name: audioshare
    buildsystem: simple
    build-commands:
      # Install Python scripts
      - install -Dm755 audioshare.sh /app/bin/audioshare.sh
      - install -Dm755 advanced-mode.sh /app/bin/advanced-mode.sh
      - install -Dm755 volume-control.sh /app/bin/volume-control.sh
      - install -Dm755 graph.sh /app/bin/graph.sh
      
      # Install desktop file
      - install -Dm644 com.audioshare.AudioConnectionManager.desktop /app/share/applications/com.audioshare.AudioConnectionManager.desktop
      
      # Install appdata
      - install -Dm644 com.audioshare.AudioConnectionManager.appdata.xml /app/share/metainfo/com.audioshare.AudioConnectionManager.appdata.xml
      
      # Install icon (required)
      - install -Dm644 com.audioshare.AudioConnectionManager.png /app/share/icons/hicolor/256x256/apps/com.audioshare.AudioConnectionManager.png
    
    sources:
      - type: file
        path: src/audioshare.sh
      - type: file
        path: src/advanced-mode.sh
      - type: file
        path: src/volume-control.sh
      - type: file
        path: src/graph.sh
      - type: file
        path: files/com.audioshare.AudioConnectionManager.desktop
      - type: file
        path: files/com.audioshare.AudioConnectionManager.appdata.xml
      - type: file
        path: files/com.audioshare.AudioConnectionManager.png
EOF
    
    print_msg "Created Flatpak manifest"
}

# Step 8: Modify scripts for Flatpak compatibility
modify_scripts() {
    print_step "Step 8: Modifying Scripts for Flatpak"
    
    # Create a wrapper that checks both flatpak and host paths
    local scripts=("audioshare.sh" "advanced-mode.sh" "volume-control.sh" "graph.sh")
    
    for script in "${scripts[@]}"; do
        if [ -f "$BUILD_DIR/src/$script" ]; then
            # Add shebang if not present
            if ! head -n1 "$BUILD_DIR/src/$script" | grep -q "^#!"; then
                print_warning "$script missing shebang, adding #!/usr/bin/env python3"
                echo -e "#!/usr/bin/env python3\n$(cat "$BUILD_DIR/src/$script")" > "$BUILD_DIR/src/$script"
            fi
            
            # Add app ID setup for GTK applications
            if grep -q "class.*Gtk.Window" "$BUILD_DIR/src/$script"; then
                print_msg "Patching $script for proper app ID and icon..."
                
                # For GTK3, we need to set the application name properly
                # Find the line with "if __name__" and add GLib setup before it
                sed -i '/if __name__/i\
# Set application properties for proper dock icon\
import gi\
gi.require_version('"'"'Gtk'"'"', '"'"'3.0'"'"')\
from gi.repository import GLib\
GLib.set_prgname('"'"'com.audioshare.AudioConnectionManager'"'"')\
GLib.set_application_name('"'"'Audio Connection Manager'"'"')\
' "$BUILD_DIR/src/$script"
                
                # Also set icon name in window init (after set_border_width or similar initialization)
                # Look for common initialization patterns and add icon setting
                if grep -q "self.set_border_width" "$BUILD_DIR/src/$script"; then
                    sed -i '/self.set_border_width/a\        self.set_icon_name('"'"'com.audioshare.AudioConnectionManager'"'"')' "$BUILD_DIR/src/$script"
                elif grep -q "self.set_default_size" "$BUILD_DIR/src/$script"; then
                    sed -i '0,/self.set_default_size/s//self.set_icon_name('"'"'com.audioshare.AudioConnectionManager'"'"')\n        self.set_default_size/' "$BUILD_DIR/src/$script"
                fi
            fi
            
            print_msg "Verified: $script"
        fi
    done
}

# Step 9: Build the Flatpak
build_flatpak() {
    print_step "Step 9: Building Flatpak"
    
    cd "$BUILD_DIR"
    
    print_msg "Starting flatpak-builder (this may take a while)..."
    
    if flatpak-builder --force-clean --repo="../$REPO_DIR" build "$APP_ID.yaml"; then
        print_msg "Build successful!"
    else
        print_error "Build failed!"
        cd ..
        exit 1
    fi
    
    cd ..
}

# Step 10: Create local repository
create_repo() {
    print_step "Step 10: Creating Local Repository"
    
    if [ -d "$REPO_DIR" ]; then
        print_msg "Repository created at: $REPO_DIR"
    else
        print_error "Repository not created"
        exit 1
    fi
}

# Step 11: Install the Flatpak
install_flatpak() {
    print_step "Step 11: Installing Flatpak"
    
    # Remove old installation if exists
    if flatpak list --app | grep -q "$APP_ID"; then
        print_msg "Removing old installation..."
        flatpak uninstall -y "$APP_ID" 2>/dev/null || true
    fi
    
    # Remove old remote if exists
    if flatpak remotes --user | grep -q "audioshare-local"; then
        print_msg "Removing old remote..."
        flatpak remote-delete --user audioshare-local 2>/dev/null || true
    fi
    
    # Add local repository
    print_msg "Adding local repository..."
    flatpak remote-add --user --no-gpg-verify audioshare-local "$REPO_DIR"
    
    # Install
    print_msg "Installing application..."
    if flatpak install -y --user audioshare-local "$APP_ID"; then
        print_msg "Installation successful!"
    else
        print_error "Installation failed!"
        exit 1
    fi
}

# Step 12: Create bundle for distribution
create_bundle() {
    print_step "Step 12: Creating Distribution Bundle"
    
    local bundle_name="AudioConnectionManager-${VERSION}.flatpak"
    
    if flatpak build-bundle "$REPO_DIR" "$bundle_name" "$APP_ID"; then
        print_msg "Created bundle: $bundle_name"
        print_msg "Users can install with: flatpak install $bundle_name"
    else
        print_warning "Failed to create bundle (optional step)"
    fi
}

# Print success message
print_success() {
    print_step "Build Complete!"
    
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  Audio Connection Manager Flatpak Build Complete!  ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Run the application:"
    echo "     ${YELLOW}flatpak run $APP_ID${NC}"
    echo ""
    echo "  2. Or launch from your application menu"
    echo ""
    echo "  3. To uninstall:"
    echo "     ${YELLOW}flatpak uninstall $APP_ID${NC}"
    echo ""
    echo "  4. To rebuild:"
    echo "     ${YELLOW}./build-flatpak.sh --rebuild${NC}"
    echo ""
    
    if [ -f "AudioConnectionManager-${VERSION}.flatpak" ]; then
        echo -e "${BLUE}Distribution bundle created:${NC}"
        echo "  AudioConnectionManager-${VERSION}.flatpak"
        echo ""
    fi
}

# Clean build
clean_build() {
    print_step "Cleaning Previous Build"
    
    rm -rf "$BUILD_DIR" "$REPO_DIR" AudioConnectionManager-*.flatpak
    print_msg "Cleaned build directories"
}

# Main execution
main() {
    echo -e "${BLUE}"
    cat << "EOF"
    ╔═══════════════════════════════════════════════════════╗
    ║  Audio Connection Manager - Flatpak Build Script     ║
    ║                                                       ║
    ║  This script will build and install a Flatpak        ║
    ║  package for the Audio Connection Manager            ║
    ╚═══════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Parse arguments
    case "${1:-}" in
        --clean)
            clean_build
            exit 0
            ;;
        --rebuild)
            clean_build
            ;;
        --help)
            echo "Usage: $0 [option]"
            echo ""
            echo "Options:"
            echo "  (none)     Build and install Flatpak"
            echo "  --rebuild  Clean and rebuild"
            echo "  --clean    Clean build directories only"
            echo "  --help     Show this help"
            exit 0
            ;;
    esac
    
    # Run all steps
    check_dependencies
    check_runtime
    create_structure
    create_desktop_file
    create_appdata
    create_icon
    create_manifest
    modify_scripts
    build_flatpak
    create_repo
    install_flatpak
    create_bundle
    print_success
}

# Run main function
main "$@"
