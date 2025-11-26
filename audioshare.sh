#!/usr/bin/env python3
"""
PipeWire Audio Connection Manager with GTK GUI
Manages connections between default sink monitor and application inputs
"""

import gi
import subprocess
import json
import sys
import os

gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib

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


class MonitorVolumeControl(Gtk.Window):
    def __init__(self):
        super().__init__(title="Monitor Volume Control")
        self.set_border_width(15)
        self.set_default_size(350, 280)
        self.set_resizable(False)
        
        # Default step percentage
        self.step_percentage = 20
        self.is_muted = False
        
        # Main vertical box
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=15)
        self.add(vbox)
        
        # Title label
        title_label = Gtk.Label()
        title_label.set_markup("<b><big>Monitor Source Volume</big></b>")
        vbox.pack_start(title_label, False, False, 0)
        
        # Volume controls frame
        volume_frame = Gtk.Frame(label="Volume Control")
        volume_frame.set_label_align(0.5, 0.5)
        volume_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        volume_box.set_border_width(15)
        volume_frame.add(volume_box)
        
        # Button box for volume up/down
        button_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        button_box.set_homogeneous(True)
        
        # Volume Up button
        self.up_button = Gtk.Button(label="🔊 Volume Up")
        self.up_button.connect("clicked", self.on_volume_up)
        button_box.pack_start(self.up_button, True, True, 0)
        
        # Volume Down button
        self.down_button = Gtk.Button(label="🔉 Volume Down")
        self.down_button.connect("clicked", self.on_volume_down)
        button_box.pack_start(self.down_button, True, True, 0)
        
        volume_box.pack_start(button_box, False, False, 0)
        
        # Mute/Unmute button
        self.mute_button = Gtk.Button(label="🔇 Mute")
        self.mute_button.connect("clicked", self.on_toggle_mute)
        volume_box.pack_start(self.mute_button, False, False, 0)
        
        vbox.pack_start(volume_frame, False, False, 0)
        
        # Step configuration frame
        config_frame = Gtk.Frame(label="Step Configuration")
        config_frame.set_label_align(0.5, 0.5)
        config_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        config_box.set_border_width(15)
        config_frame.add(config_box)
        
        step_label = Gtk.Label(label="Volume Step (%):")
        config_box.pack_start(step_label, False, False, 0)
        
        # Step entry
        self.step_entry = Gtk.Entry()
        self.step_entry.set_text(str(self.step_percentage))
        self.step_entry.set_width_chars(5)
        self.step_entry.set_max_length(3)
        config_box.pack_start(self.step_entry, False, False, 0)
        
        # Apply button
        apply_button = Gtk.Button(label="Apply")
        apply_button.connect("clicked", self.on_update_step)
        config_box.pack_start(apply_button, False, False, 0)
        
        vbox.pack_start(config_frame, False, False, 0)
        
        # Status label
        self.status_label = Gtk.Label(label="Ready")
        self.status_label.set_markup('<span foreground="green">Ready</span>')
        vbox.pack_start(self.status_label, False, False, 0)
        
        # Close button
        btn_close = Gtk.Button(label="Close")
        btn_close.connect("clicked", lambda x: self.destroy())
        vbox.pack_end(btn_close, False, False, 0)
    
    def get_monitor_source(self):
        """Get the monitor source name from default sink"""
        try:
            result = subprocess.run(['pactl', 'get-default-sink'], 
                                  capture_output=True, text=True, check=True)
            sink_name = result.stdout.strip()
            return f"{sink_name}.monitor"
        except subprocess.CalledProcessError as e:
            self.show_error_dialog(f"Failed to get default sink: {e}")
            return None
    
    def on_volume_up(self, button):
        """Increase monitor source volume"""
        monitor = self.get_monitor_source()
        if not monitor:
            return
        
        try:
            subprocess.run(['pactl', 'set-source-volume', monitor, 
                          f'+{self.step_percentage}%'], check=True)
            self.status_label.set_markup(
                f'<span foreground="green">Volume increased by {self.step_percentage}%</span>')
            # Unmute if it was muted
            if self.is_muted:
                self.is_muted = False
                self.mute_button.set_label("🔇 Mute")
        except subprocess.CalledProcessError as e:
            self.show_error_dialog(f"Failed to increase volume: {e}")
            self.status_label.set_markup('<span foreground="red">Error</span>')
    
    def on_volume_down(self, button):
        """Decrease monitor source volume"""
        monitor = self.get_monitor_source()
        if not monitor:
            return
        
        try:
            subprocess.run(['pactl', 'set-source-volume', monitor, 
                          f'-{self.step_percentage}%'], check=True)
            self.status_label.set_markup(
                f'<span foreground="green">Volume decreased by {self.step_percentage}%</span>')
        except subprocess.CalledProcessError as e:
            self.show_error_dialog(f"Failed to decrease volume: {e}")
            self.status_label.set_markup('<span foreground="red">Error</span>')
    
    def on_toggle_mute(self, button):
        """Toggle mute/unmute for monitor source"""
        monitor = self.get_monitor_source()
        if not monitor:
            return
        
        try:
            # Toggle mute state
            mute_value = '0' if self.is_muted else '1'
            subprocess.run(['pactl', 'set-source-mute', monitor, mute_value], check=True)
            
            self.is_muted = not self.is_muted
            
            if self.is_muted:
                self.mute_button.set_label("🔊 Unmute")
                self.status_label.set_markup('<span foreground="orange">Monitor muted</span>')
            else:
                self.mute_button.set_label("🔇 Mute")
                self.status_label.set_markup('<span foreground="green">Monitor unmuted</span>')
        except subprocess.CalledProcessError as e:
            self.show_error_dialog(f"Failed to toggle mute: {e}")
            self.status_label.set_markup('<span foreground="red">Error</span>')
    
    def on_update_step(self, button):
        """Update the step percentage from user input"""
        try:
            new_step = int(self.step_entry.get_text())
            if new_step < 1 or new_step > 100:
                raise ValueError("Percentage must be between 1 and 100")
            
            self.step_percentage = new_step
            self.status_label.set_markup(
                f'<span foreground="green">Step updated to {new_step}%</span>')
        except ValueError:
            self.show_error_dialog("Please enter a valid percentage (1-100)")
            self.step_entry.set_text(str(self.step_percentage))
    
    def show_error_dialog(self, message):
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


class MainWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Audio Connection Manager")
        self.set_default_size(450, 400)
        self.set_border_width(10)
        self.set_position(Gtk.WindowPosition.CENTER)
        
        self.manager = AudioConnectionManager()
        
        # Create main layout
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)
        
        # Title label
        label = Gtk.Label()
        label.set_markup("<big><b>Audio Connection Manager</b></big>")
        vbox.pack_start(label, False, False, 0)
        
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
        
        btn_disconnect = Gtk.Button(label="Disconnect from All Inputs")
        btn_disconnect.connect("clicked", self.on_disconnect_all)
        vbox.pack_start(btn_disconnect, False, False, 0)
        
        btn_advanced = Gtk.Button(label="Advanced Mode")
        btn_advanced.connect("clicked", self.on_advanced)
        vbox.pack_start(btn_advanced, False, False, 0)
        
        btn_volume = Gtk.Button(label="Monitor Volume Control")
        btn_volume.connect("clicked", self.on_volume_control)
        vbox.pack_start(btn_volume, False, False, 0)
        
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
        """Open advanced mode window"""
        advanced_window = AdvancedWindow(self.manager)
        advanced_window.show_all()
    
    def on_volume_control(self, button):
        """Open volume control window"""
        volume_window = MonitorVolumeControl()
        volume_window.show_all()
    
    def on_monitor_graph(self, button):
        """Launch the graph.sh script"""
        # Get the directory where this script is located
        script_dir = os.path.dirname(os.path.abspath(__file__))
        graph_script = os.path.join(script_dir, 'graph.sh')
        
        # Check if graph.sh exists
        if not os.path.exists(graph_script):
            self.show_error(f"graph.sh not found!\n\nExpected location:\n{graph_script}")
            return
        
        # Check if graph.sh is executable
        if not os.access(graph_script, os.X_OK):
            self.show_error(f"graph.sh is not executable!\n\nRun: chmod +x {graph_script}")
            return
        
        try:
            # Launch the script in the background
            subprocess.Popen([graph_script], 
                           cwd=script_dir,
                           stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
        except Exception as e:
            self.show_error(f"Failed to launch graph.sh:\n\n{str(e)}")


class AdvancedWindow(Gtk.Window):
    def __init__(self, manager):
        super().__init__(title="Advanced Mode")
        self.set_default_size(700, 500)
        self.set_border_width(10)
        self.set_position(Gtk.WindowPosition.CENTER)
        
        self.manager = manager
        
        # Create main layout
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)
        
        # Title
        label = Gtk.Label()
        label.set_markup("<b>Select specific inputs to connect/disconnect</b>")
        vbox.pack_start(label, False, False, 0)
        
        # Create scrolled window for the list
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_vexpand(True)
        vbox.pack_start(scrolled, True, True, 0)
        
        # Create list store and tree view
        self.liststore = Gtk.ListStore(bool, int, str, str)
        self.treeview = Gtk.TreeView(model=self.liststore)
        scrolled.add(self.treeview)
        
        # Toggle column
        renderer_toggle = Gtk.CellRendererToggle()
        renderer_toggle.connect("toggled", self.on_toggle)
        column_toggle = Gtk.TreeViewColumn("Select", renderer_toggle, active=0)
        self.treeview.append_column(column_toggle)
        
        # Port ID column
        renderer_text = Gtk.CellRendererText()
        column_id = Gtk.TreeViewColumn("Port ID", renderer_text, text=1)
        self.treeview.append_column(column_id)
        
        # Application column
        renderer_text = Gtk.CellRendererText()
        column_app = Gtk.TreeViewColumn("Application", renderer_text, text=2)
        column_app.set_expand(True)
        self.treeview.append_column(column_app)
        
        # Node ID column
        renderer_text = Gtk.CellRendererText()
        column_node = Gtk.TreeViewColumn("Node ID", renderer_text, text=3)
        self.treeview.append_column(column_node)
        
        # Load ports
        self.load_ports()
        
        # Button box
        button_box = Gtk.Box(spacing=5)
        vbox.pack_start(button_box, False, False, 0)
        
        btn_select_all = Gtk.Button(label="Select All")
        btn_select_all.connect("clicked", self.on_select_all)
        button_box.pack_start(btn_select_all, True, True, 0)
        
        btn_deselect_all = Gtk.Button(label="Deselect All")
        btn_deselect_all.connect("clicked", self.on_deselect_all)
        button_box.pack_start(btn_deselect_all, True, True, 0)
        
        # Action buttons
        action_box = Gtk.Box(spacing=5)
        vbox.pack_start(action_box, False, False, 0)
        
        btn_connect = Gtk.Button(label="Connect Selected")
        btn_connect.connect("clicked", self.on_connect)
        action_box.pack_start(btn_connect, True, True, 0)
        
        btn_disconnect = Gtk.Button(label="Disconnect Selected")
        btn_disconnect.connect("clicked", self.on_disconnect)
        action_box.pack_start(btn_disconnect, True, True, 0)
        
        # Close button
        btn_close = Gtk.Button(label="Close")
        btn_close.connect("clicked", lambda x: self.destroy())
        vbox.pack_end(btn_close, False, False, 0)
    
    def load_ports(self):
        """Load available ports into the list"""
        self.liststore.clear()
        ports = self.manager.get_all_input_ports()
        
        for port in ports:
            self.liststore.append([False, port['id'], port['alias'], str(port['node_id'])])
    
    def on_toggle(self, widget, path):
        """Handle toggle of checkbox"""
        self.liststore[path][0] = not self.liststore[path][0]
    
    def on_select_all(self, button):
        """Select all items"""
        for row in self.liststore:
            row[0] = True
    
    def on_deselect_all(self, button):
        """Deselect all items"""
        for row in self.liststore:
            row[0] = False
    
    def get_selected_ports(self):
        """Get list of selected port IDs"""
        selected = []
        for row in self.liststore:
            if row[0]:  # If checked
                selected.append(row[1])  # Port ID
        return selected
    
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
    
    def on_connect(self, button):
        """Connect to selected ports"""
        success, message = self.manager.get_monitor_ports()
        if not success:
            self.show_error(message)
            return
        
        selected = self.get_selected_ports()
        if not selected:
            self.show_error("No ports selected!")
            return
        
        success_count = 0
        failed_count = 0
        output = []
        
        for port_id in selected:
            results = self.manager.connect_port(port_id)
            for success, msg in results:
                output.append(msg)
                if success:
                    success_count += 1
                else:
                    failed_count += 1
        
        result_text = "\n".join(output)
        result_text += f"\n\nMonitor: {self.manager.get_default_sink()}\nPorts connected: {len(selected)}"
        
        if failed_count == 0:
            self.show_info("Success", f"✓ Successfully connected!\n\n{result_text}")
        else:
            self.show_warning(f"Partially connected:\n\n{result_text}\n\nSuccess: {success_count}\nFailed: {failed_count}")
    
    def on_disconnect(self, button):
        """Disconnect from selected ports"""
        success, message = self.manager.get_monitor_ports()
        if not success:
            self.show_error(message)
            return
        
        selected = self.get_selected_ports()
        if not selected:
            self.show_error("No ports selected!")
            return
        
        disconnected = 0
        output = []
        
        for port_id in selected:
            results = self.manager.disconnect_port(port_id)
            for success, msg in results:
                output.append(msg)
                if success:
                    disconnected += 1
        
        result_text = "\n".join(output)
        result_text += f"\n\nTotal disconnections: {disconnected}"
        
        self.show_info("Disconnected", f"✓ Disconnected!\n\n{result_text}")


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
