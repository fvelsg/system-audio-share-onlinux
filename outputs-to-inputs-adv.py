#!/usr/bin/env python3
"""
Audio Output-to-Input Connection GUI
GTK interface for managing the virtual audio mixer with volume control
"""

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib, Pango
import subprocess
import threading
import os
import signal
import re

#------------------Window Solution----------------------------------

# Add this after gi.require_version and imports
import sys

# Set application ID to match desktop file
GLib.set_prgname("com.audioshare.AudioConnectionManager")
GLib.set_application_name("Audio Sharing Control")


#------------------------------------------------------------------------


class AudioMixerGUI(Gtk.Window):
    def __init__(self):
        super().__init__(title="Audio Mixer Manager")

        # In the Window __init__, add:
        self.set_icon_name("com.audioshare.AudioConnectionManager")
        
        
        self.set_default_size(650, 600)
        self.set_border_width(10)
        self.set_resizable(False)  # Make window non-resizable like graph.sh
        
        # State variables
        self.monitor_process = None
        self.is_monitoring = False
        self.mixer_exists = False
        self.step_percentage = 20
        self.is_muted = False
        self.graph_process = None
        
        # Main container
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)
        
        # Title
        title_label = Gtk.Label()
        title_label.set_markup("<big><b>Virtual Audio Mixer Manager</b></big>")
        vbox.pack_start(title_label, False, False, 0)
        
        # Status frame
        status_frame = Gtk.Frame(label="Status")
        status_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5)
        status_box.set_border_width(10)
        status_frame.add(status_box)
        vbox.pack_start(status_frame, False, False, 0)
        
        # Status labels
        self.mixer_status_label = Gtk.Label()
        self.mixer_status_label.set_halign(Gtk.Align.START)
        status_box.pack_start(self.mixer_status_label, False, False, 0)
        
        self.monitor_status_label = Gtk.Label()
        self.monitor_status_label.set_halign(Gtk.Align.START)
        status_box.pack_start(self.monitor_status_label, False, False, 0)
        
        # Volume Control Frame
        volume_frame = Gtk.Frame(label="Volume Control")
        volume_frame.set_label_align(0.5, 0.5)
        volume_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        volume_box.set_border_width(15)
        volume_frame.add(volume_box)
        vbox.pack_start(volume_frame, False, False, 0)
        
        # Volume up/down buttons
        button_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        button_box.set_homogeneous(True)
        
        self.volume_up_button = Gtk.Button(label="🔊 Volume Up")
        self.volume_up_button.connect("clicked", self.on_volume_up)
        button_box.pack_start(self.volume_up_button, True, True, 0)
        
        self.volume_down_button = Gtk.Button(label="🔉 Volume Down")
        self.volume_down_button.connect("clicked", self.on_volume_down)
        button_box.pack_start(self.volume_down_button, True, True, 0)
        
        volume_box.pack_start(button_box, False, False, 0)
        
        # Mute/Unmute button
        self.mute_button = Gtk.Button(label="🔇 Mute")
        self.mute_button.connect("clicked", self.on_toggle_mute)
        volume_box.pack_start(self.mute_button, False, False, 0)
        
        # Open Graph Monitor button
        self.graph_button = Gtk.Button(label="📊 Open Waveform Monitor")
        self.graph_button.connect("clicked", self.on_open_graph)
        volume_box.pack_start(self.graph_button, False, False, 0)
        
        # Step configuration
        step_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        step_label = Gtk.Label(label="Volume Step (%):")
        step_box.pack_start(step_label, False, False, 0)
        
        self.step_entry = Gtk.Entry()
        self.step_entry.set_text(str(self.step_percentage))
        self.step_entry.set_width_chars(5)
        self.step_entry.set_max_length(3)
        step_box.pack_start(self.step_entry, False, False, 0)
        
        apply_button = Gtk.Button(label="Apply")
        apply_button.connect("clicked", self.on_update_step)
        step_box.pack_start(apply_button, False, False, 0)
        
        volume_box.pack_start(step_box, False, False, 0)
        
        # Volume status label
        self.volume_status_label = Gtk.Label()
        self.volume_status_label.set_markup('<span foreground="green">Ready</span>')
        volume_box.pack_start(self.volume_status_label, False, False, 0)
        
        # Initially disable volume controls
        self.set_volume_controls_sensitive(False)
        
        # Control buttons frame
        control_frame = Gtk.Frame(label="Controls")
        control_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        control_box.set_border_width(10)
        control_frame.add(control_box)
        vbox.pack_start(control_frame, False, False, 0)
        
        # Create mixer button
        self.create_button = Gtk.Button(label="Create Virtual Mixer")
        self.create_button.connect("clicked", self.on_create_clicked)
        control_box.pack_start(self.create_button, False, False, 0)
        
        # Start/Stop monitoring buttons in a horizontal box
        monitor_hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        control_box.pack_start(monitor_hbox, False, False, 0)
        
        self.start_button = Gtk.Button(label="Start Auto-Connect Monitor")
        self.start_button.connect("clicked", self.on_start_clicked)
        monitor_hbox.pack_start(self.start_button, True, True, 0)
        
        self.stop_button = Gtk.Button(label="Stop Monitor")
        self.stop_button.connect("clicked", self.on_stop_clicked)
        self.stop_button.set_sensitive(False)
        monitor_hbox.pack_start(self.stop_button, True, True, 0)
        
        # Delete mixer button
        self.delete_button = Gtk.Button(label="Delete Virtual Mixer")
        self.delete_button.connect("clicked", self.on_delete_clicked)
        control_box.pack_start(self.delete_button, False, False, 0)
        
        # Log frame
        log_frame = Gtk.Frame(label="Activity Log")
        vbox.pack_start(log_frame, True, True, 0)
        
        # Scrolled window for log
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        log_frame.add(scrolled)
        
        # Text view for log
        self.log_view = Gtk.TextView()
        self.log_view.set_editable(False)
        self.log_view.set_wrap_mode(Gtk.WrapMode.WORD)
        self.log_view.set_monospace(True)
        self.log_buffer = self.log_view.get_buffer()
        scrolled.add(self.log_view)
        
        # Bottom button box
        bottom_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        vbox.pack_start(bottom_box, False, False, 0)
        
        clear_button = Gtk.Button(label="Clear Log")
        clear_button.connect("clicked", self.on_clear_log)
        bottom_box.pack_start(clear_button, False, False, 0)
        
        # Spacer
        bottom_box.pack_start(Gtk.Label(), True, True, 0)
        
        quit_button = Gtk.Button(label="Quit")
        quit_button.connect("clicked", self.on_quit_clicked)
        bottom_box.pack_end(quit_button, False, False, 0)
        
        # Check initial status
        self.check_mixer_status()
        self.update_status_display()
        
        # Update mute state if mixer exists
        if self.mixer_exists:
            self.update_mute_state_from_system()
        
        # Connect window close event
        self.connect("destroy", self.on_window_destroy)
        
        self.log_message("Audio Mixer Manager started")
        self.log_message("Ready to manage virtual audio mixer")
    
    def get_script_path(self):
        """Get the path to the bash script"""
        # Assume script is in same directory as this GUI
        script_dir = os.path.dirname(os.path.abspath(__file__))
        script_path = os.path.join(script_dir, "connect-outputs-to-inputs.sh")
        
        if not os.path.exists(script_path):
            self.log_message(f"ERROR: Script not found at {script_path}")
            return None
        
        return script_path
    
    def get_graph_script_path(self):
        """Get the path to the graph.sh script"""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        script_path = os.path.join(script_dir, "graph.sh")
        
        if not os.path.exists(script_path):
            return None
        
        return script_path
    
    def on_open_graph(self, button):
        """Open the waveform monitor graph"""
        # Check if graph is already running
        if self.graph_process and self.graph_process.poll() is None:
            self.log_message("Waveform monitor is already open")
            return
        
        graph_path = self.get_graph_script_path()
        if not graph_path:
            self.show_error_dialog("graph.sh not found in the same directory as this script")
            self.log_message("ERROR: graph.sh not found")
            return
        
        # Check if mixer exists
        if not self.mixer_exists:
            self.show_mixer_warning_dialog(graph_path)
            return
        
        try:
            self.log_message("Opening waveform monitor with AudioMixer device...")
            self.graph_process = subprocess.Popen(
                ["python3", graph_path, "--device", "AudioMixer_Virtual.monitor"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            self.log_message("✓ Waveform monitor opened for AudioMixer_Virtual.monitor")
        except Exception as e:
            self.show_error_dialog(f"Failed to open waveform monitor: {e}")
            self.log_message(f"ERROR: Failed to open graph: {e}")
    
    def show_mixer_warning_dialog(self, graph_path):
        """Show warning dialog when mixer doesn't exist"""
        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=0,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.NONE,
            text="Audio Mixer Not Created"
        )
        dialog.format_secondary_text(
            "The AudioMixer_Virtual device needs to be created before opening the waveform monitor with it.\n\n"
            "Would you like to open the waveform monitor without specifying a device?"
        )
        
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        dialog.add_button("Open Without Device", Gtk.ResponseType.YES)
        dialog.add_button("Create Mixer First", Gtk.ResponseType.NO)
        
        response = dialog.run()
        dialog.destroy()
        
        if response == Gtk.ResponseType.YES:
            # Open graph without device parameter
            try:
                self.log_message("Opening waveform monitor without device parameter...")
                self.graph_process = subprocess.Popen(
                    ["python3", graph_path],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
                self.log_message("✓ Waveform monitor opened (default device)")
            except Exception as e:
                self.show_error_dialog(f"Failed to open waveform monitor: {e}")
                self.log_message(f"ERROR: Failed to open graph: {e}")
        elif response == Gtk.ResponseType.NO:
            # User wants to create mixer first
            self.log_message("Please create the Audio Mixer first, then open the waveform monitor")
    
    def check_mixer_status(self):
        """Check if virtual mixer exists"""
        try:
            result = subprocess.run(
                ["pactl", "list", "sinks", "short"],
                capture_output=True,
                text=True,
                timeout=5
            )
            self.mixer_exists = "AudioMixer_Virtual" in result.stdout
        except Exception as e:
            self.log_message(f"Error checking mixer status: {e}")
            self.mixer_exists = False
    
    def get_mute_state(self):
        """Get current mute state from system"""
        try:
            result = subprocess.run(
                ["pactl", "list", "sinks"],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            # Find AudioMixer_Virtual sink and its mute state
            lines = result.stdout.split('\n')
            in_mixer_sink = False
            
            for line in lines:
                if "AudioMixer_Virtual" in line:
                    in_mixer_sink = True
                elif in_mixer_sink and "Mute:" in line:
                    return "yes" in line.lower()
                elif in_mixer_sink and ("Sink #" in line or "Source #" in line):
                    break
            
            return False  # Default if not found
        except Exception as e:
            self.log_message(f"Error getting mute state: {e}")
            return False
    
    def update_mute_state_from_system(self):
        """Update GUI mute button from system state"""
        if not self.mixer_exists:
            return
        
        muted = self.get_mute_state()
        
        # Block signal to prevent feedback loop
        self.mute_button.handler_block_by_func(self.on_toggle_mute)
        
        self.is_muted = muted
        
        if muted:
            self.mute_button.set_label("🔊 Unmute")
            self.volume_status_label.set_markup('<span foreground="orange">Mixer muted</span>')
        else:
            self.mute_button.set_label("🔇 Mute")
            self.volume_status_label.set_markup('<span foreground="green">Ready</span>')
        
        # Unblock signal
        self.mute_button.handler_unblock_by_func(self.on_toggle_mute)
    
    def set_volume_controls_sensitive(self, sensitive):
        """Enable or disable all volume controls"""
        self.volume_up_button.set_sensitive(sensitive)
        self.volume_down_button.set_sensitive(sensitive)
        self.mute_button.set_sensitive(sensitive)
        self.step_entry.set_sensitive(sensitive)
    
    def on_volume_up(self, button):
        """Increase mixer volume"""
        if not self.mixer_exists:
            return
        
        try:
            subprocess.run(
                ["pactl", "set-sink-volume", "AudioMixer_Virtual", f"+{self.step_percentage}%"],
                check=True,
                timeout=5
            )
            self.volume_status_label.set_markup(
                f'<span foreground="green">Volume increased by {self.step_percentage}%</span>')
            self.log_message(f"Volume increased by {self.step_percentage}%")
            
            # Unmute if it was muted
            if self.is_muted:
                self.is_muted = False
                self.mute_button.set_label("🔇 Mute")
        except subprocess.CalledProcessError as e:
            self.show_error_dialog(f"Failed to increase volume: {e}")
            self.volume_status_label.set_markup('<span foreground="red">Error</span>')
    
    def on_volume_down(self, button):
        """Decrease mixer volume"""
        if not self.mixer_exists:
            return
        
        try:
            subprocess.run(
                ["pactl", "set-sink-volume", "AudioMixer_Virtual", f"-{self.step_percentage}%"],
                check=True,
                timeout=5
            )
            self.volume_status_label.set_markup(
                f'<span foreground="green">Volume decreased by {self.step_percentage}%</span>')
            self.log_message(f"Volume decreased by {self.step_percentage}%")
        except subprocess.CalledProcessError as e:
            self.show_error_dialog(f"Failed to decrease volume: {e}")
            self.volume_status_label.set_markup('<span foreground="red">Error</span>')
    
    def on_toggle_mute(self, button):
        """Toggle mute/unmute for mixer"""
        if not self.mixer_exists:
            return
        
        try:
            # Toggle mute state
            mute_value = '0' if self.is_muted else '1'
            subprocess.run(
                ["pactl", "set-sink-mute", "AudioMixer_Virtual", mute_value],
                check=True,
                timeout=5
            )
            
            self.is_muted = not self.is_muted
            
            if self.is_muted:
                self.mute_button.set_label("🔊 Unmute")
                self.volume_status_label.set_markup('<span foreground="orange">Mixer muted</span>')
                self.log_message("Mixer muted")
            else:
                self.mute_button.set_label("🔇 Mute")
                self.volume_status_label.set_markup('<span foreground="green">Mixer unmuted</span>')
                self.log_message("Mixer unmuted")
        except subprocess.CalledProcessError as e:
            self.show_error_dialog(f"Failed to toggle mute: {e}")
            self.volume_status_label.set_markup('<span foreground="red">Error</span>')
    
    def on_update_step(self, button):
        """Update the step percentage from user input"""
        try:
            new_step = int(self.step_entry.get_text())
            if new_step < 1 or new_step > 100:
                raise ValueError("Percentage must be between 1 and 100")
            
            self.step_percentage = new_step
            self.volume_status_label.set_markup(
                f'<span foreground="green">Step updated to {new_step}%</span>')
            self.log_message(f"Volume step updated to {new_step}%")
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
    
    def update_status_display(self):
        """Update status labels and enable/disable controls"""
        if self.mixer_exists:
            self.mixer_status_label.set_markup("🟢 <b>Virtual Mixer:</b> Active")
            self.create_button.set_sensitive(False)
            self.delete_button.set_sensitive(True)
            self.start_button.set_sensitive(not self.is_monitoring)
            self.set_volume_controls_sensitive(True)
        else:
            self.mixer_status_label.set_markup("🔴 <b>Virtual Mixer:</b> Not Created")
            self.create_button.set_sensitive(True)
            self.delete_button.set_sensitive(False)
            self.start_button.set_sensitive(False)
            self.set_volume_controls_sensitive(False)
        
        if self.is_monitoring:
            self.monitor_status_label.set_markup("🟢 <b>Auto-Connect Monitor:</b> Running")
            self.start_button.set_sensitive(False)
            self.stop_button.set_sensitive(True)
        else:
            self.monitor_status_label.set_markup("⚪ <b>Auto-Connect Monitor:</b> Stopped")
            self.start_button.set_sensitive(self.mixer_exists)
            self.stop_button.set_sensitive(False)
    
    def log_message(self, message):
        """Add message to log"""
        end_iter = self.log_buffer.get_end_iter()
        self.log_buffer.insert(end_iter, message + "\n")
        
        # Auto-scroll to bottom
        mark = self.log_buffer.create_mark(None, end_iter, False)
        self.log_view.scroll_mark_onscreen(mark)
    
    def run_command(self, command, success_msg, error_msg):
        """Run a shell command and log results"""
        script_path = self.get_script_path()
        if not script_path:
            return False
        
        try:
            self.log_message(f"Running: {command}")
            result = subprocess.run(
                ["bash", script_path, command],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0:
                self.log_message(success_msg)
                if result.stdout:
                    for line in result.stdout.strip().split('\n'):
                        self.log_message(f"  {line}")
                return True
            else:
                self.log_message(error_msg)
                if result.stderr:
                    for line in result.stderr.strip().split('\n'):
                        self.log_message(f"  ERROR: {line}")
                return False
        except Exception as e:
            self.log_message(f"ERROR: {e}")
            return False
    
    def on_create_clicked(self, button):
        """Create virtual mixer"""
        if self.run_command("create", "✓ Virtual mixer created", "✗ Failed to create mixer"):
            self.mixer_exists = True
            self.update_status_display()
            # Update mute state with system values
            GLib.timeout_add(500, self.update_mute_state_from_system)
    
    def monitor_thread(self):
        """Thread to run the monitor process"""
        script_path = self.get_script_path()
        if not script_path:
            GLib.idle_add(self.log_message, "ERROR: Script not found")
            return
        
        try:
            GLib.idle_add(self.log_message, "Starting auto-connect monitor...")
            
            self.monitor_process = subprocess.Popen(
                ["bash", script_path, "monitor"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1
            )
            
            # Read output line by line
            for line in self.monitor_process.stdout:
                if line.strip():
                    GLib.idle_add(self.log_message, line.rstrip())
            
            # Process ended
            self.monitor_process.wait()
            
            if self.monitor_process.returncode == 0:
                GLib.idle_add(self.log_message, "Monitor stopped normally")
            else:
                GLib.idle_add(self.log_message, f"Monitor stopped with error code {self.monitor_process.returncode}")
            
        except Exception as e:
            GLib.idle_add(self.log_message, f"ERROR in monitor thread: {e}")
        finally:
            self.monitor_process = None
            self.is_monitoring = False
            GLib.idle_add(self.update_status_display)
    
    def on_start_clicked(self, button):
        """Start monitoring"""
        if not self.mixer_exists:
            self.log_message("ERROR: Create the mixer first!")
            return
        
        if self.is_monitoring:
            self.log_message("Monitor is already running")
            return
        
        self.is_monitoring = True
        self.update_status_display()
        
        # Start monitor in separate thread
        thread = threading.Thread(target=self.monitor_thread, daemon=True)
        thread.start()
    
    def on_stop_clicked(self, button):
        """Stop monitoring"""
        if self.monitor_process:
            self.log_message("Stopping monitor...")
            try:
                # Send SIGINT (Ctrl+C) to the process
                self.monitor_process.send_signal(signal.SIGINT)
                
                # Wait a bit for graceful shutdown
                try:
                    self.monitor_process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    # Force kill if needed
                    self.monitor_process.kill()
                    self.log_message("Monitor forcefully stopped")
                
                self.monitor_process = None
            except Exception as e:
                self.log_message(f"Error stopping monitor: {e}")
        
        self.is_monitoring = False
        self.update_status_display()
    
    def on_delete_clicked(self, button):
        """Delete virtual mixer"""
        if self.is_monitoring:
            self.log_message("ERROR: Stop the monitor first!")
            return
        
        if self.run_command("delete", "✓ Virtual mixer deleted", "✗ Failed to delete mixer"):
            self.mixer_exists = False
            self.update_status_display()
    
    def on_clear_log(self, button):
        """Clear the log"""
        self.log_buffer.set_text("")
        self.log_message("Log cleared")
    
    def on_quit_clicked(self, button):
        """Quit application"""
        self.cleanup()
        Gtk.main_quit()
    
    def on_window_destroy(self, widget):
        """Handle window close"""
        self.cleanup()
        Gtk.main_quit()
    
    def cleanup(self):
        """Cleanup before exit"""
        if self.monitor_process:
            try:
                self.monitor_process.send_signal(signal.SIGINT)
                self.monitor_process.wait(timeout=2)
            except:
                try:
                    self.monitor_process.kill()
                except:
                    pass
        
        # Don't kill graph process - let it run independently
        if self.graph_process and self.graph_process.poll() is None:
            self.log_message("Waveform monitor will continue running")

def main():
    # Check dependencies
    missing = []
    for cmd in ["pactl", "pw-link", "pw-dump", "jq"]:
        if subprocess.run(["which", cmd], capture_output=True).returncode != 0:
            missing.append(cmd)
    
    if missing:
        dialog = Gtk.MessageDialog(
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text="Missing Dependencies"
        )
        dialog.format_secondary_text(
            f"Please install the following packages:\n{', '.join(missing)}"
        )
        dialog.run()
        dialog.destroy()
        return
    
    win = AudioMixerGUI()
    win.show_all()
    Gtk.main()

if __name__ == "__main__":
    main()