#!/usr/bin/env python3
"""
Audio Connection Manager (Fixed Size + Clean Exit)
- Default: Compact View
- Behavior: Sticky, Always on Top, Fixed Size
- Features: Instant terminal termination on close
"""

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib, Pango
import subprocess
import threading
import os
import signal
import sys

# Allow Ctrl+C to kill the app from terminal immediately
signal.signal(signal.SIGINT, signal.SIG_DFL)

# Set application ID
GLib.set_prgname("com.audioshare.AudioConnectionManager")
GLib.set_application_name("Audio Sharing Control")

# ==========================================
# BASE LOGIC CLASS
# ==========================================
class AudioMixerBase(Gtk.Window):
    """
    Base class containing shared logic, state management, 
    and proper cleanup routines.
    """
    def __init__(self, title):
        super().__init__(title=title)
        self.set_icon_name("com.audioshare.AudioConnectionManager")
        
        # --- STICKY WINDOW SETTINGS ---
        self.stick()
        self.set_keep_above(True)
        
        # Shared State
        self.monitor_process = None
        self.is_monitoring = False
        self.mixer_exists = False
        self.step_percentage = 20
        self.is_muted = False
        self.graph_process = None
        
        # Guard State
        self.mic_guard_active = False
        self.mic_guard_timer = None
        self.mixer_guard_active = False
        self.mixer_guard_timer = None

        self.switching_mode = False 
        self.script_dir = os.path.dirname(os.path.abspath(__file__))

    def get_script_path(self, script_name):
        p = os.path.join(self.script_dir, script_name)
        return p if os.path.exists(p) else None

    # --- STATE TRANSFER ---
    def transfer_state_from(self, old_window):
        self.is_monitoring = old_window.is_monitoring
        self.mixer_exists = old_window.mixer_exists
        self.step_percentage = old_window.step_percentage
        self.is_muted = old_window.is_muted
        self.mic_guard_active = old_window.mic_guard_active
        self.mixer_guard_active = old_window.mixer_guard_active
        
        if self.is_monitoring:
            threading.Thread(target=self.monitor_thread, daemon=True).start()
            
        if self.mixer_guard_active:
            GLib.idle_add(self.restore_mixer_guard)

        if self.mic_guard_active:
             GLib.idle_add(self.restore_mic_guard)

    def restore_mixer_guard(self):
        self.mixer_guard_switch.set_active(True)
        self.on_mixer_guard_toggled(self.mixer_guard_switch, True)

    def restore_mic_guard(self):
        self.mic_switch.set_active(True)
        self.on_mic_guard_toggled(self.mic_switch, True)

    # --- CLEANUP & EXIT ---
    def on_window_destroy(self, widget):
        """
        Triggered when the window is closed (X button).
        Forces the application and terminal process to end.
        """
        self.cleanup()
        
        if self.switching_mode:
            return # Don't exit if we are just switching views
            
        Gtk.main_quit()
        sys.exit(0) # <--- CRITICAL: Forces terminal process to close immediately

    def cleanup(self):
        if self.mic_guard_timer:
            GLib.source_remove(self.mic_guard_timer)
            self.mic_guard_timer = None
        if self.mixer_guard_timer:
            GLib.source_remove(self.mixer_guard_timer)
            self.mixer_guard_timer = None
            
        if self.monitor_process:
            try:
                self.monitor_process.send_signal(signal.SIGINT)
                self.monitor_process.wait(timeout=0.5)
            except:
                try: self.monitor_process.kill()
                except: pass
            self.monitor_process = None
            
        if self.graph_process:
            try: self.graph_process.terminate()
            except: pass
            self.graph_process = None

    def switch_window(self, TargetClass):
        self.switching_mode = True
        new_win = TargetClass(state_source=self)
        new_win.show_all()
        self.destroy()

    # --- LOGIC ---
    def run_command(self, cmd, success_msg=None, error_msg=None):
        s = self.get_script_path("connect-outputs-to-inputs.sh")
        if not s: return False
        try:
            if subprocess.run(["bash", s, cmd]).returncode == 0:
                if success_msg: self.log_message(success_msg)
                return True
            else:
                if error_msg: self.log_message(error_msg)
                return False
        except Exception as e:
            self.log_message(f"Error: {e}")
            return False

    def monitor_thread(self):
        s = self.get_script_path("connect-outputs-to-inputs.sh")
        try:
            self.log_message("Starting Monitor...")
            self.monitor_process = subprocess.Popen(["bash", s, "monitor"], stdout=subprocess.PIPE, text=True, bufsize=1)
            for line in self.monitor_process.stdout:
                if line.strip(): GLib.idle_add(self.log_message, line.strip())
        except Exception as e:
            GLib.idle_add(self.log_message, f"Error: {e}")
        finally:
            self.monitor_process = None
            if not self.switching_mode:
                self.is_monitoring = False
                GLib.idle_add(self.update_status_display)

    def on_create_clicked(self, b):
        if self.run_command("create", "Mixer Created", "Failed"):
            self.mixer_exists = True
            self.update_status_display()
            self.update_mute_ui()

    def on_delete_clicked(self, b):
        if self.is_monitoring:
            self.log_message("Stop monitor first!")
            return
        if self.run_command("delete", "Mixer Deleted", "Failed"):
            self.mixer_exists = False
            self.update_status_display()

    def on_start_clicked(self, b):
        self.is_monitoring = True
        self.update_status_display()
        threading.Thread(target=self.monitor_thread, daemon=True).start()

    def on_stop_clicked(self, b):
        if self.monitor_process:
            self.monitor_process.send_signal(signal.SIGINT)
        self.is_monitoring = False
        self.update_status_display()

    def on_open_graph(self, b):
        graph_script = self.get_script_path("graph.sh")
        if not graph_script:
            self.log_message("Error: graph.sh not found")
            return
        if not self.mixer_exists:
            dialog = Gtk.MessageDialog(transient_for=self, flags=0, message_type=Gtk.MessageType.WARNING, buttons=Gtk.ButtonsType.NONE, text="Mixer Not Found")
            dialog.format_secondary_text("Open graph anyway? (Manual device selection required)")
            dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
            dialog.add_button("Open", Gtk.ResponseType.YES)
            if dialog.run() != Gtk.ResponseType.YES:
                dialog.destroy(); return
            dialog.destroy()
            self.graph_process = subprocess.Popen(["python3", graph_script], stdout=subprocess.DEVNULL)
        else:
            self.graph_process = subprocess.Popen(["python3", graph_script, "--device", "AudioMixer_Virtual.monitor"], stdout=subprocess.DEVNULL)

    def on_back_clicked(self, b):
        main = self.get_script_path("outputs-to-inputs.py")
        self.cleanup()
        if main: subprocess.Popen(["python3", main], stdout=subprocess.DEVNULL)
        Gtk.main_quit()
        sys.exit(0)

    def on_volume_up(self, b):
        if self.mixer_exists: subprocess.run(["pactl", "set-sink-volume", "AudioMixer_Virtual", f"+{self.step_percentage}%"])
    def on_volume_down(self, b):
        if self.mixer_exists: subprocess.run(["pactl", "set-sink-volume", "AudioMixer_Virtual", f"-{self.step_percentage}%"])
    def on_toggle_mute(self, b):
        if not self.mixer_exists: return
        self.is_muted = not self.is_muted
        val = '1' if self.is_muted else '0'
        subprocess.run(["pactl", "set-sink-mute", "AudioMixer_Virtual", val])
        self.update_mute_ui()
    def on_update_step(self, entry):
        try: self.step_percentage = int(entry.get_text())
        except: pass

    def load_microphone_sources(self, combo):
        combo.remove_all()
        try:
            r = subprocess.run(['pactl', 'list', 'sources', 'short'], capture_output=True, text=True)
            combo.append("@DEFAULT_SOURCE@", "Default Mic")
            for line in r.stdout.strip().split('\n'):
                parts = line.split('\t')
                if len(parts) >= 2 and not parts[1].endswith(".monitor"):
                    combo.append(parts[1], parts[1])
            combo.set_active_id("@DEFAULT_SOURCE@")
        except:
            combo.append("0", "Error")
            combo.set_active(0)

    def on_mixer_guard_toggled(self, sw, state):
        self.mixer_guard_active = state
        if state:
            self.mixer_guard_timer = GLib.timeout_add(1500, self.enforce_mixer_state)
            self.enforce_mixer_state()
            self.set_volume_controls_sensitive(False)
            self.log_message("Mixer Guard ON")
        else:
            if self.mixer_guard_timer: GLib.source_remove(self.mixer_guard_timer)
            self.set_volume_controls_sensitive(True)
            self.log_message("Mixer Guard OFF")

    def enforce_mixer_state(self):
        if not self.mixer_guard_active or not self.mixer_exists: return False
        target = int(self.mixer_lock_scale.get_value())
        subprocess.run(["pactl", "set-sink-mute", "AudioMixer_Virtual", "0"], stderr=subprocess.DEVNULL)
        subprocess.run(["pactl", "set-sink-volume", "AudioMixer_Virtual", f"{target}%"], stderr=subprocess.DEVNULL)
        self.is_muted = False
        self.update_mute_ui()
        return True

    def on_mic_guard_toggled(self, sw, state):
        self.mic_guard_active = state
        if state:
            interval = int(self.mic_spin.get_value()) * 1000
            self.mic_guard_timer = GLib.timeout_add(interval, self.enforce_mic_state)
            self.enforce_mic_state()
            self.mic_combo.set_sensitive(False)
            self.log_message("Mic Guard ON")
        else:
            if self.mic_guard_timer: GLib.source_remove(self.mic_guard_timer)
            self.mic_combo.set_sensitive(True)
            self.log_message("Mic Guard OFF")

    def enforce_mic_state(self):
        if not self.mic_guard_active: return False
        mic = self.mic_combo.get_active_id()
        vol = int(self.mic_scale.get_value())
        if not mic: return True
        subprocess.run(["pactl", "set-source-mute", mic, "0"], stderr=subprocess.DEVNULL)
        subprocess.run(["pactl", "set-source-volume", mic, f"{vol}%"], stderr=subprocess.DEVNULL)
        return True

    def check_mixer_status(self):
        try:
            r = subprocess.run(["pactl", "list", "sinks", "short"], capture_output=True, text=True)
            self.mixer_exists = "AudioMixer_Virtual" in r.stdout
        except: self.mixer_exists = False

    def log_message(self, msg): pass
    def update_status_display(self): pass
    def update_mute_ui(self): pass
    def set_volume_controls_sensitive(self, s): pass


# ==========================================
# ADVANCED VIEW (Fixed Size, Scrollable)
# ==========================================
class AdvancedModeWindow(AudioMixerBase):
    def __init__(self, state_source=None):
        super().__init__("Audio Mixer Manager (Pro)")
        self.set_default_size(650, 850)
        self.set_size_request(550, 700)
        self.set_border_width(15)
        self.set_position(Gtk.WindowPosition.CENTER)
        # RESIZE DISABLED
        self.set_resizable(False) 
        self.connect("destroy", self.on_window_destroy)

        # Main Layout: Fixed Header + Scrollable Content
        main_layout = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(main_layout)

        # 1. FIXED HEADER
        hb = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        hb.set_border_width(10)
        main_layout.pack_start(hb, False, False, 0)
        
        back = Gtk.Button(label="← Back")
        back.connect("clicked", self.on_back_clicked)
        hb.pack_start(back, False, False, 0)
        
        hb.pack_start(Gtk.Label(), True, True, 0)
        hb.pack_start(Gtk.Label(label="<big><b>Virtual Mixer (Pro)</b></big>", use_markup=True), False, False, 0)
        hb.pack_start(Gtk.Label(), True, True, 0)
        
        switch = Gtk.Button(label="👁️ Compact")
        switch.connect("clicked", lambda b: self.switch_window(CompactModeWindow))
        hb.pack_start(switch, False, False, 0)

        # 2. SCROLLABLE BODY
        scrolled_window = Gtk.ScrolledWindow()
        scrolled_window.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        main_layout.pack_start(scrolled_window, True, True, 0)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=15)
        vbox.set_border_width(15)
        scrolled_window.add(vbox)

        # -- Status --
        stat_f = Gtk.Frame(label="Status")
        sb = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5)
        sb.set_border_width(10)
        stat_f.add(sb)
        vbox.pack_start(stat_f, False, False, 0)
        self.mixer_lbl = Gtk.Label(xalign=0)
        self.mon_lbl = Gtk.Label(xalign=0)
        sb.pack_start(self.mixer_lbl, False, False, 0)
        sb.pack_start(self.mon_lbl, False, False, 0)

        # -- Volume --
        vol_f = Gtk.Frame(label="Mixer Volume")
        vb = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        vb.set_border_width(15)
        vol_f.add(vb)
        vbox.pack_start(vol_f, False, False, 0)
        
        row1 = Gtk.Box(homogeneous=True, spacing=10)
        self.btn_up = Gtk.Button(label="🔊 Volume Up"); self.btn_up.connect("clicked", self.on_volume_up)
        self.btn_dn = Gtk.Button(label="🔉 Volume Down"); self.btn_dn.connect("clicked", self.on_volume_down)
        row1.pack_start(self.btn_up, True, True, 0); row1.pack_start(self.btn_dn, True, True, 0)
        vb.pack_start(row1, False, False, 0)
        
        row2 = Gtk.Box(homogeneous=True, spacing=10)
        self.btn_mute = Gtk.Button(label="🔇 Mute"); self.btn_mute.connect("clicked", self.on_toggle_mute)
        self.btn_graph = Gtk.Button(label="📊 Graph"); self.btn_graph.connect("clicked", self.on_open_graph)
        row2.pack_start(self.btn_mute, True, True, 0); row2.pack_start(self.btn_graph, True, True, 0)
        vb.pack_start(row2, False, False, 0)
        
        step_b = Gtk.Box(spacing=10)
        step_b.pack_start(Gtk.Label(label="Step (%):"), False, False, 0)
        self.step_entry = Gtk.Entry(text="20", width_chars=5)
        step_b.pack_start(self.step_entry, False, False, 0)
        apply = Gtk.Button(label="Apply"); apply.connect("clicked", self.on_update_step)
        step_b.pack_start(apply, False, False, 0)
        vb.pack_start(step_b, False, False, 0)

        vb.pack_start(Gtk.Separator(), False, False, 5)
        
        # Mixer Guard
        lb = Gtk.Box(spacing=10)
        lb.pack_start(Gtk.Label(label="<b>Lock Level:</b>", use_markup=True), False, False, 0)
        self.mixer_lock_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 150, 1)
        self.mixer_lock_scale.set_value(100); self.mixer_lock_scale.set_hexpand(True)
        self.mixer_lock_val_label = Gtk.Label(label="100%")
        self.mixer_lock_scale.connect("value-changed", lambda w: self.mixer_lock_val_label.set_text(f"{int(w.get_value())}%"))
        lb.pack_start(self.mixer_lock_scale, True, True, 0)
        lb.pack_start(self.mixer_lock_val_label, False, False, 0)
        self.mixer_guard_switch = Gtk.Switch(); self.mixer_guard_switch.set_valign(Gtk.Align.CENTER)
        self.mixer_guard_switch.connect("state-set", self.on_mixer_guard_toggled)
        lb.pack_start(self.mixer_guard_switch, False, False, 0)
        vb.pack_start(lb, False, False, 0)

        # -- Mic Guard --
        mic_f = Gtk.Frame(label="Microphone Guard")
        mb = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        mb.set_border_width(15)
        mic_f.add(mb)
        vbox.pack_start(mic_f, False, False, 0)
        
        src_row = Gtk.Box(spacing=10)
        self.mic_combo = Gtk.ComboBoxText(); self.mic_combo.set_hexpand(True)
        src_row.pack_start(self.mic_combo, True, True, 0)
        ref = Gtk.Button(label="🔄"); ref.connect("clicked", lambda b: self.load_microphone_sources(self.mic_combo))
        src_row.pack_start(ref, False, False, 0)
        mb.pack_start(src_row, False, False, 0)
        
        self.mic_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 150, 1)
        self.mic_scale.set_value(100)
        mb.pack_start(self.mic_scale, False, False, 0)
        
        ctrl_row = Gtk.Box(spacing=10)
        ctrl_row.pack_start(Gtk.Label(label="Interval (s):"), False, False, 0)
        self.mic_spin = Gtk.SpinButton.new_with_range(1, 60, 1); self.mic_spin.set_value(2)
        ctrl_row.pack_start(self.mic_spin, False, False, 0)
        ctrl_row.pack_start(Gtk.Label(), True, True, 0)
        self.mic_switch = Gtk.Switch(); self.mic_switch.set_valign(Gtk.Align.CENTER)
        self.mic_switch.connect("state-set", self.on_mic_guard_toggled)
        ctrl_row.pack_start(self.mic_switch, False, False, 0)
        mb.pack_start(ctrl_row, False, False, 0)

        # -- Admin --
        adm_f = Gtk.Frame(label="Mixer Controls")
        ab = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        ab.set_border_width(10)
        adm_f.add(ab)
        vbox.pack_start(adm_f, False, False, 0)
        
        self.create_button = Gtk.Button(label="Create Mixer"); self.create_button.connect("clicked", self.on_create_clicked)
        ab.pack_start(self.create_button, False, False, 0)
        
        arow = Gtk.Box(homogeneous=True, spacing=10)
        self.start_button = Gtk.Button(label="Start Monitor"); self.start_button.connect("clicked", self.on_start_clicked)
        self.stop_button = Gtk.Button(label="Stop Monitor"); self.stop_button.connect("clicked", self.on_stop_clicked)
        arow.pack_start(self.start_button, True, True, 0); arow.pack_start(self.stop_button, True, True, 0)
        ab.pack_start(arow, False, False, 0)
        
        self.delete_button = Gtk.Button(label="Delete Mixer"); self.delete_button.connect("clicked", self.on_delete_clicked)
        ab.pack_start(self.delete_button, False, False, 0)

        # -- Log --
        log_f = Gtk.Frame(label="Log")
        vbox.pack_start(log_f, False, False, 0)
        
        log_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        log_f.add(log_box)
        
        sw = Gtk.ScrolledWindow()
        sw.set_size_request(-1, 200)
        self.log_view = Gtk.TextView(editable=False, wrap_mode=Gtk.WrapMode.WORD)
        self.log_buffer = self.log_view.get_buffer()
        sw.add(self.log_view)
        log_box.pack_start(sw, True, True, 0)
        
        foot = Gtk.Box()
        clr = Gtk.Button(label="Clear"); clr.connect("clicked", lambda b: self.log_buffer.set_text(""))
        foot.pack_start(clr, False, False, 0)
        qt = Gtk.Button(label="Quit"); qt.connect("clicked", self.on_back_clicked)
        foot.pack_end(qt, False, False, 0)
        log_box.pack_start(foot, False, False, 0)

        # Initialize
        self.load_microphone_sources(self.mic_combo)
        if state_source: self.transfer_state_from(state_source)
        else: self.check_mixer_status()
        self.update_status_display()
        self.update_mute_ui()
        self.show_all()

    def log_message(self, msg):
        end = self.log_buffer.get_end_iter()
        self.log_buffer.insert(end, msg + "\n")
        self.log_view.scroll_mark_onscreen(self.log_buffer.create_mark(None, end, False))

    def update_status_display(self):
        self.mixer_lbl.set_markup(f"Mixer: {'🟢 Active' if self.mixer_exists else '🔴 Missing'}")
        self.mon_lbl.set_markup(f"Monitor: {'🟢 Running' if self.is_monitoring else '⚪ Stopped'}")
        self.create_button.set_sensitive(not self.mixer_exists)
        self.delete_button.set_sensitive(self.mixer_exists and not self.is_monitoring)
        self.start_button.set_sensitive(self.mixer_exists and not self.is_monitoring)
        self.stop_button.set_sensitive(self.is_monitoring)
        self.set_volume_controls_sensitive(self.mixer_exists)
        self.mixer_guard_switch.set_sensitive(self.mixer_exists)
        self.mixer_lock_scale.set_sensitive(self.mixer_exists)

    def set_volume_controls_sensitive(self, sensitive):
        if self.mixer_guard_active:
            self.btn_up.set_sensitive(False)
            self.btn_dn.set_sensitive(False)
            self.btn_mute.set_sensitive(False)
        else:
            self.btn_up.set_sensitive(sensitive)
            self.btn_dn.set_sensitive(sensitive)
            self.btn_mute.set_sensitive(sensitive)
        self.step_entry.set_sensitive(sensitive)
        self.btn_graph.set_sensitive(True)

    def update_mute_ui(self):
        self.btn_mute.set_label("🔊 Unmute" if self.is_muted else "🔇 Mute")


# ==========================================
# COMPACT VIEW (Fixed Size, Scrollable)
# ==========================================
class CompactModeWindow(AudioMixerBase):
    def __init__(self, state_source=None):
        super().__init__("Audio Mixer (Compact)")
        self.set_default_size(420, 550)
        self.set_size_request(380, 450)
        self.set_border_width(5)
        self.set_position(Gtk.WindowPosition.CENTER)
        # RESIZE DISABLED
        self.set_resizable(False)
        self.connect("destroy", self.on_window_destroy)

        main_vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5)
        self.add(main_vbox)

        # Header
        hb = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        main_vbox.pack_start(hb, False, False, 0)
        back = Gtk.Button(label="←"); back.connect("clicked", self.on_back_clicked)
        hb.pack_start(back, False, False, 0)
        self.status_lbl = Gtk.Label()
        hb.pack_start(self.status_lbl, True, True, 0)
        switch = Gtk.Button(label="👁️ Pro"); switch.connect("clicked", lambda b: self.switch_window(AdvancedModeWindow))
        hb.pack_start(switch, False, False, 0)

        # Notebook
        nb = Gtk.Notebook()
        main_vbox.pack_start(nb, True, True, 0)

        # TAB 1: CONTROL (Scrollable)
        sw1 = Gtk.ScrolledWindow()
        sw1.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        t1 = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        t1.set_border_width(10)
        sw1.add(t1)
        nb.append_page(sw1, Gtk.Label(label="Control"))

        r1 = Gtk.Box(homogeneous=True, spacing=5)
        self.create_button = Gtk.Button(label="Create"); self.create_button.connect("clicked", self.on_create_clicked)
        self.delete_button = Gtk.Button(label="Delete"); self.delete_button.connect("clicked", self.on_delete_clicked)
        r1.pack_start(self.create_button, True, True, 0); r1.pack_start(self.delete_button, True, True, 0)
        t1.pack_start(r1, False, False, 0)

        r2 = Gtk.Box(homogeneous=True, spacing=5)
        self.start_button = Gtk.Button(label="Monitor"); self.start_button.connect("clicked", self.on_start_clicked)
        self.stop_button = Gtk.Button(label="Stop"); self.stop_button.connect("clicked", self.on_stop_clicked)
        r2.pack_start(self.start_button, True, True, 0); r2.pack_start(self.stop_button, True, True, 0)
        t1.pack_start(r2, False, False, 0)

        t1.pack_start(Gtk.Separator(), False, False, 5)

        r3 = Gtk.Box(homogeneous=True, spacing=5)
        self.btn_up = Gtk.Button(label="Vol +"); self.btn_up.connect("clicked", self.on_volume_up)
        self.btn_dn = Gtk.Button(label="Vol -"); self.btn_dn.connect("clicked", self.on_volume_down)
        r3.pack_start(self.btn_up, True, True, 0); r3.pack_start(self.btn_dn, True, True, 0)
        t1.pack_start(r3, False, False, 0)

        r4 = Gtk.Box(homogeneous=True, spacing=5)
        self.btn_mute = Gtk.Button(label="Mute"); self.btn_mute.connect("clicked", self.on_toggle_mute)
        self.btn_graph = Gtk.Button(label="Graph"); self.btn_graph.connect("clicked", self.on_open_graph)
        r4.pack_start(self.btn_mute, True, True, 0); r4.pack_start(self.btn_graph, True, True, 0)
        t1.pack_start(r4, False, False, 0)

        step = Gtk.Box(spacing=5)
        step.pack_start(Gtk.Label(label="Step %:"), False, False, 0)
        self.step_entry = Gtk.Entry(text="20", width_chars=4)
        step.pack_start(self.step_entry, False, False, 0)
        apply = Gtk.Button(label="Set"); apply.connect("clicked", self.on_update_step)
        step.pack_start(apply, False, False, 0)
        t1.pack_start(step, False, False, 0)

        # TAB 2: GUARDS (Scrollable)
        sw2 = Gtk.ScrolledWindow()
        sw2.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        t2 = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        t2.set_border_width(10)
        sw2.add(t2)
        nb.append_page(sw2, Gtk.Label(label="Guards"))

        t2.pack_start(Gtk.Label(label="<b>Mixer Lock:</b>", use_markup=True, xalign=0), False, False, 0)
        lbox = Gtk.Box(spacing=5)
        self.mixer_lock_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 150, 1)
        self.mixer_lock_scale.set_value(100); self.mixer_lock_scale.set_hexpand(True)
        self.mixer_lock_lbl = Gtk.Label(label="100%")
        self.mixer_lock_scale.connect("value-changed", lambda w: self.mixer_lock_lbl.set_text(f"{int(w.get_value())}%"))
        lbox.pack_start(self.mixer_lock_scale, True, True, 0)
        lbox.pack_start(self.mixer_lock_lbl, False, False, 0)
        self.mixer_guard_switch = Gtk.Switch(); self.mixer_guard_switch.set_valign(Gtk.Align.CENTER)
        self.mixer_guard_switch.connect("state-set", self.on_mixer_guard_toggled)
        lbox.pack_start(self.mixer_guard_switch, False, False, 0)
        t2.pack_start(lbox, False, False, 0)

        t2.pack_start(Gtk.Separator(), False, False, 5)

        t2.pack_start(Gtk.Label(label="<b>Mic Guard:</b>", use_markup=True, xalign=0), False, False, 0)
        self.mic_combo = Gtk.ComboBoxText()
        mbox = Gtk.Box(spacing=5)
        mbox.pack_start(self.mic_combo, True, True, 0)
        ref = Gtk.Button(label="🔄"); ref.connect("clicked", lambda b: self.load_microphone_sources(self.mic_combo))
        mbox.pack_start(ref, False, False, 0)
        t2.pack_start(mbox, False, False, 0)
        
        self.mic_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 150, 1)
        self.mic_scale.set_value(100)
        t2.pack_start(self.mic_scale, False, False, 0)
        
        cbox = Gtk.Box(spacing=5)
        cbox.pack_start(Gtk.Label(label="Int (s):"), False, False, 0)
        self.mic_spin = Gtk.SpinButton.new_with_range(1, 60, 1); self.mic_spin.set_value(2)
        cbox.pack_start(self.mic_spin, False, False, 0)
        cbox.pack_start(Gtk.Label(), True, True, 0)
        self.mic_switch = Gtk.Switch(); self.mic_switch.set_valign(Gtk.Align.CENTER)
        self.mic_switch.connect("state-set", self.on_mic_guard_toggled)
        cbox.pack_start(self.mic_switch, False, False, 0)
        t2.pack_start(cbox, False, False, 0)

        # TAB 3: LOG (Scrollable)
        t3 = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5)
        t3.set_border_width(5)
        nb.append_page(t3, Gtk.Label(label="Log"))
        sw3 = Gtk.ScrolledWindow()
        self.log_view = Gtk.TextView(editable=False, wrap_mode=Gtk.WrapMode.WORD)
        self.log_buffer = self.log_view.get_buffer()
        sw3.add(self.log_view)
        t3.pack_start(sw3, True, True, 0)
        clr = Gtk.Button(label="Clear Log"); clr.connect("clicked", lambda b: self.log_buffer.set_text(""))
        t3.pack_start(clr, False, False, 0)

        # Init
        self.load_microphone_sources(self.mic_combo)
        if state_source: self.transfer_state_from(state_source)
        else: self.check_mixer_status()
        self.update_status_display()
        self.update_mute_ui()
        self.show_all()

    def log_message(self, msg):
        end = self.log_buffer.get_end_iter()
        self.log_buffer.insert(end, msg + "\n")
        self.log_view.scroll_mark_onscreen(self.log_buffer.create_mark(None, end, False))

    def update_status_display(self):
        m = "🟢" if self.mixer_exists else "🔴"
        mon = "🟢" if self.is_monitoring else "⚪"
        self.status_lbl.set_text(f"{m} Mixer | {mon} Mon")
        
        self.create_button.set_sensitive(not self.mixer_exists)
        self.delete_button.set_sensitive(self.mixer_exists and not self.is_monitoring)
        self.start_button.set_sensitive(self.mixer_exists and not self.is_monitoring)
        self.stop_button.set_sensitive(self.is_monitoring)
        self.set_volume_controls_sensitive(self.mixer_exists)
        self.mixer_guard_switch.set_sensitive(self.mixer_exists)
        self.mixer_lock_scale.set_sensitive(self.mixer_exists)

    def set_volume_controls_sensitive(self, sensitive):
        if self.mixer_guard_active:
            self.btn_up.set_sensitive(False)
            self.btn_dn.set_sensitive(False)
            self.btn_mute.set_sensitive(False)
        else:
            self.btn_up.set_sensitive(sensitive)
            self.btn_dn.set_sensitive(sensitive)
            self.btn_mute.set_sensitive(sensitive)
        self.btn_graph.set_sensitive(True)

    def update_mute_ui(self):
        self.btn_mute.set_label("Unmute" if self.is_muted else "Mute")

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

    # START DIRECTLY IN COMPACT MODE
    win = CompactModeWindow()
    Gtk.main()

if __name__ == "__main__":
    main()
