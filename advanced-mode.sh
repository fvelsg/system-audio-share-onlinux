#!/usr/bin/env python3
import subprocess
import json
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib, Gdk

#------------------Window Solution----------------------------------

# Add this after gi.require_version and imports
import sys

# Set application ID to match desktop file
GLib.set_prgname("com.audioshare.AudioConnectionManager")
GLib.set_application_name("Audio Sharing Control")

# In the Window __init__, add:
self.set_icon_name("com.audioshare.AudioConnectionManager")

#------------------------------------------------------------------------

class PortConnectionManager(Gtk.Window):
    def __init__(self):
        super().__init__(title="Advanced Port Connection Manager")
        self.set_border_width(15)
        self.set_default_size(800, 600)
        self.set_resizable(False)  # Match volume control - non-resizable
        
        # Get default sink
        self.default_sink = self.get_default_sink()
        if not self.default_sink:
            self.show_error_dialog("No default sink found!\n\nPlease check your audio configuration.")
            Gtk.main_quit()
            return
        
        self.monitor_fl = f"{self.default_sink}:monitor_FL"
        self.monitor_fr = f"{self.default_sink}:monitor_FR"
        
        # Verify monitor ports exist
        if not self.verify_monitor_ports():
            self.show_error_dialog(f"Monitor ports not found for default sink.\n\nDefault sink: {self.default_sink}\n\nThe sink may have been disconnected or changed.\nPlease reconnect your audio device and try again.")
            Gtk.main_quit()
            return
        
        # Main vertical box
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=15)
        self.add(vbox)
        
        # Title label
        title_label = Gtk.Label()
        title_label.set_markup("<b><big>Advanced Mode - Port Selection</big></b>")
        vbox.pack_start(title_label, False, False, 0)
        
        # Sink info label
        sink_label = Gtk.Label()
        sink_label.set_markup(f'<span foreground="blue">Default Sink: <b>{self.default_sink}</b></span>')
        vbox.pack_start(sink_label, False, False, 0)
        
        # Instructions
        info_label = Gtk.Label(label="Select specific inputs to connect/disconnect")
        vbox.pack_start(info_label, False, False, 0)
        
        # Show selection dialog
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_vexpand(True)
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_shadow_type(Gtk.ShadowType.IN)
        
        # Create list store: [selected, port_id, application, node_id]
        self.liststore = Gtk.ListStore(bool, int, str, str)
        
        # Create tree view
        self.treeview = Gtk.TreeView(model=self.liststore)
        self.treeview.set_headers_visible(True)
        
        # Checkbox column
        renderer_toggle = Gtk.CellRendererToggle()
        renderer_toggle.connect("toggled", self.on_cell_toggled)
        column_toggle = Gtk.TreeViewColumn("Select", renderer_toggle, active=0)
        self.treeview.append_column(column_toggle)
        
        # Port ID column
        renderer_text = Gtk.CellRendererText()
        column_id = Gtk.TreeViewColumn("Port ID", renderer_text, text=1)
        column_id.set_sort_column_id(1)
        self.treeview.append_column(column_id)
        
        # Application column
        renderer_app = Gtk.CellRendererText()
        column_app = Gtk.TreeViewColumn("Application", renderer_app, text=2)
        column_app.set_expand(True)
        column_app.set_sort_column_id(2)
        self.treeview.append_column(column_app)
        
        # Node ID column
        renderer_node = Gtk.CellRendererText()
        column_node = Gtk.TreeViewColumn("Node ID", renderer_node, text=3)
        column_node.set_sort_column_id(3)
        self.treeview.append_column(column_node)
        
        scrolled.add(self.treeview)
        vbox.pack_start(scrolled, True, True, 0)
        
        # Button box
        button_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        button_box.set_homogeneous(True)
        
        # Connect button
        connect_button = Gtk.Button(label="🔗 Connect Selected")
        connect_button.connect("clicked", self.on_connect_clicked)
        button_box.pack_start(connect_button, True, True, 0)
        
        # Disconnect button
        disconnect_button = Gtk.Button(label="⛓️‍💥 Disconnect Selected")
        disconnect_button.connect("clicked", self.on_disconnect_clicked)
        button_box.pack_start(disconnect_button, True, True, 0)
        
        # Refresh button
        refresh_button = Gtk.Button(label="🔄 Refresh")
        refresh_button.connect("clicked", self.on_refresh_clicked)
        button_box.pack_start(refresh_button, True, True, 0)
        
        vbox.pack_start(button_box, False, False, 0)
        
        # Status label
        self.status_label = Gtk.Label(label="Ready")
        self.status_label.set_markup('<span foreground="green">Ready</span>')
        vbox.pack_start(self.status_label, False, False, 0)
        
        # Load ports after all UI elements are created
        self.load_ports()
    
    def get_default_sink(self):
        """Get the default sink name"""
        try:
            result = subprocess.run(['pactl', 'get-default-sink'],
                                  capture_output=True, text=True, check=True)
            return result.stdout.strip()
        except subprocess.CalledProcessError:
            return None
    
    def verify_monitor_ports(self):
        """Verify that monitor ports exist"""
        try:
            result = subprocess.run(['pw-link', '-o'],
                                  capture_output=True, text=True, check=True)
            return self.monitor_fl in result.stdout
        except subprocess.CalledProcessError:
            return False
    
    def check_dependencies(self):
        """Check if required tools are installed"""
        # Check for pw-dump and pw-link
        try:
            subprocess.run(['pw-dump', '--version'], capture_output=True, stderr=subprocess.DEVNULL)
            subprocess.run(['pw-link', '--version'], capture_output=True, stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            return False
        return True
    
    def get_input_ports(self):
        """Get all input ports using pw-dump"""
        try:
            result = subprocess.run(['pw-dump'],
                                  capture_output=True, text=True, check=True)
            data = json.loads(result.stdout)
            
            ports = []
            for item in data:
                if (item.get('type') == 'PipeWire:Interface:Port' and
                    item.get('info', {}).get('props', {}).get('port.direction') == 'in'):
                    
                    port_name = item.get('info', {}).get('props', {}).get('port.name', '')
                    if port_name.startswith('input_'):
                        port_id = item.get('id', 0)
                        port_alias = item.get('info', {}).get('props', {}).get('port.alias', 'Unknown')
                        node_id = str(item.get('info', {}).get('props', {}).get('node.id', ''))
                        ports.append((port_id, port_alias, node_id))
            
            return ports
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            return []
    
    def load_ports(self):
        """Load input ports into the list"""
        self.liststore.clear()
        ports = self.get_input_ports()
        
        if not ports:
            self.status_label.set_markup('<span foreground="red">No input ports found! Make sure your applications are running.</span>')
            return
        
        for port_id, port_alias, node_id in ports:
            self.liststore.append([False, port_id, port_alias, node_id])
        
        self.status_label.set_markup(f'<span foreground="green">Loaded {len(ports)} port(s)</span>')
    
    def on_cell_toggled(self, widget, path):
        """Handle checkbox toggle"""
        self.liststore[path][0] = not self.liststore[path][0]
    
    def on_refresh_clicked(self, button):
        """Refresh the port list"""
        self.load_ports()
    
    def get_selected_ports(self):
        """Get list of selected port IDs"""
        selected = []
        for row in self.liststore:
            if row[0]:  # If checkbox is checked
                selected.append((row[1], row[2]))  # (port_id, port_alias)
        return selected
    
    def on_connect_clicked(self, button):
        """Connect selected ports"""
        selected = self.get_selected_ports()
        
        if not selected:
            self.show_error_dialog("No ports selected!")
            return
        
        self.process_ports(selected, "connect")
    
    def on_disconnect_clicked(self, button):
        """Disconnect selected ports"""
        selected = self.get_selected_ports()
        
        if not selected:
            self.show_error_dialog("No ports selected!")
            return
        
        self.process_ports(selected, "disconnect")
    
    def process_ports(self, selected_ports, action):
        """Process the selected ports (connect or disconnect)"""
        results = []
        success_count = 0
        failed_count = 0
        
        for port_id, port_name in selected_ports:
            if action == "connect":
                # Connect FL
                try:
                    subprocess.run(['pw-link', self.monitor_fl, str(port_id)],
                                 check=True, capture_output=True)
                    results.append(f"✓ Connected FL to {port_name}")
                    success_count += 1
                except subprocess.CalledProcessError:
                    results.append(f"✗ Failed to connect FL to {port_name}")
                    failed_count += 1
                
                # Connect FR
                try:
                    subprocess.run(['pw-link', self.monitor_fr, str(port_id)],
                                 check=True, capture_output=True)
                    results.append(f"✓ Connected FR to {port_name}")
                    success_count += 1
                except subprocess.CalledProcessError:
                    results.append(f"✗ Failed to connect FR to {port_name}")
                    failed_count += 1
            else:  # disconnect
                # Disconnect FL
                try:
                    subprocess.run(['pw-link', '-d', self.monitor_fl, str(port_id)],
                                 check=True, capture_output=True)
                    results.append(f"✓ Disconnected FL from {port_name}")
                    success_count += 1
                except subprocess.CalledProcessError:
                    results.append(f"✗ Failed to disconnect FL from {port_name}")
                    failed_count += 1
                
                # Disconnect FR
                try:
                    subprocess.run(['pw-link', '-d', self.monitor_fr, str(port_id)],
                                 check=True, capture_output=True)
                    results.append(f"✓ Disconnected FR from {port_name}")
                    success_count += 1
                except subprocess.CalledProcessError:
                    results.append(f"✗ Failed to disconnect FR from {port_name}")
                    failed_count += 1
        
        # Show results
        self.show_results_dialog(results, success_count, failed_count, action)
    
    def show_results_dialog(self, results, success_count, failed_count, action):
        """Show results dialog"""
        total_ops = success_count + failed_count
        results_text = "\n".join(results)
        summary = f"\n\nMonitor: {self.default_sink}\nTotal operations: {total_ops}\nSuccessful: {success_count}\nFailed: {failed_count}"
        
        if failed_count == 0:
            message_type = Gtk.MessageType.INFO
            if action == "connect":
                title = "Success"
                message = f"✓ Successfully connected!\n\n{results_text}{summary}"
            else:
                title = "Success"
                message = f"✓ Successfully disconnected!\n\n{results_text}{summary}"
        else:
            message_type = Gtk.MessageType.WARNING
            title = "Partial Success"
            message = f"Operation partially completed:\n\n{results_text}{summary}"
        
        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=0,
            message_type=message_type,
            buttons=Gtk.ButtonsType.OK,
            text=title
        )
        dialog.format_secondary_text(message)
        dialog.set_default_size(500, -1)
        dialog.run()
        dialog.destroy()
        
        # Update status
        if failed_count == 0:
            self.status_label.set_markup(f'<span foreground="green">Operation completed successfully</span>')
        else:
            self.status_label.set_markup(f'<span foreground="orange">Operation partially completed ({failed_count} failed)</span>')
    
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

def main():
    # Check dependencies first
    try:
        subprocess.run(['pw-dump', '--version'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['pw-link', '--version'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        dialog = Gtk.MessageDialog(
            flags=0,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text="PipeWire tools not found!"
        )
        dialog.format_secondary_text("Please install pipewire-tools.")
        dialog.run()
        dialog.destroy()
        return
    
    win = PortConnectionManager()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()

if __name__ == "__main__":
    main()
