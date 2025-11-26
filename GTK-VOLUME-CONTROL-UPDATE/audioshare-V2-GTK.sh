#!/bin/bash

# PipeWire Audio Connection Manager with Zenity GUI
# Manages connections between default sink monitor and application inputs

# Volume control settings
VOLUME_INCREMENT=5  # Default volume increment percentage

# Function to get default sink name
get_default_sink() {
    pactl get-default-sink
}

# Function to get monitor source name
get_monitor_source() {
    local sink_name=$(get_default_sink)
    
    if [ -z "$sink_name" ]; then
        return 1
    fi
    
    echo "${sink_name}.monitor"
}

# Function to verify monitor source exists
verify_monitor_source() {
    local monitor_source=$(get_monitor_source)
    
    if [ -z "$monitor_source" ]; then
        zenity --error --text="Error: No default sink found!\n\nPlease check your audio configuration."
        return 1
    fi
    
    # Check if monitor source exists
    if ! pactl list sources short | grep -q "$monitor_source"; then
        zenity --error --text="Error: Monitor source not found!\n\nMonitor: $monitor_source\n\nThe audio device may have been disconnected.\nPlease reconnect your audio device and try again."
        return 1
    fi
    
    return 0
}

# Function to get current monitor volume
get_monitor_volume() {
    local monitor_source=$(get_monitor_source)
    pactl get-source-volume "$monitor_source" | grep -oP '\d+(?=%)' | head -1
}

# Function to adjust monitor volume
adjust_monitor_volume() {
    local adjustment=$1  # e.g., "+5%" or "-5%"
    local monitor_source=$(get_monitor_source)
    
    if ! verify_monitor_source; then
        return 1
    fi
    
    if pactl set-source-volume "$monitor_source" "$adjustment" 2>/dev/null; then
        local new_volume=$(get_monitor_volume)
        zenity --info --timeout=2 --text="✓ Volume adjusted!\n\nMonitor: $(get_default_sink)\nCurrent volume: ${new_volume}%"
        return 0
    else
        zenity --error --text="Failed to adjust volume!\n\nPlease check your audio configuration."
        return 1
    fi
}

# Function to get monitor ports for default sink
get_monitor_ports() {
    local sink_name=$(get_default_sink)
    
    # Check if default sink is available
    if [ -z "$sink_name" ]; then
        zenity --error --text="Error: No default sink found!\n\nPlease check your audio configuration."
        return 1
    fi
    
    MONITOR_FL="${sink_name}:monitor_FL"
    MONITOR_FR="${sink_name}:monitor_FR"
    
    # Verify the ports exist
    if ! pw-link -o | grep -q "$MONITOR_FL"; then
        zenity --error --text="Error: Monitor ports not found for default sink.\n\nDefault sink: $sink_name\n\nThe sink may have been disconnected or changed.\nPlease reconnect your audio device and try again."
        return 1
    fi
    
    return 0
}

# Function to get all available input ports
get_all_input_ports() {
    pw-dump 2>/dev/null | jq -r '.[] | select(.type == "PipeWire:Interface:Port" and .info.props["port.direction"] == "in" and .info.props["port.name"] == "input_MONO") | {id: .id, alias: .info.props["port.alias"], node_id: .info.props["node.id"]} | "\(.id)|\(.alias)|\(.node_id)"' 2>/dev/null
}

# Function to select input ports (for advanced mode)
select_input_ports() {
    local all_ports=$(get_all_input_ports)
    
    if [ -z "$all_ports" ]; then
        zenity --error --text="No input ports found!\n\nMake sure your applications are running."
        return 1
    fi
    
    local select_state="FALSE"
    
    while true; do
        # Build the checklist options
        local checklist_options=()
        while IFS='|' read -r port_id port_alias node_id; do
            checklist_options+=("$select_state" "$port_id" "$port_alias" "$node_id")
        done <<< "$all_ports"
        
        # Show checklist dialog with extra buttons
        SELECTED_PORTS=$(zenity --list --checklist \
            --title="Select Input Ports" \
            --text="Select which application inputs to connect/disconnect:" \
            --width=700 --height=450 \
            --column="Select" --column="Port ID" --column="Application" --column="Node ID" \
            "${checklist_options[@]}" \
            --separator="|" \
            --print-column=2 \
            --extra-button="Select All" \
            --extra-button="Deselect All")
        
        local exit_code=$?
        
        # Handle button clicks
        if [ $exit_code -eq 1 ]; then
            # User clicked Cancel or closed dialog
            return 1
        elif [ "$SELECTED_PORTS" == "Select All" ]; then
            # Set state to TRUE and loop again
            select_state="TRUE"
            continue
        elif [ "$SELECTED_PORTS" == "Deselect All" ]; then
            # Set state to FALSE and loop again
            select_state="FALSE"
            continue
        fi
        
        # If we get here, user clicked OK with a selection
        if [ -z "$SELECTED_PORTS" ]; then
            zenity --error --text="No ports selected!"
            return 1
        fi
        
        # Convert to array
        IFS='|' read -ra SELECTED_PORT_IDS <<< "$SELECTED_PORTS"
        return 0
    done
}

# Function to get all input port IDs automatically
get_all_input_port_ids() {
    pw-dump 2>/dev/null | jq -r '.[] | select(.type == "PipeWire:Interface:Port" and .info.props["port.direction"] == "in" and (.info.props["port.name"] | startswith("input_"))) | .id' 2>/dev/null
}

# Function to connect monitors (automatic mode)
connect_monitors_auto() {
    if ! get_monitor_ports; then
        return 1
    fi
    
    # Get all input port IDs
    mapfile -t ALL_PORT_IDS < <(get_all_input_port_ids)
    
    if [ ${#ALL_PORT_IDS[@]} -eq 0 ]; then
        zenity --error --text="No input ports found!\n\nMake sure your applications are running."
        return 1
    fi
    
    local success=0
    local failed=0
    local output=""
    
    for port_id in "${ALL_PORT_IDS[@]}"; do
        # Get port name for display
        local port_name=$(pw-dump 2>/dev/null | jq -r ".[] | select(.id == $port_id) | .info.props[\"port.alias\"]" 2>/dev/null)
        output+="Connecting to: $port_name\n"
        
        if pw-link "$MONITOR_FL" "$port_id" 2>/dev/null; then
            output+="  ✓ Connected FL\n"
            ((success++))
        else
            ((failed++))
        fi
        
        if pw-link "$MONITOR_FR" "$port_id" 2>/dev/null; then
            output+="  ✓ Connected FR\n"
            ((success++))
        else
            ((failed++))
        fi
        output+="\n"
    done
    
    if [ $failed -eq 0 ]; then
        zenity --info --text="✓ Successfully connected to all inputs!\n\n${output}Monitor: $(get_default_sink)\nTotal ports: ${#ALL_PORT_IDS[@]}"
    else
        zenity --warning --text="Partially connected:\n\n${output}Success: $success\nFailed: $failed"
    fi
}

# Function to disconnect monitors (automatic mode)
disconnect_monitors_auto() {
    if ! get_monitor_ports; then
        return 1
    fi
    
    # Get all input port IDs
    mapfile -t ALL_PORT_IDS < <(get_all_input_port_ids)
    
    if [ ${#ALL_PORT_IDS[@]} -eq 0 ]; then
        zenity --error --text="No input ports found!"
        return 1
    fi
    
    local disconnected=0
    local output=""
    
    for port_id in "${ALL_PORT_IDS[@]}"; do
        local port_name=$(pw-dump 2>/dev/null | jq -r ".[] | select(.id == $port_id) | .info.props[\"port.alias\"]" 2>/dev/null)
        output+="Disconnecting from: $port_name\n"
        
        if pw-link -d "$MONITOR_FL" "$port_id" 2>/dev/null; then
            output+="  ✓ Disconnected FL\n"
            ((disconnected++))
        fi
        
        if pw-link -d "$MONITOR_FR" "$port_id" 2>/dev/null; then
            output+="  ✓ Disconnected FR\n"
            ((disconnected++))
        fi
        output+="\n"
    done
    
    zenity --info --text="✓ Disconnected from all inputs!\n\n${output}Total disconnections: $disconnected"
}

# Function to connect monitors (advanced mode)
connect_monitors_advanced() {
    if ! get_monitor_ports; then
        return 1
    fi
    
    if ! select_input_ports; then
        return 1
    fi
    
    local success=0
    local failed=0
    local output=""
    
    for port_id in "${SELECTED_PORT_IDS[@]}"; do
        local port_name=$(pw-dump 2>/dev/null | jq -r ".[] | select(.id == $port_id) | .info.props[\"port.alias\"]" 2>/dev/null)
        output+="Connecting to: $port_name\n"
        
        if pw-link "$MONITOR_FL" "$port_id" 2>/dev/null; then
            output+="  ✓ Connected FL\n"
            ((success++))
        else
            output+="  ✗ Failed to connect FL\n"
            ((failed++))
        fi
        
        if pw-link "$MONITOR_FR" "$port_id" 2>/dev/null; then
            output+="  ✓ Connected FR\n"
            ((success++))
        else
            output+="  ✗ Failed to connect FR\n"
            ((failed++))
        fi
        output+="\n"
    done
    
    if [ $failed -eq 0 ]; then
        zenity --info --text="✓ Successfully connected!\n\n${output}Monitor: $(get_default_sink)\nPorts connected: ${#SELECTED_PORT_IDS[@]}"
    else
        zenity --warning --text="Partially connected:\n\n${output}Success: $success\nFailed: $failed"
    fi
}

# Function to disconnect monitors (advanced mode)
disconnect_monitors_advanced() {
    if ! get_monitor_ports; then
        return 1
    fi
    
    if ! select_input_ports; then
        return 1
    fi
    
    local disconnected=0
    local output=""
    
    for port_id in "${SELECTED_PORT_IDS[@]}"; do
        local port_name=$(pw-dump 2>/dev/null | jq -r ".[] | select(.id == $port_id) | .info.props[\"port.alias\"]" 2>/dev/null)
        output+="Disconnecting from: $port_name\n"
        
        if pw-link -d "$MONITOR_FL" "$port_id" 2>/dev/null; then
            output+="  ✓ Disconnected FL\n"
            ((disconnected++))
        fi
        
        if pw-link -d "$MONITOR_FR" "$port_id" 2>/dev/null; then
            output+="  ✓ Disconnected FR\n"
            ((disconnected++))
        fi
        output+="\n"
    done
    
    zenity --info --text="✓ Disconnected!\n\n${output}Total disconnections: $disconnected"
}

# Volume control menu
volume_control_menu() {
    while true; do
        local current_volume=$(get_monitor_volume)
        
        choice=$(zenity --list --width=450 --height=300 \
            --title="Volume Control" \
            --text="Adjust shared audio volume\n\nCurrent volume: ${current_volume}%\nIncrement: ${VOLUME_INCREMENT}%" \
            --column="Action" --column="Description" \
            "Increase" "Increase volume by ${VOLUME_INCREMENT}%" \
            "Decrease" "Decrease volume by ${VOLUME_INCREMENT}%" \
            "Settings" "Change volume increment" \
            "Back" "Return to main menu")
        
        case $choice in
            "Increase")
                adjust_monitor_volume "+${VOLUME_INCREMENT}%"
                ;;
            "Decrease")
                adjust_monitor_volume "-${VOLUME_INCREMENT}%"
                ;;
            "Settings")
                change_volume_increment
                ;;
            "Back"|*)
                return 0
                ;;
        esac
    done
}

# Function to change volume increment
change_volume_increment() {
    local new_increment=$(zenity --entry \
        --title="Volume Increment Settings" \
        --text="Enter volume increment percentage (1-50):\n\nCurrent: ${VOLUME_INCREMENT}%" \
        --entry-text="$VOLUME_INCREMENT")
    
    if [ $? -eq 0 ] && [ -n "$new_increment" ]; then
        # Validate input is a number between 1 and 50
        if [[ "$new_increment" =~ ^[0-9]+$ ]] && [ "$new_increment" -ge 1 ] && [ "$new_increment" -le 50 ]; then
            VOLUME_INCREMENT=$new_increment
            zenity --info --timeout=2 --text="✓ Volume increment set to ${VOLUME_INCREMENT}%"
        else
            zenity --error --text="Invalid input!\n\nPlease enter a number between 1 and 50."
        fi
    fi
}

# Main menu
main_menu() {
    choice=$(zenity --list --width=450 --height=330 \
        --title="Audio Connection Manager" \
        --text="Connect default monitor to application inputs" \
        --column="Action" --column="Description" \
        "Connect" "Connect to all inputs automatically" \
        "Disconnect" "Disconnect from all inputs automatically" \
        "Volume" "Adjust shared audio volume" \
        "Advanced" "Advanced mode - select specific inputs")
    
    case $choice in
        "Connect")
            connect_monitors_auto
            ;;
        "Disconnect")
            disconnect_monitors_auto
            ;;
        "Volume")
            volume_control_menu
            ;;
        "Advanced")
            advanced_menu
            ;;
        *)
            exit 0
            ;;
    esac
}

# Advanced mode menu
advanced_menu() {
    choice=$(zenity --list --width=450 --height=250 \
        --title="Advanced Mode" \
        --text="Select specific inputs to connect/disconnect" \
        --column="Action" --column="Description" \
        "Connect" "Connect to selected inputs" \
        "Disconnect" "Disconnect from selected inputs" \
        "Back" "Return to main menu")
    
    case $choice in
        "Connect")
            connect_monitors_advanced
            ;;
        "Disconnect")
            disconnect_monitors_advanced
            ;;
        "Back")
            main_menu
            ;;
        *)
            exit 0
            ;;
    esac
}

# Check dependencies
for cmd in zenity pw-link pw-dump pactl jq; do
    if ! command -v $cmd &> /dev/null; then
        zenity --error --text="Error: Required command '$cmd' not found.\n\nPlease install: $cmd"
        exit 1
    fi
done

# Run main menu
main_menu
