#!/usr/bin/env python3
"""
Audio Output-to-Input Connection GUI (Advanced)
GTK interface for managing the virtual audio mixer with volume control
ADDED: Advanced Microphone Guard (Source selection, Custom Target Volume, Interval)
"""

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib, Pango
import subprocess
import threading
import os
import signal
import re
import sys

# Set application ID to match desktop file
GLib.set_prgname("com.audioshare.AudioConnectionManager")
GLib.set_application_name("Audio Sharing Control")

class AudioMixerGUI(Gtk.Window):
    def __init__(self):
        super().__init__(title="Audio Mixer Manager (Advanced)")

        self.set_icon_name("com.audioshare.AudioConnectionManager")
        
        # Increased height for new controls
        self.set_default_size(650, 750)
        self.set_border_width(10)
        self.set_resizable(False)
        
        # State variables
        self.monitor_process = None
        self.is_monitoring = False
        self.mixer_exists = False
        self.step_percentage = 20
        self.is_muted = False
        self.graph_process = None
        
        # Mic Guard State
        self.mic_guard_active = False
        self.mic_guard_timer = None
        
        # Main container
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)
        
        # --- Header ---
        header_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        vbox.pack_start(header_box, False, False, 0)
        
        self.back_button = Gtk.Button(label="← Back")
        self.back_button.set_tooltip_text("Return to Main Menu")
        self.back_button.connect("clicked", self.on_back_clicked)
        header_box.pack_start(self.back_button, False, False, 0)
        
        header_box.pack_start(Gtk.Label(), True, True, 0)
        title_label = Gtk.Label()
        title_label.set_markup("<big><b>Virtual Audio Mixer Manager</b></big>")
        header_box.pack_start(title_label, False, False, 0)
        header_box.pack_start(Gtk.Label(), True, True, 0)
        
        placeholder = Gtk.Label()
        placeholder.set_size_request(70, -1)
        header_box.pack_start(placeholder, False, False, 0)
        
        # --- Status Frame ---
        status_frame = Gtk.Frame(label="Status")
        status_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5)
        status_box.set_border_width(10)
        status_frame.add(status_box)
        vbox.pack_start(status_frame, False, False, 0)
        
        self.mixer_status_label = Gtk.Label()
        self.mixer_status_label.set_halign(Gtk.Align.START)
        status_box.pack_start(self.mixer_status_label, False, False, 0)
        
        self.monitor_status_label = Gtk.Label()
        self.monitor_status_label.set_halign(Gtk.Align.START)
        status_box.pack_start(self.monitor_status_label, False, False, 0)
        
        # --- Mixer Volume Control ---
        volume_frame = Gtk.Frame(label="Virtual Mixer Volume")
        volume_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        volume_box.set_border_width(15)
        volume_frame.add(volume_box)
        vbox.pack_start(volume_frame, False, False, 0)
        
        button_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        button_box.set_homogeneous(True)
        
        self.volume_up_button = Gtk.Button(label="🔊 Volume Up")
        self.volume_up_button.connect("clicked", self.on_volume_up)
        button_box.pack_start(self.volume_up_button, True, True, 0)
        
        self.volume_down_button = Gtk.Button(label="🔉 Volume Down")
        self.volume_down_button.connect("clicked", self.on_volume_down)
        button_box.pack_start(self.volume_down_button, True, True, 0)
        
        volume_box.pack_start(button_box, False, False, 0)
        
        mute_graph_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        mute_graph_box.set_homogeneous(True)
        
        self.mute_button = Gtk.Button(label="🔇 Mute Mixer")
        self.mute_button.connect("clicked", self.on_toggle_mute)
        mute_graph_box.pack_start(self.mute_button, True, True, 0)
        
        self.graph_button = Gtk.Button(label="📊 Waveform Monitor")
        self.graph_button.connect("clicked", self.on_open_graph)
        mute_graph_box.pack_start(self.graph_button, True, True, 0)
        
        volume_box.pack_start(mute_graph_box, False, False, 0)
        
        # Mixer Step config
        step_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        step_label = Gtk.Label(label="Step (%):")
        step_box.pack_start(step_label, False, False, 0)
        self.step_entry = Gtk.Entry()
        self.step_entry.set_text(str(self.step_percentage))
        self.step_entry.set_width_chars(5)
        step_box.pack_start(self.step_entry, False, False, 0)
        apply_button = Gtk.Button(label="Apply")
        apply_button.connect("clicked", self.on_update_step)
        step_box.pack_start(apply_button, False, False, 0)
        self.volume_status_label = Gtk.Label(label="Ready")
        step_box.pack_start(self.volume_status_label, True, True, 0) # Fill rest
        volume_box.pack_start(step_box, False, False, 0)
        
        # --- Advanced Microphone Guard Frame (NEW) ---
        mic_frame = Gtk.Frame(label="Advanced Microphone Guard")
        mic_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        mic_box.set_border_width(15)
        mic_frame.add(mic_box)
        vbox.pack_start(mic_frame, False, False, 0)
        
        # Row 1: Source Selection
        mic_sel_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        mic_box.pack_start(mic_sel_box, False, False, 0)
        
        mic_label = Gtk.Label(label="Target Mic:")
        mic_sel_box.pack_start(mic_label, False, False, 0)
        
        self.mic_combo = Gtk.ComboBoxText()
        self.mic_combo.set_hexpand(True)
        mic_sel_box.pack_start(self.mic_combo, True, True, 0)
        
        mic_refresh_btn = Gtk.Button(label="🔄")
        mic_refresh_btn.set_tooltip_text("Refresh Device List")
        mic_refresh_btn.connect("clicked", self.on_refresh_mics)
        mic_sel_box.pack_start(mic_refresh_btn, False, False, 0)
        
        # Row 2: Target Volume Slider
        mic_vol_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        mic_box.pack_start(mic_vol_box, False, False, 0)
        
        vol_label = Gtk.Label(label="Lock Volume:")
        mic_vol_box.pack_start(vol_label, False, False, 0)
        
        self.mic_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 150, 1)
        self.mic_scale.set_value(100)
        self.mic_scale.set_hexpand(True)
        self.mic_scale.add_mark(100, Gtk.PositionType.BOTTOM, "100%")
        self.mic_scale.add_mark(0, Gtk.PositionType.BOTTOM, "Mute")
        mic_vol_box.pack_start(self.mic_scale, True, True, 0)
        
        self.mic_vol_value_label = Gtk.Label(label="100%")
        self.mic_scale.connect("value-changed", self.on_mic_slider_changed)
        mic_vol_box.pack_start(self.mic_vol_value_label, False, False, 0)
        
        # Row 3: Interval and Activation
        mic_ctrl_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=15)
        mic_box.pack_start(mic_ctrl_box, False, False, 0)
        
        # Interval Spinner
        int_label = Gtk.Label(label="Check Interval (sec):")
        mic_ctrl_box.pack_start(int_label, False, False, 0)
        
        adj = Gtk.Adjustment(value=2, lower=1, upper=60, step_increment=1, page_increment=5)
        self.mic_interval_spin = Gtk.SpinButton(adjustment=adj)
        mic_ctrl_box.pack_start(self.mic_interval_spin, False, False, 0)
        
        # Activation Switch
        self.mic_switch = Gtk.Switch()
        self.mic_switch.connect("state-set", self.on_mic_guard_toggled)
        self.mic_switch.set_valign(Gtk.Align.CENTER)
        
        switch_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        switch_box.pack_end(self.mic_switch, False, False, 0)
        switch_box.pack_end(Gtk.Label(label="<b>Enable Guard:</b>", use_markup=True), False, False, 0)
        mic_ctrl_box.pack_end(switch_box, False, False, 0)
        
        self.mic_status_label = Gtk.Label(label="<i>Inactive</i>")
        self.mic_status_label.set_use_markup(True)
        self.mic_status_label.set_halign(Gtk.Align.END)
        mic_box.pack_start(self.mic_status_label, False, False, 0)

        # --- Main Controls ---
        control_frame = Gtk.Frame(label="Mixer Controls")
        control_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        control_box.set_border_width(10)
        control_frame.add(control_box)
        vbox.pack_start(control_frame, False, False, 0)
        
        self.create_button = Gtk.Button(label="Create Virtual Mixer")
        self.create_button.connect("clicked", self.on_create_clicked)
        control_box.pack_start(self.create_button, False, False, 0)
        
        monitor_hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        control_box.pack_start(monitor_hbox, False, False, 0)
        
        self.start_button = Gtk.Button(label="Start Auto-Connect")
        self.start_button.connect("clicked", self.on_start_clicked)
        monitor_hbox.pack_start(self.start_button, True, True, 0)
        
        self.stop_button = Gtk.Button(label="Stop Monitor")
        self.stop_button.connect("clicked", self.on_stop_clicked)
        self.stop_button.set_sensitive(False)
        monitor_hbox.pack_start(self.stop_button, True, True, 0)
        
        self.delete_button = Gtk.Button(label="Delete Virtual Mixer")
        self.delete_button.connect("clicked", self.on_delete_clicked)
        control_box.pack_start(self.delete_button, False, False, 0)
        
        # --- Log ---
        log_frame = Gtk.Frame(label="Activity Log")
        vbox.pack_start(log_frame, True, True, 0)
        
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        log_frame.add(scrolled)
        
        self.log_view = Gtk.TextView()
        self.log_view.set_editable(False)
        self.log_view.set_wrap_mode(Gtk.WrapMode.WORD)
        self.log_buffer = self.log_view.get_buffer()
        scrolled.add(self.log_view)
        
        # --- Footer ---
        bottom_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        vbox.pack_start(bottom_box, False, False, 0)
        
        clear_button = Gtk.Button(label="Clear Log")
        clear_button.connect("clicked", self.on_clear_log)
        bottom_box.pack_start(clear_button, False, False, 0)
        
        quit_button = Gtk.Button(label="Quit")
        quit_button.connect("clicked", self.on_quit_clicked)
        bottom_box.pack_end(quit_button, False, False, 0)
        
        # Initialization
        self.set_volume_controls_sensitive(False)
        self.check_mixer_status()
        self.update_status_display()
        self.load_microphone_sources()
        
        if self.mixer_exists:
            self.update_mute_state_from_system()
        
        self.connect("destroy", self.on_window_destroy)
        self.log_message("Advanced Audio Manager ready.")

    # ==========================================
    # MIC GUARD LOGIC
    # ==========================================

    def load_microphone_sources(self):
        """Populate combobox with input sources (excluding monitors)"""
        self.mic_combo.remove_all()
        try:
            # Use 'pactl list sources short' to get ID and Name
            result = subprocess.run(['pactl', 'list', 'sources', 'short'], 
                                  capture_output=True, text=True)
            
            # Default option
            self.mic_combo.append("@DEFAULT_SOURCE@", "System Default Microphone")
            
            for line in result.stdout.strip().split('\n'):
                if not line: continue
                parts = line.split('\t')
                if len(parts) >= 2:
                    name = parts[1]
                    # Filter out monitor sources (usually output monitors)
                    if not name.endswith(".monitor"):
                        # Try to get a nicer description via pactl list sources
                        desc = self.get_source_description(name)
                        display_text = f"{desc} ({name})" if desc != name else name
                        self.mic_combo.append(name, display_text)
            
            self.mic_combo.set_active_id("@DEFAULT_SOURCE@")
            
        except Exception as e:
            self.log_message(f"Error loading mics: {e}")
            self.mic_combo.append("@DEFAULT_SOURCE@", "Default (Error loading list)")
            self.mic_combo.set_active(0)

    def get_source_description(self, source_name):
        """Helper to find description for a specific source"""
        try:
            # This is expensive, so we only do it on refresh
            res = subprocess.run(['pactl', 'list', 'sources'], capture_output=True, text=True)
            current_name = None
            for line in res.stdout.split('\n'):
                line = line.strip()
                if line.startswith("Name:"):
                    current_name = line.split(":", 1)[1].strip()
                elif line.startswith("Description:") and current_name == source_name:
                    return line.split(":", 1)[1].strip()
            return source_name
        except:
            return source_name

    def on_refresh_mics(self, button):
        self.load_microphone_sources()
        self.log_message("Refreshed microphone list")

    def on_mic_slider_changed(self, scale):
        val = int(scale.get_value())
        self.mic_vol_value_label.set_text(f"{val}%")

    def on_mic_guard_toggled(self, switch, state):
        self.mic_guard_active = state
        
        if state:
            # Validate selection
            target_mic = self.mic_combo.get_active_id()
            if not target_mic:
                self.log_message("Error: No microphone selected")
                switch.set_active(False)
                return False

            interval = int(self.mic_interval_spin.get_value()) * 1000
            target_vol = int(self.mic_scale.get_value())
            
            self.log_message(f"GUARD ACTIVE: Locking {target_mic} to {target_vol}% every {interval/1000}s")
            self.mic_status_label.set_markup(f'<span foreground="green"><b>GUARD ACTIVE</b> ({target_vol}%)</span>')
            
            # Disable controls while active to prevent confusion
            self.mic_combo.set_sensitive(False)
            self.mic_interval_spin.set_sensitive(False)
            
            # Start timer
            if self.mic_guard_timer:
                GLib.source_remove(self.mic_guard_timer)
            self.mic_guard_timer = GLib.timeout_add(interval, self.enforce_mic_state)
            
            # Run once immediately
            self.enforce_mic_state()
        else:
            self.log_message("Mic Guard Deactivated")
            self.mic_status_label.set_markup('<i>Inactive</i>')
            
            if self.mic_guard_timer:
                GLib.source_remove(self.mic_guard_timer)
                self.mic_guard_timer = None
            
            # Re-enable controls
            self.mic_combo.set_sensitive(True)
            self.mic_interval_spin.set_sensitive(True)

    def enforce_mic_state(self):
        """The timer callback to force volume"""
        if not self.mic_guard_active:
            return False # Stop timer
        
        target_mic = self.mic_combo.get_active_id()
        target_vol = int(self.mic_scale.get_value())
        
        try:
            # Unmute
            subprocess.run(
                ["pactl", "set-source-mute", target_mic, "0"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            # Set Volume
            subprocess.run(
                ["pactl", "set-source-volume", target_mic, f"{target_vol}%"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        except Exception as e:
            print(f"Guard Error: {e}")
            
        return True # Continue timer

    # ==========================================
    # STANDARD MIXER LOGIC (Legacy functionality)
    # ==========================================

    def get_main_script_path(self):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        main_script = os.path.join(script_dir, "outputs-to-inputs.py")
        if not os.path.exists(main_script): return None
        return main_script
    
    def on_back_clicked(self, button):
        main_script = self.get_main_script_path()
        if not main_script:
            self.show_error_dialog("Main script not found!")
            return
        
        # Stop guard before leaving
        if self.mic_guard_timer:
            GLib.source_remove(self.mic_guard_timer)
        
        try:
            subprocess.Popen(["python3", main_script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            GLib.timeout_add(100, self.close_window)
        except Exception as e:
            self.show_error_dialog(f"Failed to launch main script: {e}")
    
    def close_window(self):
        self.cleanup()
        self.destroy()
        Gtk.main_quit()
        return False
    
    def get_script_path(self):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        script_path = os.path.join(script_dir, "connect-outputs-to-inputs.sh")
        if not os.path.exists(script_path): return None
        return script_path
    
    def get_graph_script_path(self):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        script_path = os.path.join(script_dir, "graph.sh")
        if not os.path.exists(script_path): return None
        return script_path
    
    def on_open_graph(self, button):
        if self.graph_process and self.graph_process.poll() is None:
            self.log_message("Waveform monitor is already open")
            return
        
        graph_path = self.get_graph_script_path()
        if not graph_path:
            self.show_error_dialog("graph.sh not found")
            return
        
        # Check if mixer exists
        if not self.mixer_exists:
            self.show_mixer_warning_dialog(graph_path)
            return
        
        try:
            self.log_message("Opening waveform monitor...")
            self.graph_process = subprocess.Popen(
                ["python3", graph_path, "--device", "AudioMixer_Virtual.monitor"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        except Exception as e:
            self.show_error_dialog(f"Failed: {e}")
    
    def show_mixer_warning_dialog(self, graph_path):
        dialog = Gtk.MessageDialog(
            transient_for=self, flags=0, message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.NONE, text="Audio Mixer Not Created"
        )
        dialog.format_secondary_text("Open monitor without the virtual mixer device?")
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        dialog.add_button("Open Default", Gtk.ResponseType.YES)
        response = dialog.run()
        dialog.destroy()
        
        if response == Gtk.ResponseType.YES:
            subprocess.Popen(["python3", graph_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    def check_mixer_status(self):
        try:
            result = subprocess.run(["pactl", "list", "sinks", "short"], capture_output=True, text=True, timeout=5)
            self.mixer_exists = "AudioMixer_Virtual" in result.stdout
        except:
            self.mixer_exists = False
    
    def get_mute_state(self):
        try:
            result = subprocess.run(["pactl", "list", "sinks"], capture_output=True, text=True, timeout=5)
            lines = result.stdout.split('\n')
            in_mixer_sink = False
            for line in lines:
                if "AudioMixer_Virtual" in line: in_mixer_sink = True
                elif in_mixer_sink and "Mute:" in line: return "yes" in line.lower()
                elif in_mixer_sink and ("Sink #" in line or "Source #" in line): break
            return False
        except:
            return False
    
    def update_mute_state_from_system(self):
        if not self.mixer_exists: return
        muted = self.get_mute_state()
        self.mute_button.handler_block_by_func(self.on_toggle_mute)
        self.is_muted = muted
        if muted:
            self.mute_button.set_label("🔊 Unmute Mixer")
            self.volume_status_label.set_markup('<span foreground="orange">Muted</span>')
        else:
            self.mute_button.set_label("🔇 Mute Mixer")
            self.volume_status_label.set_markup('<span foreground="green">Ready</span>')
        self.mute_button.handler_unblock_by_func(self.on_toggle_mute)
    
    def set_volume_controls_sensitive(self, sensitive):
        self.volume_up_button.set_sensitive(sensitive)
        self.volume_down_button.set_sensitive(sensitive)
        self.mute_button.set_sensitive(sensitive)
        self.step_entry.set_sensitive(sensitive)
        self.graph_button.set_sensitive(sensitive)
    
    def on_volume_up(self, button):
        if not self.mixer_exists: return
        try:
            subprocess.run(["pactl", "set-sink-volume", "AudioMixer_Virtual", f"+{self.step_percentage}%"], check=True)
            self.log_message(f"Mixer Vol +{self.step_percentage}%")
            if self.is_muted:
                self.is_muted = False
                self.mute_button.set_label("🔇 Mute Mixer")
        except Exception as e:
            self.log_message(f"Error: {e}")
    
    def on_volume_down(self, button):
        if not self.mixer_exists: return
        try:
            subprocess.run(["pactl", "set-sink-volume", "AudioMixer_Virtual", f"-{self.step_percentage}%"], check=True)
            self.log_message(f"Mixer Vol -{self.step_percentage}%")
        except Exception as e:
            self.log_message(f"Error: {e}")
    
    def on_toggle_mute(self, button):
        if not self.mixer_exists: return
        try:
            mute_val = '0' if self.is_muted else '1'
            subprocess.run(["pactl", "set-sink-mute", "AudioMixer_Virtual", mute_val], check=True)
            self.is_muted = not self.is_muted
            if self.is_muted:
                self.mute_button.set_label("🔊 Unmute Mixer")
                self.log_message("Mixer Muted")
            else:
                self.mute_button.set_label("🔇 Mute Mixer")
                self.log_message("Mixer Unmuted")
        except Exception as e:
            self.log_message(f"Error: {e}")
    
    def on_update_step(self, button):
        try:
            new = int(self.step_entry.get_text())
            if 1 <= new <= 100:
                self.step_percentage = new
                self.log_message(f"Step updated: {new}%")
            else:
                raise ValueError
        except:
            self.step_entry.set_text(str(self.step_percentage))
    
    def show_error_dialog(self, message):
        dialog = Gtk.MessageDialog(transient_for=self, flags=0, message_type=Gtk.MessageType.ERROR, buttons=Gtk.ButtonsType.OK, text="Error")
        dialog.format_secondary_text(message)
        dialog.run()
        dialog.destroy()
    
    def update_status_display(self):
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
            self.monitor_status_label.set_markup("🟢 <b>Auto-Connect:</b> Running")
            self.start_button.set_sensitive(False)
            self.stop_button.set_sensitive(True)
        else:
            self.monitor_status_label.set_markup("⚪ <b>Auto-Connect:</b> Stopped")
            self.start_button.set_sensitive(self.mixer_exists)
            self.stop_button.set_sensitive(False)
    
    def log_message(self, message):
        end = self.log_buffer.get_end_iter()
        self.log_buffer.insert(end, message + "\n")
        mark = self.log_buffer.create_mark(None, end, False)
        self.log_view.scroll_mark_onscreen(mark)
    
    def run_command(self, command, success_msg, error_msg):
        script_path = self.get_script_path()
        if not script_path: return False
        try:
            self.log_message(f"Cmd: {command}")
            res = subprocess.run(["bash", script_path, command], capture_output=True, text=True, timeout=10)
            if res.returncode == 0:
                self.log_message(success_msg)
                return True
            else:
                self.log_message(error_msg)
                return False
        except Exception as e:
            self.log_message(f"Error: {e}")
            return False
    
    def on_create_clicked(self, button):
        if self.run_command("create", "Mixer Created", "Failed"):
            self.mixer_exists = True
            self.update_status_display()
            GLib.timeout_add(500, self.update_mute_state_from_system)
    
    def monitor_thread(self):
        script_path = self.get_script_path()
        if not script_path: return
        try:
            GLib.idle_add(self.log_message, "Starting Monitor...")
            self.monitor_process = subprocess.Popen(["bash", script_path, "monitor"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
            for line in self.monitor_process.stdout:
                if line.strip(): GLib.idle_add(self.log_message, line.rstrip())
            self.monitor_process.wait()
        except Exception as e:
            GLib.idle_add(self.log_message, f"Monitor Error: {e}")
        finally:
            self.monitor_process = None
            self.is_monitoring = False
            GLib.idle_add(self.update_status_display)
    
    def on_start_clicked(self, button):
        if not self.mixer_exists:
            self.log_message("Create mixer first!")
            return
        self.is_monitoring = True
        self.update_status_display()
        threading.Thread(target=self.monitor_thread, daemon=True).start()
    
    def on_stop_clicked(self, button):
        if self.monitor_process:
            self.log_message("Stopping monitor...")
            try:
                self.monitor_process.send_signal(signal.SIGINT)
            except:
                pass
        self.is_monitoring = False
        self.update_status_display()
    
    def on_delete_clicked(self, button):
        if self.is_monitoring:
            self.log_message("Stop monitor first!")
            return
        if self.run_command("delete", "Mixer Deleted", "Failed"):
            self.mixer_exists = False
            self.update_status_display()
    
    def on_clear_log(self, button):
        self.log_buffer.set_text("")
    
    def on_quit_clicked(self, button):
        self.cleanup()
        Gtk.main_quit()
    
    def on_window_destroy(self, widget):
        self.cleanup()
        Gtk.main_quit()
    
    def cleanup(self):
        if self.mic_guard_timer:
            GLib.source_remove(self.mic_guard_timer)
        if self.monitor_process:
            try:
                self.monitor_process.send_signal(signal.SIGINT)
                self.monitor_process.wait(timeout=2)
            except:
                try: self.monitor_process.kill()
                except: pass

def main():
    missing = []
    for cmd in ["pactl", "pw-link", "pw-dump", "jq"]:
        if subprocess.run(["which", cmd], capture_output=True).returncode != 0: missing.append(cmd)
    
    if missing:
        dialog = Gtk.MessageDialog(message_type=Gtk.MessageType.ERROR, buttons=Gtk.ButtonsType.OK, text="Missing Dependencies")
        dialog.format_secondary_text(f"Install: {', '.join(missing)}")
        dialog.run()
        dialog.destroy()
        return
    
    win = AudioMixerGUI()
    win.show_all()
    Gtk.main()

if __name__ == "__main__":
    main()