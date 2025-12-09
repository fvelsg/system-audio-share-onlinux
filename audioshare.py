#!/usr/bin/env python3
"""
PipeWire Audio Connection Manager with GTK GUI (Legacy)
Manages connections between default sink monitor and application inputs
"""

import gi
import subprocess
import json
import sys
import os

gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib

#------------------Window Solution----------------------------------

# Set application ID to match desktop file
GLib.set_prgname("com.audioshare.AudioConnectionManager")
GLib.set_application_name("Audio Sharing Control")

#------------------------------------------------------------------------


class AudioConnectionManager:
    def __init__(self):
        self.monitor_fl = None
        self.monitor_fr = None
        self.selected_ports = []
        
    def get_default_sink(self):
        """Get the default sink name"""
        try:
            result = subprocess.run(['pactl', 'get-default-sink'], 
                                  capture_output=True, text=True, check=True)
            return result.stdout.strip()
        except subprocess.CalledProcessError:
            return None
    
    def get_monitor_ports(self):
        """Get monitor ports for default sink"""
        sink_name = self.get_default_sink()
        
        if not sink_name:
            return False, "No default sink found!\n\nPlease check your audio configuration."
        
        self.monitor_fl = f"{sink_name}:monitor_FL"
        self.monitor_fr = f"{sink_name}:monitor_FR"
        
        # Verify the ports exist
        try:
            result = subprocess.run(['pw-link', '-o'], 
                                  capture_output=True, text=True, check=True)
            if self.monitor_fl not in result.stdout:
                return False, f"Monitor ports not found for default sink.\n\nDefault sink: {sink_name}\n\nThe sink may have been disconnected or changed.\nPlease reconnect your audio device and try again."
        except subprocess.CalledProcessError:
            return False, "Failed to query PipeWire links"
        
        return True, sink_name
    
    def get_all_input_ports(self):
        """Get all available input ports"""
        try:
            result = subprocess.run(['pw-dump'], 
                                  capture_output=True, text=True, check=True)
            data = json.loads(result.stdout)
            
            ports = []
            for item in data:
                if (item.get('type') == 'PipeWire:Interface:Port' and
                    item.get('info', {}).get('props', {}).get('port.direction') == 'in' and
                    item.get('info', {}).get('props', {}).get('port.name', '').startswith('input_')):
                    
                    port_id = item.get('id')
                    port_alias = item.get('info', {}).get('props', {}).get('port.alias', 'Unknown')
                    node_id = item.get('info', {}).get('props', {}).get('node.id', '')
                    
                    ports.append({
                        'id': port_id,
                        'alias': port_alias,
                        'node_id': node_id
                    })
            
            return ports
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            return []
    
    def get_port_name(self, port_id):
        """Get port alias by ID"""
        try:
            result = subprocess.run(['pw-dump'], 
                                  capture_output=True, text=True, check=True)
            data = json.loads(result.stdout)
            
            for item in data:
                if item.get('id') == port_id:
                    return item.get('info', {}).get('props', {}).get('port.alias', 'Unknown')
        except:
            pass
        return 'Unknown'
    
    def connect_port(self, port_id):
        """Connect monitor to a specific port"""
        results = []
        port_name = self.get_port_name(port_id)
        
        # Connect FL
        try:
            subprocess.run(['pw-link', self.monitor_fl, str(port_id)], 
                         capture_output=True, check=True)
            results.append((True, f"✓ Connected FL to {port_name}"))
        except subprocess.CalledProcessError:
            results.append((False, f"✗ Failed to connect FL to {port_name}"))
        
        # Connect FR
        try:
            subprocess.run(['pw-link', self.monitor_fr, str(port_id)], 
                         capture_output=True, check=True)
            results.append((True, f"✓ Connected FR to {port_name}"))
        except subprocess.CalledProcessError:
            results.append((False, f"✗ Failed to connect FR to {port_name}"))
        
        return results
    
    def disconnect_port(self, port_id):
        """Disconnect monitor from a specific port"""
        results = []
        port_name = self.get_port_name(port_id)
        
        # Disconnect FL
        try:
            subprocess.run(['pw-link', '-d', self.monitor_fl, str(port_id)], 
                         capture_output=True, check=True)
            results.append((True, f"✓ Disconnected FL from {port_name}"))
        except subprocess.CalledProcessError:
            results.append((False, f"✗ Failed to disconnect FL from {port_name}"))
        
        # Disconnect FR
        try:
            subprocess.run(['pw-link', '-d', self.monitor_fr, str(port_id)], 
                         capture_output=True, check=True)
            results.append((True, f"✓ Disconnected FR from {port_name}"))
        except subprocess.CalledProcessError:
            results.append((False, f"✗ Failed to disconnect FR from {port_name}"))
        
        return results


class MainWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Audio Connection Manager (Legacy)")

        self.set_icon_name("com.audioshare.AudioConnectionManager")
        self.set_border_width(10)
        self.set_default_size(450, 500)
        self.set_resizable(False)
        self.set_position(Gtk.WindowPosition.CENTER)
        
        self.manager = AudioConnectionManager()
        
        # Create main layout
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)
        
        # Header with back button and title
        header_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        vbox.pack_start(header_box, False, False, 0)
        
        # Back button
        self.back_button = Gtk.Button(label="← Back")
        self.back_button.set_tooltip_text("Return to Main Menu")
        self.back_button.connect("clicked", self.on_back_clicked)
        header_box.pack_start(self.back_button, False, False, 0)
        
        # Title (centered with expanding spacers)
        header_box.pack_start(Gtk.Label(), True, True, 0)  # Left spacer
        title_label = Gtk.Label()
        title_label.set_markup("<big><b>Audio Connection Manager</b></big>")
        header_box.pack_start(title_label, False, False, 0)
        header_box.pack_start(Gtk.Label(), True, True, 0)  # Right spacer
        
        # Invisible placeholder to balance the back button
        placeholder = Gtk.Label()
        placeholder.set_size_request(70, -1)  # Same width as back button
        header_box.pack_start(placeholder, False, False, 0)
        
        # Legacy mode indicator
        legacy_label = Gtk.Label()
        legacy_label.set_markup('<span foreground="gray"><i>(Legacy Mode)</i></span>')
        vbox.pack_start(legacy_label, False, False, 0)
        
        # Description label
        desc = Gtk.Label(label="Connect default monitor to application inputs")
        desc.set_line_wrap(True)
        vbox.pack_start(desc, False, False, 0)
        
        # Separator
        vbox.pack_start(Gtk.Separator(), False, False, 5)
        
        # Buttons
        btn_connect = Gtk.Button(label="Connect to All Inputs")
        btn_connect.connect("clicked", self.on_connect_all)
        vbox.pack_start(btn_connect, False, False, 0)
        
        btn_volume = Gtk.Button(label="Monitor Volume Control")
        btn_volume.connect("clicked", self.on_volume_control)
        vbox.pack_start(btn_volume, False, False, 0)
        
        btn_disconnect = Gtk.Button(label="Disconnect from All Inputs")
        btn_disconnect.connect("clicked", self.on_disconnect_all)
        vbox.pack_start(btn_disconnect, False, False, 0)
        
        btn_advanced = Gtk.Button(label="Advanced Mode")
        btn_advanced.connect("clicked", self.on_advanced)
        vbox.pack_start(btn_advanced, False, False, 0)
        
        btn_graph = Gtk.Button(label="Monitor Graph")
        btn_graph.connect("clicked", self.on_monitor_graph)
        vbox.pack_start(btn_graph, False, False, 0)
        
        # Separator
        vbox.pack_start(Gtk.Separator(), False, False, 5)
        
        # Quit button
        btn_quit = Gtk.Button(label="Quit")
        btn_quit.connect("clicked", Gtk.main_quit)
        vbox.pack_end(btn_quit, False, False, 0)
        
        self.connect("destroy", Gtk.main_quit)
    
    def get_main_script_path(self):
        """Get the path to the main menu script"""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        main_script = os.path.join(script_dir, "outputs-to-inputs.py")
        
        if not os.path.exists(main_script):
            return None
        
        return main_script
    
    def on_back_clicked(self, button):
        """Go back to the main menu"""
        main_script = self.get_main_script_path()
        
        if not main_script:
            self.show_error("Main script (outputs-to-inputs.py) not found!")
            return
        
        try:
            # Launch the main script
            subprocess.Popen(
                ["python3", main_script],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            # Close this window after a brief delay
            GLib.timeout_add(100, self.close_window)
        except Exception as e:
            self.show_error(f"Failed to launch main script: {e}")
    
    def close_window(self):
        """Close the window gracefully"""
        self.destroy()
        Gtk.main_quit()
        return False
    
    def show_error(self, message):
        """Show error dialog"""
        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=0,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text="Error"
        )
        dialog.format_secondary_text(message)
        dialog.run()
        dialog.destroy()
    
    def show_info(self, title, message):
        """Show info dialog"""
        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=0,
            message_type=Gtk.MessageType.INFO,
            buttons=Gtk.ButtonsType.OK,
            text=title
        )
        dialog.format_secondary_text(message)
        dialog.run()
        dialog.destroy()
    
    def show_warning(self, message):
        """Show warning dialog"""
        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=0,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.OK,
            text="Warning"
        )
        dialog.format_secondary_text(message)
        dialog.run()
        dialog.destroy()
    
    def on_connect_all(self, button):
        """Connect to all inputs automatically"""
        success, message = self.manager.get_monitor_ports()
        if not success:
            self.show_error(message)
            return
        
        ports = self.manager.get_all_input_ports()
        if not ports:
            self.show_error("No input ports found!\n\nMake sure your applications are running.")
            return
        
        success_count = 0
        failed_count = 0
        output = []
        
        for port in ports:
            results = self.manager.connect_port(port['id'])
            for success, msg in results:
                output.append(msg)
                if success:
                    success_count += 1
                else:
                    failed_count += 1
        
        result_text = "\n".join(output)
        result_text += f"\n\nMonitor: {self.manager.get_default_sink()}\nTotal ports: {len(ports)}"
        
        if failed_count == 0:
            self.show_info("Success", f"✓ Successfully connected to all inputs!\n\n{result_text}")
        else:
            self.show_warning(f"Partially connected:\n\n{result_text}\n\nSuccess: {success_count}\nFailed: {failed_count}")
    
    def on_disconnect_all(self, button):
        """Disconnect from all inputs automatically"""
        success, message = self.manager.get_monitor_ports()
        if not success:
            self.show_error(message)
            return
        
        ports = self.manager.get_all_input_ports()
        if not ports:
            self.show_error("No input ports found!")
            return
        
        disconnected = 0
        output = []
        
        for port in ports:
            results = self.manager.disconnect_port(port['id'])
            for success, msg in results:
                output.append(msg)
                if success:
                    disconnected += 1
        
        result_text = "\n".join(output)
        result_text += f"\n\nTotal disconnections: {disconnected}"
        
        self.show_info("Disconnected", f"✓ Disconnected from all inputs!\n\n{result_text}")
    
    def on_advanced(self, button):
        """Launch the advanced-mode.sh script"""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        advanced_script = os.path.join(script_dir, 'advanced-mode.sh')
        
        if not os.path.exists(advanced_script):
            self.show_error(f"advanced-mode.sh not found!\n\nExpected location:\n{advanced_script}")
            return
        
        if not os.access(advanced_script, os.X_OK):
            self.show_error(f"advanced-mode.sh is not executable!\n\nRun: chmod +x {advanced_script}")
            return
        
        try:
            subprocess.Popen([advanced_script], 
                           cwd=script_dir,
                           stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
        except Exception as e:
            self.show_error(f"Failed to launch advanced-mode.sh:\n\n{str(e)}")
    
    def on_volume_control(self, button):
        """Launch the volume-control.sh script"""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        volume_script = os.path.join(script_dir, 'volume-control.sh')
        
        if not os.path.exists(volume_script):
            self.show_error(f"volume-control.sh not found!\n\nExpected location:\n{volume_script}")
            return
        
        if not os.access(volume_script, os.X_OK):
            self.show_error(f"volume-control.sh is not executable!\n\nRun: chmod +x {volume_script}")
            return
        
        try:
            subprocess.Popen([volume_script], 
                           cwd=script_dir,
                           stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
        except Exception as e:
            self.show_error(f"Failed to launch volume-control.sh:\n\n{str(e)}")
    
    def on_monitor_graph(self, button):
        """Launch the graph.sh script"""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        graph_script = os.path.join(script_dir, 'graph.sh')
        
        if not os.path.exists(graph_script):
            self.show_error(f"graph.sh not found!\n\nExpected location:\n{graph_script}")
            return
        
        if not os.access(graph_script, os.X_OK):
            self.show_error(f"graph.sh is not executable!\n\nRun: chmod +x {graph_script}")
            return
        
        try:
            subprocess.Popen([graph_script], 
                           cwd=script_dir,
                           stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
        except Exception as e:
            self.show_error(f"Failed to launch graph.sh:\n\n{str(e)}")


def check_dependencies():
    """Check if required commands are available"""
    required = ['pw-link', 'pw-dump', 'pactl']
    missing = []
    
    for cmd in required:
        try:
            subprocess.run(['which', cmd], capture_output=True, check=True)
        except subprocess.CalledProcessError:
            missing.append(cmd)
    
    if missing:
        dialog = Gtk.MessageDialog(
            flags=0,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text="Missing Dependencies"
        )
        dialog.format_secondary_text(
            f"Required commands not found: {', '.join(missing)}\n\n"
            f"Please install the required packages."
        )
        dialog.run()
        dialog.destroy()
        sys.exit(1)


if __name__ == "__main__":
    check_dependencies()
    win = MainWindow()
    win.show_all()
    Gtk.main()
