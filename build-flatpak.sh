#!/bin/bash
###############################################################################
# Audio Sharing Control - Flatpak Build Script (GitHub Version)
# Downloads sources from GitHub instead of requiring local files
# Auto-installs dependencies for multiple Linux distributions
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
APP_NAME="Audio Sharing Control"
VERSION="1.0.0"
BUILD_DIR="flatpak-build"
REPO_DIR="flatpak-repo"

# GitHub configuration
GITHUB_USER="fvelsg"
GITHUB_REPO="system-audio-share-onlinux"
GITHUB_BRANCH="main"
GITHUB_BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}"

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

# Detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_ID_LIKE="$ID_LIKE"
        DISTRO_NAME="$NAME"
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        DISTRO_ID="$DISTRIB_ID"
        DISTRO_NAME="$DISTRIB_DESCRIPTION"
    else
        DISTRO_ID="unknown"
        DISTRO_NAME="Unknown Linux"
    fi
    
    # Normalize distro ID
    DISTRO_ID=$(echo "$DISTRO_ID" | tr '[:upper:]' '[:lower:]')
    DISTRO_ID_LIKE=$(echo "$DISTRO_ID_LIKE" | tr '[:upper:]' '[:lower:]')
}

# Determine package manager and install command
get_package_manager() {
    detect_distro
    
    # Check for specific distributions and their derivatives
    if [[ "$DISTRO_ID" == "arch" ]] || [[ "$DISTRO_ID_LIKE" == *"arch"* ]] || command_exists pacman; then
        PKG_MANAGER="pacman"
        INSTALL_CMD="sudo pacman -S --noconfirm"
        UPDATE_CMD="sudo pacman -Sy"
        PACKAGES=(flatpak flatpak-builder curl coreutils imagemagick librsvg)
        
    elif [[ "$DISTRO_ID" == "fedora" ]] || [[ "$DISTRO_ID" == "rhel" ]] || [[ "$DISTRO_ID" == "centos" ]] || [[ "$DISTRO_ID_LIKE" == *"fedora"* ]] || [[ "$DISTRO_ID_LIKE" == *"rhel"* ]] || command_exists dnf; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="sudo dnf install -y"
        UPDATE_CMD="sudo dnf check-update || true"
        PACKAGES=(flatpak flatpak-builder curl coreutils ImageMagick librsvg2-tools)
        
    elif [[ "$DISTRO_ID" == "opensuse"* ]] || [[ "$DISTRO_ID_LIKE" == *"suse"* ]] || command_exists zypper; then
        PKG_MANAGER="zypper"
        INSTALL_CMD="sudo zypper install -y"
        UPDATE_CMD="sudo zypper refresh"
        PACKAGES=(flatpak flatpak-builder curl coreutils ImageMagick librsvg)
        
    elif [[ "$DISTRO_ID" == "debian" ]] || [[ "$DISTRO_ID" == "ubuntu" ]] || [[ "$DISTRO_ID_LIKE" == *"debian"* ]] || [[ "$DISTRO_ID_LIKE" == *"ubuntu"* ]] || command_exists apt-get; then
        PKG_MANAGER="apt"
        INSTALL_CMD="sudo apt-get install -y"
        UPDATE_CMD="sudo apt-get update"
        PACKAGES=(flatpak flatpak-builder curl coreutils imagemagick librsvg2-bin)
        
    elif command_exists apk; then
        PKG_MANAGER="apk"
        INSTALL_CMD="sudo apk add"
        UPDATE_CMD="sudo apk update"
        PACKAGES=(flatpak flatpak-builder curl coreutils imagemagick librsvg)
        
    elif command_exists emerge; then
        PKG_MANAGER="portage"
        INSTALL_CMD="sudo emerge"
        UPDATE_CMD="sudo emerge --sync"
        PACKAGES=(sys-apps/flatpak dev-util/flatpak-builder net-misc/curl sys-apps/coreutils media-gfx/imagemagick gnome-base/librsvg)
        
    elif command_exists xbps-install; then
        PKG_MANAGER="xbps"
        INSTALL_CMD="sudo xbps-install -y"
        UPDATE_CMD="sudo xbps-install -S"
        PACKAGES=(flatpak flatpak-builder curl coreutils ImageMagick librsvg-utils)
        
    else
        print_error "Could not detect package manager"
        print_msg "Supported distributions:"
        print_msg "  - Ubuntu/Debian based (apt)"
        print_msg "  - Fedora/RHEL/CentOS (dnf)"
        print_msg "  - Arch Linux based (pacman)"
        print_msg "  - openSUSE (zypper)"
        print_msg "  - Alpine Linux (apk)"
        print_msg "  - Gentoo (portage)"
        print_msg "  - Void Linux (xbps)"
        return 1
    fi
    
    print_msg "Detected distribution: $DISTRO_NAME"
    print_msg "Package manager: $PKG_MANAGER"
    return 0
}

# Install missing dependencies
install_dependencies() {
    print_step "Installing Missing Dependencies"
    
    if ! get_package_manager; then
        print_error "Cannot proceed without package manager detection"
        exit 1
    fi
    
    local missing_deps=()
    local missing_packages=()
    
    # Check which dependencies are missing
    if ! command_exists flatpak; then
        missing_deps+=("flatpak")
    fi
    
    if ! command_exists flatpak-builder; then
        missing_deps+=("flatpak-builder")
    fi
    
    if ! command_exists curl; then
        missing_deps+=("curl")
    fi
    
    if ! command_exists sha256sum; then
        missing_deps+=("coreutils/sha256sum")
    fi
    
    # Optional but recommended tools
    if ! command_exists convert; then
        missing_deps+=("imagemagick (optional)")
    fi
    
    if ! command_exists rsvg-convert; then
        missing_deps+=("librsvg (optional)")
    fi
    
    if [ ${#missing_deps[@]} -eq 0 ]; then
        print_msg "All dependencies are already installed!"
        return 0
    fi
    
    print_warning "Missing dependencies: ${missing_deps[*]}"
    echo ""
    
    # Ask for confirmation
    read -p "Do you want to install missing dependencies? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
        print_error "Cannot proceed without required dependencies"
        exit 1
    fi
    
    print_msg "Updating package database..."
    eval "$UPDATE_CMD" || print_warning "Package update failed, continuing anyway..."
    
    print_msg "Installing packages: ${PACKAGES[*]}"
    
    if eval "$INSTALL_CMD ${PACKAGES[*]}"; then
        print_msg "Dependencies installed successfully!"
    else
        print_error "Failed to install some dependencies"
        print_msg "You may need to install them manually:"
        print_msg "  ${PACKAGES[*]}"
        exit 1
    fi
    
    # Add Flathub repository if not already added
    if ! flatpak remotes | grep -q flathub; then
        print_msg "Adding Flathub repository..."
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    fi
}

# Step 1: Check dependencies (now just verifies after auto-install)
check_dependencies() {
    print_step "Step 1: Verifying Dependencies"
    
    # First, try to install any missing dependencies
    install_dependencies
    
    # Verify all critical dependencies are now available
    local missing_critical=()
    
    if ! command_exists flatpak; then
        missing_critical+=("flatpak")
    fi
    
    if ! command_exists flatpak-builder; then
        missing_critical+=("flatpak-builder")
    fi
    
    if ! command_exists curl; then
        missing_critical+=("curl")
    fi
    
    if ! command_exists sha256sum; then
        missing_critical+=("coreutils/sha256sum")
    fi
    
    if [ ${#missing_critical[@]} -ne 0 ]; then
        print_error "Critical dependencies still missing: ${missing_critical[*]}"
        print_msg "Please install them manually and try again"
        exit 1
    fi
    
    print_msg "All required dependencies are installed!"
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
    mkdir -p "$BUILD_DIR/files"
    
    print_msg "Created directory: $BUILD_DIR"
}

# Step 4: Download files from GitHub and generate hashes
download_and_hash() {
    print_step "Step 4: Downloading Files from GitHub"
    
    local scripts=("audioshare.sh" "advanced-mode.sh" "volume-control.sh" "graph.sh" "connect-outputs-to-inputs.sh" "outputs-to-inputs.py")
    local temp_dir="$BUILD_DIR/temp"
    mkdir -p "$temp_dir"
    
    declare -A file_hashes
    
    for script in "${scripts[@]}"; do
        local url="${GITHUB_BASE_URL}/${script}"
        print_msg "Downloading: $script"
        
        if curl -fsSL "$url" -o "$temp_dir/$script"; then
            # Generate SHA256 hash
            local hash=$(sha256sum "$temp_dir/$script" | cut -d' ' -f1)
            file_hashes["$script"]="$hash"
            print_msg "  SHA256: $hash"
        else
            print_error "Failed to download: $script"
            print_msg "URL attempted: $url"
            exit 1
        fi
    done
    
    # Clean up temp directory
    rm -rf "$temp_dir"
    
    # Export hashes for manifest creation
    export AUDIOSHARE_HASH="${file_hashes[audioshare.sh]}"
    export ADVANCED_HASH="${file_hashes[advanced-mode.sh]}"
    export VOLUME_HASH="${file_hashes[volume-control.sh]}"
    export GRAPH_HASH="${file_hashes[graph.sh]}"
    export CONNECT_OUTPUTS_HASH="${file_hashes[connect-outputs-to-inputs.sh]}"
    export OUTPUTS_TO_INPUTS_HASH="${file_hashes[outputs-to-inputs.py]}"
}

# Step 5: Create desktop file
create_desktop_file() {
    print_step "Step 5: Creating Desktop Entry"
    
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

# Step 6: Create AppData XML
create_appdata() {
    print_step "Step 6: Creating AppData Metadata"
    
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
      Audio Sharing Control is a graphical tool for managing PipeWire audio connections.
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
  
  <url type="homepage">https://github.com/${GITHUB_USER}/${GITHUB_REPO}</url>
  <url type="bugtracker">https://github.com/${GITHUB_USER}/${GITHUB_REPO}/issues</url>
  
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

# Step 7: Create application icon
create_icon() {
    print_step "Step 7: Downloading Application Icon"
    
    # Try to download icon from GitHub
    if curl -fsSL "${GITHUB_BASE_URL}/icon.png" -o "$BUILD_DIR/files/$APP_ID.png" 2>/dev/null; then
        print_msg "Downloaded icon from GitHub: icon.png"
        
        # Verify it's a valid PNG
        if file "$BUILD_DIR/files/$APP_ID.png" | grep -q "PNG"; then
            print_msg "Icon verified as valid PNG image"
            return 0
        else
            print_warning "Downloaded file is not a valid PNG, will create default icon"
            rm -f "$BUILD_DIR/files/$APP_ID.png"
        fi
    else
        print_warning "Could not download icon.png from GitHub"
    fi
    
    print_warning "Creating default icon with ImageMagick or rsvg-convert"
    
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
    print_msg "Please ensure icon.png exists in your GitHub repository"
    exit 1
}

# Step 8: Create Flatpak manifest with GitHub sources
create_manifest() {
    print_step "Step 8: Creating Flatpak Manifest with GitHub Sources"
    
    cat > "$BUILD_DIR/$APP_ID.yaml" << EOF
app-id: ${APP_ID}
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
  # Install jq for JSON processing (required by connect-outputs-to-inputs.sh)
  - name: jq
    buildsystem: autotools
    config-opts:
      - --with-oniguruma=builtin
      - --disable-maintainer-mode
    sources:
      - type: archive
        url: https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-1.7.1.tar.gz
        sha256: 478c9ca129fd2e3443fe27314b455e211e0d8c60bc8ff7df703873deeee580c2

  # Wrapper script to find host commands
  - name: host-command-wrapper
    buildsystem: simple
    build-commands:
      - mkdir -p /app/bin
      - |
        cat > /app/bin/find-host-command << 'WRAPPER_EOF'
        #!/bin/bash
        # Wrapper to find commands in host or flatpak
        CMD="\$1"
        
        # Try various locations
        for path in "/usr/bin/\$CMD" "/bin/\$CMD" "/app/bin/\$CMD" "/var/run/host/usr/bin/\$CMD" "/run/host/usr/bin/\$CMD"; do
          if [ -x "\$path" ]; then
            echo "\$path"
            exit 0
          fi
        done
        
        # Fallback to PATH
        which "\$CMD" 2>/dev/null || echo "\$CMD"
        WRAPPER_EOF
      - chmod +x /app/bin/find-host-command
    sources: []

  # Main application - downloads from GitHub
  - name: audioshare
    buildsystem: simple
    build-commands:
      # Install scripts
      - install -Dm755 audioshare.sh /app/bin/audioshare.sh
      - install -Dm755 advanced-mode.sh /app/bin/advanced-mode.sh
      - install -Dm755 volume-control.sh /app/bin/volume-control.sh
      - install -Dm755 graph.sh /app/bin/graph.sh
      - install -Dm755 connect-outputs-to-inputs.sh /app/bin/connect-outputs-to-inputs.sh
      - install -Dm755 outputs-to-inputs.py /app/bin/outputs-to-inputs.py
      
      # Install desktop file
      - install -Dm644 ${APP_ID}.desktop /app/share/applications/${APP_ID}.desktop
      
      # Install appdata
      - install -Dm644 ${APP_ID}.appdata.xml /app/share/metainfo/${APP_ID}.appdata.xml
      
      # Install icon at multiple resolutions
      - install -Dm644 ${APP_ID}.png /app/share/icons/hicolor/256x256/apps/${APP_ID}.png
      - install -Dm644 ${APP_ID}.png /app/share/icons/hicolor/128x128/apps/${APP_ID}.png
      - install -Dm644 ${APP_ID}.png /app/share/icons/hicolor/64x64/apps/${APP_ID}.png
    
    sources:
      # Download scripts directly from GitHub
      - type: file
        url: ${GITHUB_BASE_URL}/audioshare.sh
        sha256: ${AUDIOSHARE_HASH}
        dest-filename: audioshare.sh
      
      - type: file
        url: ${GITHUB_BASE_URL}/advanced-mode.sh
        sha256: ${ADVANCED_HASH}
        dest-filename: advanced-mode.sh
      
      - type: file
        url: ${GITHUB_BASE_URL}/volume-control.sh
        sha256: ${VOLUME_HASH}
        dest-filename: volume-control.sh
      
      - type: file
        url: ${GITHUB_BASE_URL}/graph.sh
        sha256: ${GRAPH_HASH}
        dest-filename: graph.sh
      
      - type: file
        url: ${GITHUB_BASE_URL}/connect-outputs-to-inputs.sh
        sha256: ${CONNECT_OUTPUTS_HASH}
        dest-filename: connect-outputs-to-inputs.sh
      
      - type: file
        url: ${GITHUB_BASE_URL}/outputs-to-inputs.py
        sha256: ${OUTPUTS_TO_INPUTS_HASH}
        dest-filename: outputs-to-inputs.py
      
      # Local metadata files (generated by build script)
      - type: file
        path: files/${APP_ID}.desktop
      
      - type: file
        path: files/${APP_ID}.appdata.xml
      
      - type: file
        path: files/${APP_ID}.png
EOF
    
    print_msg "Created Flatpak manifest with GitHub sources"
    print_msg "  Branch: $GITHUB_BRANCH"
    print_msg "  Repository: https://github.com/${GITHUB_USER}/${GITHUB_REPO}"
    print_msg "  jq will be compiled and included in the Flatpak"
}

# Step 9: Build the Flatpak
build_flatpak() {
    print_step "Step 9: Building Flatpak"
    
    cd "$BUILD_DIR"
    
    print_msg "Starting flatpak-builder (this may take a while)..."
    print_msg "Note: Building jq from source will add a few minutes to the build time"
    
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
    
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  Audio Sharing Control Flatpak Build Complete!  ${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
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
    
    echo -e "${GREEN}Note:${NC} jq has been compiled and included in the Flatpak"
    echo "      The icon has been installed at multiple resolutions"
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
    ║  Audio Sharing Control - Flatpak Build Script     ║
    ║                  (GitHub Version)                     ║
    ║                                                       ║
    ║  Auto-installs dependencies and builds from GitHub   ║
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
            echo "  (none)     Build and install Flatpak from GitHub"
            echo "  --rebuild  Clean and rebuild"
            echo "  --clean    Clean build directories only"
            echo "  --help     Show this help"
            echo ""
            echo "Supported Distributions:"
            echo "  - Ubuntu/Debian based"
            echo "  - Fedora/RHEL/CentOS"
            echo "  - Arch Linux based"
            echo "  - openSUSE"
            echo "  - Alpine Linux"
            echo "  - Gentoo"
            echo "  - Void Linux"
            echo ""
            echo "GitHub Repository:"
            echo "  ${GITHUB_BASE_URL}"
            echo ""
            echo "What gets bundled:"
            echo "  - jq (compiled from source for JSON processing)"
            echo "  - All shell scripts and Python GUI"
            echo "  - Icon at multiple resolutions"
            exit 0
            ;;
    esac
    
    # Run all steps
    check_dependencies
    check_runtime
    create_structure
    download_and_hash
    create_desktop_file
    create_appdata
    create_icon
    create_manifest
    build_flatpak
    create_repo
    install_flatpak
    create_bundle
    print_success
}

# Run main function
main "$@"

