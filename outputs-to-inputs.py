#!/usr/bin/env python3
"""
Simplified Audio Output-to-Input Connection GUI
GTK interface for managing the virtual audio mixer with volume control
FIXED: Proper subprocess cleanup without psutil dependency
"""

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib, Pango
from audio_monitor import AudioWaveformMonitor, AudioMonitor
import subprocess
import threading
import os
import signal
import time



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

        self.set_default_size(400, 350)
        self.set_border_width(15)
        self.set_resizable(False)
        
        # State variables
        self.monitor_process = None
        self.monitor_thread = None
        self.launched_processes = []  # Track all launched processes
        self.is_connected = False
        self.is_connecting = False
        self.step_percentage = 20
        self.is_muted = False
        self.shutdown_flag = False
        self.state_lock = threading.Lock()
        self.audio_monitor = None
        self.monitor_visible = False
        self.monitor_window = None
        
       

        
        # Main container
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=15)
        self.add(vbox)
        
        # Container for audio monitor (initially hidden)
        self.monitor_container = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        vbox.pack_start(self.monitor_container, False, False, 0)

        # Title
        title_label = Gtk.Label()
        title_label.set_markup("<big><b>Virtual Audio Mixer</b></big>")
        vbox.pack_start(title_label, False, False, 0)
        
        # Status indicator
        status_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        status_box.set_halign(Gtk.Align.CENTER)
        
        self.status_circle = Gtk.Label()
        self.status_circle.set_markup('<span font="24">⚪</span>')
        status_box.pack_start(self.status_circle, False, False, 0)
        
        self.status_label = Gtk.Label()
        self.status_label.set_markup("<b>Disconnected</b>")
        status_box.pack_start(self.status_label, False, False, 0)
        
        vbox.pack_start(status_box, False, False, 10)
        
        # Connect/Disconnect buttons
        button_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        button_box.set_homogeneous(True)
        
        self.connect_button = Gtk.Button(label="Connect")
        self.connect_button.connect("clicked", self.on_connect_clicked)
        #self.connect_button.connect("clicked", self.on_monitor_clicked)
        button_box.pack_start(self.connect_button, True, True, 0)
        
        self.disconnect_button = Gtk.Button(label="Disconnect")
        self.disconnect_button.connect("clicked", self.on_disconnect_clicked)
        #self.disconnect_button.connect("clicked", self.off_monitor_clicked)
        self.disconnect_button.set_sensitive(False)
        button_box.pack_start(self.disconnect_button, True, True, 0)
        
        vbox.pack_start(button_box, False, False, 0)
        
        # Separator
        separator = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        vbox.pack_start(separator, False, False, 5)
        
        # Volume Control Frame
        volume_frame = Gtk.Frame(label="Volume Control")
        volume_frame.set_label_align(0.5, 0.5)
        volume_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        volume_box.set_border_width(15)
        volume_frame.add(volume_box)
        vbox.pack_start(volume_frame, False, False, 0)
        
        # Volume up/down buttons
        vol_button_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        vol_button_box.set_homogeneous(True)
        
        self.volume_up_button = Gtk.Button(label="🔊 Volume Up")
        self.volume_up_button.connect("clicked", self.on_volume_up)
        vol_button_box.pack_start(self.volume_up_button, True, True, 0)
        
        self.volume_down_button = Gtk.Button(label="🔉 Volume Down")
        self.volume_down_button.connect("clicked", self.on_volume_down)
        vol_button_box.pack_start(self.volume_down_button, True, True, 0)
        
        volume_box.pack_start(vol_button_box, False, False, 0)
        
        # Mute/Unmute button
        self.mute_button = Gtk.Button(label="🔇 Mute")
        self.mute_button.connect("clicked", self.on_toggle_mute)
        volume_box.pack_start(self.mute_button, False, False, 0)
        
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
        
        # Separator
        separator2 = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        vbox.pack_start(separator2, False, False, 5)
        
        # Bottom buttons
        bottom_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        
        advanced_button = Gtk.Button(label="Advanced Mode")
        advanced_button.connect("clicked", self.on_advanced_clicked)
        bottom_box.pack_start(advanced_button, False, False, 0)
        
        legacy_button = Gtk.Button(label="Legacy App")
        legacy_button.connect("clicked", self.on_legacy_clicked)
        bottom_box.pack_start(legacy_button, False, False, 0)

        # Spacer
        bottom_box.pack_start(Gtk.Label(), True, True, 0)
        
        quit_button = Gtk.Button(label="Quit")
        quit_button.connect("clicked", self.on_quit_clicked)
        
        bottom_box.pack_end(quit_button, False, False, 0)
        
        vbox.pack_start(bottom_box, False, False, 0)
        
        # Check initial status
        self.check_mixer_status()
        
        # Connect window close event
        self.connect("destroy", self.on_window_destroy)
        
        self.on_monitor_clicked(button=type("obj", (object,), {"set_label": lambda self, x: None})())

    def get_script_path(self):
        """Get the path to the bash script"""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        script_path = os.path.join(script_dir, "connect-outputs-to-inputs.sh")
        
        if not os.path.exists(script_path):
            return None
        
        return script_path
    
    def get_advanced_script_path(self):
        """Get the path to the advanced GUI script"""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        script_path = os.path.join(script_dir, "outputs-to-inputs-adv.py")
        
        if not os.path.exists(script_path):
            return None
        
        return script_path
    
    def get_legacy_script_path(self):
        """Get the path to the legacy audioshare script"""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        
        # Try multiple possible file names
        possible_names = ["audioshare.sh", "audioshare.py", "audioshare"]
        
        for name in possible_names:
            script_path = os.path.join(script_dir, name)
            if os.path.exists(script_path):
                return script_path
        
        return None
    
    def kill_process_tree(self, pid):
        """Kill a process and all its children using OS commands"""
        try:
            # Use pkill to kill process group
            # The negative PID kills the entire process group
            os.killpg(os.getpgid(pid), signal.SIGTERM)
            time.sleep(0.5)
            
            # Check if still alive, then force kill
            try:
                os.killpg(os.getpgid(pid), signal.SIGKILL)
            except ProcessLookupError:
                pass  # Already dead
                
        except ProcessLookupError:
            pass  # Process doesn't exist
        except Exception as e:
            # Fallback: try killing just the main process
            try:
                os.kill(pid, signal.SIGTERM)
                time.sleep(0.3)
                os.kill(pid, signal.SIGKILL)
            except:
                pass
    
    def check_mixer_status(self):
        """Check if virtual mixer exists and update UI"""
        try:
            result = subprocess.run(
                ["pactl", "list", "sinks", "short"],
                capture_output=True,
                text=True,
                timeout=5
            )
            mixer_exists = "AudioMixer_Virtual" in result.stdout
            
            if mixer_exists:
                self.is_connected = True
                self.status_circle.set_markup('<span font="24">🟢</span>')
                self.status_label.set_markup("<b>Connected</b>")
                self.connect_button.set_sensitive(False)
                self.disconnect_button.set_sensitive(True)
                self.set_volume_controls_sensitive(True)
                self.update_mute_state_from_system()
            else:
                self.is_connected = False
                self.status_circle.set_markup('<span font="24">⚪</span>')
                self.status_label.set_markup("<b>Disconnected</b>")
                self.connect_button.set_sensitive(True)
                self.disconnect_button.set_sensitive(False)
                self.set_volume_controls_sensitive(False)
        except Exception as e:
            pass
    
    def get_mute_state(self):
        """Get current mute state from system"""
        try:
            result = subprocess.run(
                ["pactl", "list", "sinks"],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            lines = result.stdout.split('\n')
            in_mixer_sink = False
            
            for line in lines:
                if "AudioMixer_Virtual" in line:
                    in_mixer_sink = True
                elif in_mixer_sink and "Mute:" in line:
                    return "yes" in line.lower()
                elif in_mixer_sink and ("Sink #" in line or "Source #" in line):
                    break
            
            return False
        except Exception as e:
            return False
    
    def update_mute_state_from_system(self):
        """Update GUI mute button from system state"""
        if not self.is_connected:
            return
        
        muted = self.get_mute_state()
        
        try:
            self.mute_button.handler_block_by_func(self.on_toggle_mute)
        except:
            pass
        
        self.is_muted = muted
        
        if muted:
            self.mute_button.set_label("🔊 Unmute")
            self.volume_status_label.set_markup('<span foreground="orange">Mixer muted</span>')
        else:
            self.mute_button.set_label("🔇 Mute")
            self.volume_status_label.set_markup('<span foreground="green">Ready</span>')
        
        try:
            self.mute_button.handler_unblock_by_func(self.on_toggle_mute)
        except:
            pass
    
    def set_volume_controls_sensitive(self, sensitive):
        """Enable or disable all volume controls"""
        self.volume_up_button.set_sensitive(sensitive)
        self.volume_down_button.set_sensitive(sensitive)
        self.mute_button.set_sensitive(sensitive)
        self.step_entry.set_sensitive(sensitive)
    
    def on_volume_up(self, button):
        """Increase mixer volume"""
        if not self.is_connected:
            return
        
        try:
            subprocess.run(
                ["pactl", "set-sink-volume", "AudioMixer_Virtual", f"+{self.step_percentage}%"],
                check=True,
                timeout=5
            )
            self.volume_status_label.set_markup(
                f'<span foreground="green">Volume increased by {self.step_percentage}%</span>')
            
            GLib.timeout_add(200, self.update_mute_state_from_system)
        except subprocess.CalledProcessError as e:
            self.show_error_dialog(f"Failed to increase volume: {e}")
            self.volume_status_label.set_markup('<span foreground="red">Error</span>')
    
    def on_volume_down(self, button):
        """Decrease mixer volume"""
        if not self.is_connected:
            return
        
        try:
            subprocess.run(
                ["pactl", "set-sink-volume", "AudioMixer_Virtual", f"-{self.step_percentage}%"],
                check=True,
                timeout=5
            )
            self.volume_status_label.set_markup(
                f'<span foreground="green">Volume decreased by {self.step_percentage}%</span>')
        except subprocess.CalledProcessError as e:
            self.show_error_dialog(f"Failed to decrease volume: {e}")
            self.volume_status_label.set_markup('<span foreground="red">Error</span>')
    
    def on_toggle_mute(self, button):
        """Toggle mute/unmute for mixer"""
        if not self.is_connected:
            return
        
        try:
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
            else:
                self.mute_button.set_label("🔇 Mute")
                self.volume_status_label.set_markup('<span foreground="green">Mixer unmuted</span>')
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
    
    def connect_thread(self):
        """Thread to create mixer and start monitor"""
        script_path = self.get_script_path()
        if not script_path:
            GLib.idle_add(self.show_error_dialog, "Script not found")
            GLib.idle_add(self.finish_connection, False)
            return
        
        try:
            # Create mixer
            result = subprocess.run(
                ["bash", script_path, "create"],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode != 0:
                GLib.idle_add(self.show_error_dialog, "Failed to create mixer")
                GLib.idle_add(self.finish_connection, False)
                return
            
            # Start monitor with new process group
            with self.state_lock:
                if self.shutdown_flag:
                    GLib.idle_add(self.finish_connection, False)
                    return
                
                self.monitor_process = subprocess.Popen(
                    ["bash", script_path, "monitor"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    bufsize=1,
                    start_new_session=True  # CRITICAL: Create new process group
                )
            
            GLib.idle_add(self.finish_connection, True)
            
            # Monitor the process
            while not self.shutdown_flag:
                if self.monitor_process.poll() is not None:
                    break
                
                try:
                    line = self.monitor_process.stdout.readline()
                    if not line and self.monitor_process.poll() is not None:
                        break
                except:
                    break
                
                time.sleep(0.1)
            
            if not self.shutdown_flag and self.is_connected:
                GLib.idle_add(self.on_monitor_stopped_unexpectedly)
            
        except Exception as e:
            if not self.shutdown_flag:
                GLib.idle_add(self.show_error_dialog, f"Connection error: {e}")
                GLib.idle_add(self.finish_connection, False)
    
    def finish_connection(self, success):
        """Finish connection process and update UI"""
        with self.state_lock:
            self.is_connecting = False
            
            if success and not self.shutdown_flag:
                self.is_connected = True
                self.status_circle.set_markup('<span font="24">🟢</span>')
                self.status_label.set_markup("<b>Connected</b>")
                self.connect_button.set_sensitive(False)
                self.disconnect_button.set_sensitive(True)
                self.set_volume_controls_sensitive(True)
                GLib.timeout_add(500, self.update_mute_state_from_system)

                if self.monitor_visible and self.audio_monitor:
                    self.audio_monitor.set_source("AudioMixer_Virtual.monitor")
                
            else:
                self.status_circle.set_markup('<span font="24">⚪</span>')
                self.status_label.set_markup("<b>Disconnected</b>")
                self.connect_button.set_sensitive(True)
                self.disconnect_button.set_sensitive(False)

    def on_monitor_clicked(self, button=None):
        """Toggle audio monitor visibility (compact embedded version)"""
        try:
            source = "AudioMixer_Virtual.monitor" if self.is_connected else None
                
            self.audio_monitor = AudioWaveformMonitor(
                source=source,
                amplitude=1.5,
                color=(0.2, 0.8, 0.2),  # Green
                dark_theme=True
            )
                
            # Make the waveform widget compact (smaller height)
            #self.audio_monitor.waveform.set_size_request(380, 80)
            
            
            self.monitor_container.pack_start(self.audio_monitor, False, False, 0)
            self.audio_monitor.show_all()
            self.audio_monitor.start()
                
            button.set_label("Hide Monitor")
            self.monitor_visible = True
                
            # Slightly increase window height only
            current_width, current_height = self.get_size()
            self.resize(current_width, current_height + 100)
            self.audio_monitor.waveform.set_size_request(350, 60)
                
        except Exception as e:
            self.show_error_dialog(f"Failed to start audio monitor: {e}")

#    def off_monitor_clicked(self, button):
#        """Toggle audio monitor visibility to off (compact embedded version)"""
#        # Hide and destroy monitor
#        if self.audio_monitor:
#            self.audio_monitor.stop()
#            self.audio_monitor.cleanup()
#            self.monitor_container.remove(self.audio_monitor)
#            self.audio_monitor = None
            
        # Shrink window back
        current_width, current_height = self.get_size()
        self.resize(current_width, current_height - 100)


    def on_monitor_window_closed(self, widget):
        """Handle monitor window being closed by user"""
        if self.audio_monitor:
            self.audio_monitor.stop()
            self.audio_monitor.cleanup()
            self.audio_monitor = None
        
        self.monitor_window = None
        self.monitor_visible = False
        
        # Update button label (find the button in bottom_box)
        # Use idle_add to safely update UI
        GLib.idle_add(self.reset_monitor_button_label)

    def close_monitor_window(self):
        """Close the monitor window and clean up"""
        if self.audio_monitor:
            self.audio_monitor.stop()
            self.audio_monitor.cleanup()
            self.audio_monitor = None
        
        if self.monitor_window:
            self.monitor_window.destroy()
            self.monitor_window = None
        
        self.monitor_visible = False


    def on_monitor_stopped_unexpectedly(self):
        """Handle monitor stopping unexpectedly"""
        with self.state_lock:
            if self.shutdown_flag:
                return
            
            self.is_connected = False
            self.monitor_process = None
            self.status_circle.set_markup('<span font="24">🔴</span>')
            self.status_label.set_markup("<b>Monitor Stopped</b>")
            self.connect_button.set_sensitive(True)
            self.disconnect_button.set_sensitive(True)
            self.set_volume_controls_sensitive(False)
        
        self.show_error_dialog("Monitor stopped unexpectedly. You may need to disconnect and reconnect.")
    
    def on_connect_clicked(self, button):
        """Start connection process"""
        if self.is_connecting:
            return
        
        with self.state_lock:
            self.is_connecting = True
            self.shutdown_flag = False
        
        self.connect_button.set_sensitive(False)
        self.status_circle.set_markup('<span font="24">🟡</span>')
        self.status_label.set_markup("<b>Connecting...</b>")
        
        self.monitor_thread = threading.Thread(target=self.connect_thread, daemon=True)
        self.monitor_thread.start()
    
    def disconnect_thread(self):
        """Thread to stop monitor and delete mixer"""
        script_path = self.get_script_path()
        if not script_path:
            GLib.idle_add(self.show_error_dialog, "Script not found")
            GLib.idle_add(self.finish_disconnection, False)
            return
        
        try:
            with self.state_lock:
                self.shutdown_flag = True
            
            # Kill monitor process tree
            if self.monitor_process:
                try:
                    self.kill_process_tree(self.monitor_process.pid)
                    self.monitor_process.wait(timeout=2)
                except:
                    pass
                
                with self.state_lock:
                    self.monitor_process = None
            
            # Wait for thread
            if self.monitor_thread and self.monitor_thread.is_alive():
                self.monitor_thread.join(timeout=2)
            
            # Delete mixer
            result = subprocess.run(
                ["bash", script_path, "delete"],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            success = result.returncode == 0
            GLib.idle_add(self.finish_disconnection, success)
            
        except Exception as e:
            GLib.idle_add(self.show_error_dialog, f"Disconnection error: {e}")
            GLib.idle_add(self.finish_disconnection, False)
    
    def finish_disconnection(self, success):
        """Finish disconnection process and update UI"""
        with self.state_lock:
            self.is_connecting = False
            self.shutdown_flag = False
            
            if success:
                self.is_connected = False
                self.status_circle.set_markup('<span font="24">⚪</span>')
                self.status_label.set_markup("<b>Disconnected</b>")
                self.connect_button.set_sensitive(True)
                self.disconnect_button.set_sensitive(False)
                self.set_volume_controls_sensitive(False)
                if self.monitor_visible and self.audio_monitor:
                    monitor = AudioMonitor()
                    default = monitor.get_default_sink_monitor()
                    if default:
                        self.audio_monitor.set_source(default)                
            else:
                self.status_circle.set_markup('<span font="24">🔴</span>')
                self.status_label.set_markup("<b>Error</b>")
                self.disconnect_button.set_sensitive(True)
    
    def on_disconnect_clicked(self, button):
        """Start disconnection process"""
        if self.is_connecting:
            return
        
        with self.state_lock:
            self.is_connecting = True
        
        self.disconnect_button.set_sensitive(False)
        self.status_circle.set_markup('<span font="24">🟡</span>')
        self.status_label.set_markup("<b>Disconnecting...</b>")
        
        thread = threading.Thread(target=self.disconnect_thread, daemon=True)
        thread.start()
    
    def on_advanced_clicked(self, button):
        """Open advanced mode GUI"""
        advanced_path = self.get_advanced_script_path()
        if not advanced_path:
            self.show_error_dialog("Advanced mode script (outputs-to-inputs-adv.py) not found")
            return
        
        try:
            # Launch with new session to detach from parent
            proc = subprocess.Popen(
                ["python3", advanced_path],
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            
            # Track but don't wait for it
            with self.state_lock:
                self.launched_processes.append(proc)
            
            # Clean up this GUI
            self.cleanup()
            Gtk.main_quit()
            
        except Exception as e:
            self.show_error_dialog(f"Failed to open advanced mode: {e}")
    
    def on_legacy_clicked(self, button):
        """Open legacy audioshare app"""
        legacy_path = self.get_legacy_script_path()
        if not legacy_path:
            self.show_error_dialog("Legacy app script not found\n\nLooking for: audioshare.sh, audioshare.py, or audioshare")
            return
        
        try:
            # Detect file type
            cmd = None
            if legacy_path.endswith('.py'):
                cmd = ["python3", legacy_path]
            elif legacy_path.endswith('.sh'):
                with open(legacy_path, 'r') as f:
                    first_line = f.readline().strip()
                
                if 'python' in first_line or 'import' in first_line:
                    cmd = ["python3", legacy_path]
                else:
                    cmd = ["bash", legacy_path]
            else:
                with open(legacy_path, 'r') as f:
                    first_line = f.readline().strip()
                
                if 'python' in first_line:
                    cmd = ["python3", legacy_path]
                else:
                    cmd = [legacy_path]
            
            # Launch with new session
            proc = subprocess.Popen(
                cmd,
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            
            with self.state_lock:
                self.launched_processes.append(proc)
            
            self.cleanup()
            Gtk.main_quit()
            
        except Exception as e:
            self.show_error_dialog(f"Failed to open legacy app: {e}")
    
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
        with self.state_lock:
            self.shutdown_flag = True
        
        self.close_monitor_window()
        

        # Kill monitor process tree
        if self.monitor_process:
            try:
                self.kill_process_tree(self.monitor_process.pid)
            except:
                pass
        
        # Wait for monitor thread
        if self.monitor_thread and self.monitor_thread.is_alive():
            self.monitor_thread.join(timeout=1)
        

        # Note: We DON'T clean up launched_processes here
        # because those are meant to stay running
    
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
