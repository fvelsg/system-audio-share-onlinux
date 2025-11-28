#!/bin/bash
#
# Audio Output-to-Input Connection Script with Virtual Mixer
# Creates a virtual device that mixes all outputs and sends to inputs
# Usage: ./connect-outputs-to-inputs.sh [create|monitor|delete]
#

VIRTUAL_SINK_NAME="AudioMixer_Virtual"
VIRTUAL_SINK_DESC="Audio Mixer Virtual Device"

# Get all output ports from applications (excluding monitors and hardware devices)
get_all_output_ports() {
    pw-dump 2>/dev/null | jq -r '
        # Store root for node lookup
        . as $root |
        .[] | 
        select(.type == "PipeWire:Interface:Port") |
        select(.info.props."port.direction" == "out") |
        # Get the node id this port belongs to
        .info.props."node.id" as $node_id |
        # Find the corresponding node
        ($root[] | select(.type == "PipeWire:Interface:Node") | select(.id == $node_id)) as $node |
        # Get media class
        ($node.info.props."media.class" // "") as $media_class |
        # Exclude AudioMixer_Virtual
        select(($node.info.props."node.name" // "") | contains("AudioMixer_Virtual") | not) |
        # Exclude monitors
        select($media_class | test("Monitor") | not) |
        # ONLY include Stream nodes (applications)
        select($media_class | test("Stream/Output|Stream/Source")) |
        # Must have audio channels
        select(.info.props."audio.channel" // "" | test("FL|FR|MONO")) |
        # Create unique identifier using port.id
        {
            port_id: .id,
            node_id: $node_id,
            port_alias: (.info.props."port.alias" // .info.props."port.name" // "Unknown"),
            port_name: (.info.props."port.name" // ""),
            node_name: ($node.info.props."node.name" // ""),
            media_class: $media_class,
            app_name: ($node.info.props."application.name" // $node.info.props."app.name" // "")
        } |
        # Return format: port_id|port_alias|app_name (using ID for uniqueness)
        "\(.port_id)|\(.port_alias)|\(.app_name)"
    ' | sort -u
}

# Get all input ports from applications ONLY (NO SINKS, NO HARDWARE)
get_all_input_ports() {
    pw-dump 2>/dev/null | jq -r '
        # Store root for node lookup
        . as $root |
        .[] | 
        select(.type == "PipeWire:Interface:Port") |
        select(.info.props."port.direction" == "in") |
        # Get the node id this port belongs to
        .info.props."node.id" as $node_id |
        # Find the corresponding node
        ($root[] | select(.type == "PipeWire:Interface:Node") | select(.id == $node_id)) as $node |
        # Get media class and node name
        ($node.info.props."media.class" // "") as $media_class |
        ($node.info.props."node.name" // "") as $node_name |
        # CRITICAL: Exclude AudioMixer_Virtual
        select($node_name | contains("AudioMixer_Virtual") | not) |
        # CRITICAL: ONLY Stream/Input or Stream/Sink (application streams that accept input)
        select($media_class | test("Stream/Input|Stream/Sink")) |
        # CRITICAL: Exclude anything with "Audio/Sink" (hardware sinks)
        select($media_class | contains("Audio/Sink") | not) |
        # Must have audio channels
        select(.info.props."audio.channel" // "" | test("FL|FR|MONO")) |
        # Create unique identifier using port.id
        {
            port_id: .id,
            node_id: $node_id,
            port_alias: (.info.props."port.alias" // .info.props."port.name" // "Unknown"),
            port_name: (.info.props."port.name" // ""),
            node_name: $node_name,
            media_class: $media_class,
            app_name: ($node.info.props."application.name" // $node.info.props."app.name" // "")
        } |
        # Return format: port_id|port_alias|app_name (using ID for uniqueness)
        "\(.port_id)|\(.port_alias)|\(.app_name)"
    ' | sort -u
}

# Extract first word from app name for comparison
get_first_word() {
    echo "$1" | awk '{print tolower($1)}'
}

# Check if output should be excluded from connecting to mixer
# based on matching input app names
should_exclude_output() {
    local output_app="$1"
    shift
    local input_apps=("$@")
    
    local output_first=$(get_first_word "$output_app")
    
    # If output has no app name, don't exclude
    [ -z "$output_first" ] && return 1
    
    # Check if any input has matching first word
    for input_app in "${input_apps[@]}"; do
        local input_first=$(get_first_word "$input_app")
        
        if [ "$output_first" = "$input_first" ]; then
            return 0  # Should exclude
        fi
    done
    
    return 1  # Should not exclude
}

# Check if virtual sink exists
virtual_sink_exists() {
    pactl list sinks short 2>/dev/null | grep -q "$VIRTUAL_SINK_NAME"
}

# Get virtual sink monitor ports
get_virtual_monitor_ports() {
    local monitor_fl="${VIRTUAL_SINK_NAME}:monitor_FL"
    local monitor_fr="${VIRTUAL_SINK_NAME}:monitor_FR"
    
    # Wait and verify the ports exist
    for i in {1..10}; do
        if pw-link -o 2>/dev/null | grep -q "$monitor_fl"; then
            echo "$monitor_fl"
            echo "$monitor_fr"
            return 0
        fi
        sleep 0.3
    done
    
    echo "ERROR: Virtual sink monitor ports not found!"
    return 1
}

# Get virtual sink input ports
get_virtual_sink_input_ports() {
    local virtual_inputs=$(pw-dump 2>/dev/null | jq -r --arg name "$VIRTUAL_SINK_NAME" '
        .[] |
        select(.type == "PipeWire:Interface:Port") |
        select(.info.props."port.direction" == "in") |
        select((.info.props."node.name" // "") == $name) |
        select(.info.props."port.name" // "" | test("playback_FL|playback_FR")) |
        "\(.info.props."port.name")|\(.info.props."port.alias" // .info.props."port.name")"
    ')
    
    if [ -z "$virtual_inputs" ]; then
        # Alternative: use port names directly
        virtual_inputs=$(pw-link -i 2>/dev/null | grep -A 100 "$VIRTUAL_SINK_NAME" | grep -E "playback_FL|playback_FR" | head -2)
        
        if [ -z "$virtual_inputs" ]; then
            return 1
        fi
    fi
    
    local virtual_fl=$(echo "$virtual_inputs" | grep "FL" | head -1 | cut -d'|' -f2)
    local virtual_fr=$(echo "$virtual_inputs" | grep "FR" | head -1 | cut -d'|' -f2)
    
    # Fallback if cut didn't work (no pipe separator)
    if [ -z "$virtual_fl" ]; then
        virtual_fl=$(echo "$virtual_inputs" | grep "FL" | head -1)
    fi
    if [ -z "$virtual_fr" ]; then
        virtual_fr=$(echo "$virtual_inputs" | grep "FR" | head -1)
    fi
    
    echo "$virtual_fl"
    echo "$virtual_fr"
    return 0
}

# Check if ports are already connected (more robust)
ports_connected() {
    local src="$1"
    local dst="$2"
    
    # Check both the link list and status
    pw-link -l 2>/dev/null | grep -F "$src" | grep -F -q "$dst"
    return $?
}

# Connect a specific output to virtual sink
connect_output_to_virtual() {
    local port_spec="$1"
    local virtual_fl="$2"
    local virtual_fr="$3"
    
    # Extract port_id, alias, and app_name from the format "port_id|port_alias|app_name"
    local port_id=$(echo "$port_spec" | cut -d'|' -f1)
    local port_alias=$(echo "$port_spec" | cut -d'|' -f2)
    local app_name=$(echo "$port_spec" | cut -d'|' -f3)
    
    # Use port_id for actual connection (unique), alias for display
    local connected=0
    
    # Check and connect FL
    if ! ports_connected "$port_id" "$virtual_fl"; then
        if timeout 3 pw-link "$port_id" "$virtual_fl" 2>/dev/null; then
            echo "  ✓ Connected: $port_alias → Virtual Mixer (L)"
            connected=1
        fi
    fi
    
    # Check and connect FR
    if ! ports_connected "$port_id" "$virtual_fr"; then
        if timeout 3 pw-link "$port_id" "$virtual_fr" 2>/dev/null; then
            echo "  ✓ Connected: $port_alias → Virtual Mixer (R)"
            connected=1
        fi
    fi
    
    return $connected
}

# Connect virtual monitor to a specific input
connect_virtual_to_input() {
    local port_spec="$1"
    local monitor_fl="$2"
    local monitor_fr="$3"
    
    # Extract port_id, alias, and app_name from the format "port_id|port_alias|app_name"
    local port_id=$(echo "$port_spec" | cut -d'|' -f1)
    local port_alias=$(echo "$port_spec" | cut -d'|' -f2)
    local app_name=$(echo "$port_spec" | cut -d'|' -f3)
    
    # Use port_id for actual connection (unique), alias for display
    local connected=0
    
    # Check and connect FL
    if ! ports_connected "$monitor_fl" "$port_id"; then
        if timeout 3 pw-link "$monitor_fl" "$port_id" 2>/dev/null; then
            echo "  ✓ Connected: Virtual Mixer → $port_alias (L)"
            connected=1
        fi
    fi
    
    # Check and connect FR
    if ! ports_connected "$monitor_fr" "$port_id"; then
        if timeout 3 pw-link "$monitor_fr" "$port_id" 2>/dev/null; then
            echo "  ✓ Connected: Virtual Mixer → $port_alias (R)"
            connected=1
        fi
    fi
    
    return $connected
}

# FUNCTION 1: Create virtual mixer
create_virtual_mixer() {
    echo "=== Creating Virtual Mixer ==="
    echo ""
    
    if virtual_sink_exists; then
        echo "Virtual sink already exists: $VIRTUAL_SINK_NAME"
        echo "✓ Virtual mixer is ready"
        return 0
    fi
    
    echo "Creating virtual sink: $VIRTUAL_SINK_NAME"
    pactl load-module module-null-sink \
        sink_name="$VIRTUAL_SINK_NAME" \
        sink_properties="device.description='$VIRTUAL_SINK_DESC'" \
        2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "✓ Virtual mixer created successfully"
        sleep 1  # Give PipeWire time to register the device
        return 0
    else
        echo "✗ Failed to create virtual mixer"
        return 1
    fi
}

# FUNCTION 2: Monitor and auto-connect (IMPROVED)
monitor_and_connect() {
    echo "=== Auto-Connect Monitor ==="
    echo ""
    
    # Ensure virtual sink exists
    if ! virtual_sink_exists; then
        echo "ERROR: Virtual mixer doesn't exist. Run 'create' first."
        return 1
    fi
    
    # Get virtual sink ports
    local virtual_ports=($(get_virtual_sink_input_ports))
    if [ $? -ne 0 ] || [ -z "${virtual_ports[0]}" ]; then
        echo "ERROR: Could not get virtual mixer input ports"
        return 1
    fi
    
    local virtual_fl="${virtual_ports[0]}"
    local virtual_fr="${virtual_ports[1]}"
    
    # Get monitor ports
    local monitor_ports=($(get_virtual_monitor_ports))
    if [ $? -ne 0 ]; then
        echo "ERROR: Could not get monitor ports"
        return 1
    fi
    
    local monitor_fl="${monitor_ports[0]}"
    local monitor_fr="${monitor_ports[1]}"
    
    echo "Virtual Mixer ready:"
    echo "  Input FL:   $virtual_fl"
    echo "  Input FR:   $virtual_fr"
    echo "  Monitor FL: $monitor_fl"
    echo "  Monitor FR: $monitor_fr"
    echo ""
    
    # Track known ports with timestamps
    declare -A known_outputs
    declare -A known_inputs
    declare -A output_timestamps
    declare -A input_timestamps
    
    # Connect existing ports
    echo "Connecting existing ports..."
    echo ""
    
    # First, collect all input app names for exclusion checking
    local input_app_names=()
    while read -r port_spec; do
        [ -z "$port_spec" ] && continue
        local app_name=$(echo "$port_spec" | cut -d'|' -f3)
        input_app_names+=("$app_name")
    done <<< "$(get_all_input_ports)"
    
    echo "=== APP OUTPUTS → VIRTUAL MIXER ==="
    while read -r port_spec; do
        [ -z "$port_spec" ] && continue
        
        local port_alias=$(echo "$port_spec" | cut -d'|' -f2)
        local app_name=$(echo "$port_spec" | cut -d'|' -f3)
        
        # Check if this output should be excluded
        if should_exclude_output "$app_name" "${input_app_names[@]}"; then
            echo "  ⊗ Skipped: $port_alias (matches input app: $app_name)"
            continue
        fi
        
        known_outputs["$port_spec"]=1
        output_timestamps["$port_spec"]=$(date +%s)
        connect_output_to_virtual "$port_spec" "$virtual_fl" "$virtual_fr"
    done <<< "$(get_all_output_ports)"
    
    echo ""
    echo "=== VIRTUAL MIXER → APP INPUTS ==="
    while read -r port_spec; do
        [ -z "$port_spec" ] && continue
        known_inputs["$port_spec"]=1
        input_timestamps["$port_spec"]=$(date +%s)
        connect_virtual_to_input "$port_spec" "$monitor_fl" "$monitor_fr"
    done <<< "$(get_all_input_ports)"
    
    echo ""
    echo "✓ Initial connections complete"
    echo ""
    echo "Monitoring for new audio ports... (Press Ctrl+C to stop)"
    echo "  - Checking every 1 second"
    echo "  - Will retry failed connections"
    echo "  - Auto-excluding outputs that match input app names"
    echo ""
    
    local check_count=0
    
    # Monitor loop - MORE FREQUENT AND PERSISTENT
    while true; do
        sleep 1
        check_count=$((check_count + 1))
        
        # Refresh input app names list
        input_app_names=()
        while read -r port_spec; do
            [ -z "$port_spec" ] && continue
            local app_name=$(echo "$port_spec" | cut -d'|' -f3)
            input_app_names+=("$app_name")
        done <<< "$(get_all_input_ports)"
        
        # Every 5 checks, re-verify all connections
        if [ $((check_count % 5)) -eq 0 ]; then
            # Re-check all known outputs
            for port_spec in "${!known_outputs[@]}"; do
                local port_id=$(echo "$port_spec" | cut -d'|' -f1)
                local app_name=$(echo "$port_spec" | cut -d'|' -f3)
                
                # Skip if now matches an input
                if should_exclude_output "$app_name" "${input_app_names[@]}"; then
                    continue
                fi
                
                if ! ports_connected "$port_id" "$virtual_fl" && \
                   ! ports_connected "$port_id" "$virtual_fr"; then
                    echo "[$(date '+%H:%M:%S')] Re-connecting output: $port_spec"
                    connect_output_to_virtual "$port_spec" "$virtual_fl" "$virtual_fr"
                fi
            done
            
            # Re-check all known inputs
            for port_spec in "${!known_inputs[@]}"; do
                local port_id=$(echo "$port_spec" | cut -d'|' -f1)
                if ! ports_connected "$monitor_fl" "$port_id" && \
                   ! ports_connected "$monitor_fr" "$port_id"; then
                    echo "[$(date '+%H:%M:%S')] Re-connecting input: $port_spec"
                    connect_virtual_to_input "$port_spec" "$monitor_fl" "$monitor_fr"
                fi
            done
        fi
        
        # Check for new outputs
        local current_outputs=$(get_all_output_ports)
        while read -r port_spec; do
            [ -z "$port_spec" ] && continue
            
            if [ -z "${known_outputs[$port_spec]}" ]; then
                local port_alias=$(echo "$port_spec" | cut -d'|' -f2)
                local app_name=$(echo "$port_spec" | cut -d'|' -f3)
                
                # Check if this output should be excluded
                if should_exclude_output "$app_name" "${input_app_names[@]}"; then
                    echo "[$(date '+%H:%M:%S')] ⊗ New output skipped: $port_alias (matches input app: $app_name)"
                    known_outputs["$port_spec"]=1  # Mark as known but don't connect
                    continue
                fi
                
                echo "[$(date '+%H:%M:%S')] New output detected: $port_alias"
                known_outputs["$port_spec"]=1
                output_timestamps["$port_spec"]=$(date +%s)
                
                # Try multiple times for new ports (they may not be ready)
                for attempt in 1 2 3; do
                    if connect_output_to_virtual "$port_spec" "$virtual_fl" "$virtual_fr"; then
                        break
                    fi
                    [ $attempt -lt 3 ] && sleep 0.5
                done
                echo ""
            fi
        done <<< "$current_outputs"
        
        # Check for new inputs
        local current_inputs=$(get_all_input_ports)
        while read -r port_spec; do
            [ -z "$port_spec" ] && continue
            
            if [ -z "${known_inputs[$port_spec]}" ]; then
                local port_alias=$(echo "$port_spec" | cut -d'|' -f2)
                echo "[$(date '+%H:%M:%S')] New input detected: $port_alias"
                known_inputs["$port_spec"]=1
                input_timestamps["$port_spec"]=$(date +%s)
                
                # Try multiple times for new ports
                for attempt in 1 2 3; do
                    if connect_virtual_to_input "$port_spec" "$monitor_fl" "$monitor_fr"; then
                        break
                    fi
                    [ $attempt -lt 3 ] && sleep 0.5
                done
                echo ""
            fi
        done <<< "$current_inputs"
    done
}

# FUNCTION 3: Volume control
set_virtual_volume() {
    local action="$1"
    local percent="${2:-10}"
    
    if ! virtual_sink_exists; then
        echo "ERROR: Virtual mixer doesn't exist."
        return 1
    fi
    
    # Get current volume
    local current_vol=$(pactl list sinks | grep -A 15 "$VIRTUAL_SINK_NAME" | grep "Volume:" | head -1 | awk '{print $5}' | tr -d '%')
    
    if [ -z "$current_vol" ]; then
        echo "ERROR: Could not get current volume"
        return 1
    fi
    
    local new_vol=$current_vol
    
    case "$action" in
        up)
            new_vol=$((current_vol + percent))
            echo "Increasing volume by ${percent}%: ${current_vol}% → ${new_vol}%"
            ;;
        down)
            new_vol=$((current_vol - percent))
            if [ $new_vol -lt 0 ]; then
                new_vol=0
            fi
            echo "Decreasing volume by ${percent}%: ${current_vol}% → ${new_vol}%"
            ;;
        mute)
            pactl set-sink-mute "$VIRTUAL_SINK_NAME" toggle
            local mute_status=$(pactl list sinks | grep -A 15 "$VIRTUAL_SINK_NAME" | grep "Mute:" | awk '{print $2}')
            echo "Mute toggled: $mute_status"
            return 0
            ;;
        set)
            new_vol=$percent
            echo "Setting volume to ${new_vol}%"
            ;;
        get)
            local mute_status=$(pactl list sinks | grep -A 15 "$VIRTUAL_SINK_NAME" | grep "Mute:" | awk '{print $2}')
            echo "Current volume: ${current_vol}% (Mute: $mute_status)"
            return 0
            ;;
        *)
            echo "ERROR: Invalid action. Use: up, down, mute, set, or get"
            return 1
            ;;
    esac
    
    # Set the new volume
    pactl set-sink-volume "$VIRTUAL_SINK_NAME" "${new_vol}%"
    
    if [ $? -eq 0 ]; then
        echo "✓ Volume adjusted successfully"
        return 0
    else
        echo "✗ Failed to adjust volume"
        return 1
    fi
}

# FUNCTION 4: Delete virtual mixer
delete_virtual_mixer() {
    echo "=== Deleting Virtual Mixer ==="
    echo ""
    
    if ! virtual_sink_exists; then
        echo "Virtual mixer does not exist. Nothing to delete."
        return 0
    fi
    
    echo "Removing virtual mixer: $VIRTUAL_SINK_NAME"
    echo "(All connections will be automatically disconnected)"
    echo ""
    
    # Get the module ID
    local module_id=$(pactl list modules short 2>/dev/null | \
        grep "module-null-sink" | \
        grep "$VIRTUAL_SINK_NAME" | \
        awk '{print $1}')
    
    if [ -n "$module_id" ]; then
        pactl unload-module "$module_id" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "✓ Virtual mixer removed successfully"
            echo "✓ All connections have been automatically disconnected"
            return 0
        else
            echo "✗ Failed to remove virtual mixer"
            return 1
        fi
    else
        echo "✗ Could not find module ID for virtual mixer"
        return 1
    fi
}

# Main script
main() {
    # Check dependencies
    local missing_deps=()
    for cmd in pw-link pw-dump pactl jq; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "ERROR: Missing dependencies: ${missing_deps[*]}"
        echo "Please install the required packages."
        exit 1
    fi
    
    # Parse command
    local action="${1:-}"
    
    case "$action" in
        create)
            create_virtual_mixer
            ;;
        monitor)
            monitor_and_connect
            ;;
        volume)
            local vol_action="${2:-get}"
            local vol_percent="${3:-10}"
            set_virtual_volume "$vol_action" "$vol_percent"
            ;;
        delete)
            delete_virtual_mixer
            ;;
        *)
            echo "Usage: $0 [create|monitor|volume|delete]"
            echo ""
            echo "Commands:"
            echo "  create           - Create the virtual audio mixer device"
            echo "  monitor          - Auto-connect all outputs/inputs (existing and new)"
            echo "  volume <action> [percent] - Control virtual mixer volume"
            echo "  delete           - Delete the virtual mixer (disconnects everything)"
            echo ""
            echo "Volume actions:"
            echo "  up [percent]     - Increase volume (default: 10%)"
            echo "  down [percent]   - Decrease volume (default: 10%)"
            echo "  mute             - Toggle mute"
            echo "  set <percent>    - Set volume to specific percentage"
            echo "  get              - Get current volume"
            echo ""
            echo "Volume examples:"
            echo "  $0 volume up       # Increase by 10%"
            echo "  $0 volume up 25    # Increase by 25%"
            echo "  $0 volume down 5   # Decrease by 5%"
            echo "  $0 volume set 150  # Set to 150% (no limit!)"
            echo "  $0 volume mute     # Toggle mute"
            echo "  $0 volume get      # Show current volume"
            echo ""
            echo "Typical workflow:"
            echo "  1. $0 create   # Create the mixer"
            echo "  2. $0 monitor  # Start auto-connecting (keeps running)"
            echo "  3. $0 volume up 20  # Adjust volume as needed"
            echo "  4. $0 delete   # Cleanup when done"
            echo ""
            echo "The virtual mixer combines all application outputs into one"
            echo "mixed stream and sends it to all application inputs."
            echo ""
            echo "Feedback Prevention:"
            echo "  Outputs are automatically excluded from the mixer if their"
            echo "  application name matches an input's application name."
            echo "  (Comparison uses first word, case-insensitive)"
            exit 1
            ;;
    esac
}

main "$@"