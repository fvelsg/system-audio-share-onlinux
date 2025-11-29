#!/usr/bin/env python3
import subprocess
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib

#------------------Window Solution----------------------------------

# Add this after gi.require_version and imports
import sys

# Set application ID to match desktop file
GLib.set_prgname("com.audioshare.AudioConnectionManager")
GLib.set_application_name("Audio Sharing Control")

# In the Window __init__, add:
self.set_icon_name("com.audioshare.AudioConnectionManager")

#------------------------------------------------------------------------


class MonitorVolumeControl(Gtk.Window):
    def __init__(self):
        super().__init__(title="Monitor Volume Control")

        # In the Window __init__, add:
        self.set_icon_name("com.audioshare.AudioConnectionManager")

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

def main():
    win = MonitorVolumeControl()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()

if __name__ == "__main__":
    main()
