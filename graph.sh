#!/usr/bin/env python3
"""
Real-time Audio Waveform Monitor
Monitors PulseAudio default sink and displays waveform visualization
"""

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib
import subprocess
import struct
import sys
import os

class AudioMonitor:
    def __init__(self):
        self.process = None
        self.paused = False
        
    def get_default_sink(self):
        """Get the default sink monitor name"""
        try:
            result = subprocess.run(['pactl', 'get-default-sink'], 
                                  capture_output=True, text=True, check=True)
            sink_name = result.stdout.strip()
            return f"{sink_name}.monitor"
        except subprocess.CalledProcessError:
            return None
    
    def start_capture(self, monitor_name):
        """Start capturing audio from the monitor"""
        if self.process:
            self.stop_capture()
        
        # Use parec to capture raw audio data with reduced latency settings
        cmd = ['parec', 
               '--device', monitor_name, 
               '--format=s16le', 
               '--rate=44100', 
               '--channels=1',
               '--latency-msec=50']  # Set low latency
        
        self.process = subprocess.Popen(cmd, 
                                       stdout=subprocess.PIPE, 
                                       stderr=subprocess.DEVNULL,
                                       bufsize=0)  # Disable buffering
        
        # Make the pipe non-blocking to avoid read delays
        import fcntl
        flags = fcntl.fcntl(self.process.stdout, fcntl.F_GETFL)
        fcntl.fcntl(self.process.stdout, fcntl.F_SETFL, flags | os.O_NONBLOCK)
        
    def stop_capture(self):
        """Stop audio capture"""
        if self.process:
            self.process.terminate()
            self.process.wait()
            self.process = None
    
    def read_samples(self, num_samples):
        """Read audio samples"""
        if not self.process or self.paused:
            return [0] * num_samples
        
        try:
            # Read raw bytes (2 bytes per sample for s16le)
            data = self.process.stdout.read(num_samples * 2)
            if not data or len(data) < num_samples * 2:
                return [0] * num_samples
            
            # Unpack as signed 16-bit integers
            samples = struct.unpack(f'{num_samples}h', data)
            # Normalize to -1.0 to 1.0
            return [s / 32768.0 for s in samples]
        except BlockingIOError:
            # No data available yet
            return [0] * num_samples
        except:
            return [0] * num_samples

class WaveformWidget(Gtk.DrawingArea):
    def __init__(self):
        super().__init__()
        self.samples = []
        self.amplitude = 1.0
        self.dark_theme = True
        self.wave_color = (0.2, 0.8, 0.2)  # Green by default
        self.wave_thickness = 2.0
        self.history = []  # Store historical waveform data
        self.max_history = 800  # Number of vertical bars to keep
        
        self.connect('draw', self.on_draw)
        self.set_size_request(800, 300)
    
    def set_samples(self, samples):
        if not samples:
            return
        
        # Calculate RMS (Root Mean Square) for amplitude of this chunk
        rms = (sum(s * s for s in samples) / len(samples)) ** 0.5
        
        # Add to history
        self.history.append(rms)
        
        # Keep only max_history items (scroll effect)
        if len(self.history) > self.max_history:
            self.history.pop(0)
        
        self.queue_draw()
    
    def on_draw(self, widget, cr):
        width = widget.get_allocated_width()
        height = widget.get_allocated_height()
        
        # Background
        if self.dark_theme:
            cr.set_source_rgb(0.1, 0.1, 0.1)
        else:
            cr.set_source_rgb(0.95, 0.95, 0.95)
        cr.paint()
        
        # Draw center line
        if self.dark_theme:
            cr.set_source_rgba(0.3, 0.3, 0.3, 0.5)
        else:
            cr.set_source_rgba(0.7, 0.7, 0.7, 0.5)
        cr.set_line_width(1)
        cr.move_to(0, height / 2)
        cr.line_to(width, height / 2)
        cr.stroke()
        
        # Draw waveform bars (audio recording style)
        if not self.history:
            return
        
        cr.set_source_rgb(*self.wave_color)
        
        # Calculate bar width
        bar_width = max(1, width / self.max_history)
        middle = height / 2
        
        # Draw each amplitude value as a vertical bar
        for i, amplitude in enumerate(self.history):
            x = i * bar_width
            
            # Scale amplitude with user control
            scaled_amp = amplitude * self.amplitude * middle * 0.9
            
            # Draw vertical bar from center
            cr.set_line_width(self.wave_thickness)
            cr.move_to(x, middle - scaled_amp)
            cr.line_to(x, middle + scaled_amp)
            cr.stroke()
        
        # Draw scrolling position indicator (rightmost edge highlighted)
        if self.dark_theme:
            cr.set_source_rgba(1.0, 1.0, 1.0, 0.3)
        else:
            cr.set_source_rgba(0.0, 0.0, 0.0, 0.3)
        cr.set_line_width(2)
        x_pos = len(self.history) * bar_width
        cr.move_to(x_pos, 0)
        cr.line_to(x_pos, height)
        cr.stroke()

class AudioVisualizerWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Audio Waveform Monitor")
        self.set_default_size(900, 500)
        self.set_border_width(10)
        
        self.monitor = AudioMonitor()
        self.buffer_size = 2205  # Reduced to 0.05 seconds at 44100 Hz (was 0.1s)
        self.timeout_id = None
        
        # Main container
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)
        
        # Waveform display
        self.waveform = WaveformWidget()
        frame = Gtk.Frame()
        frame.add(self.waveform)
        vbox.pack_start(frame, True, True, 0)
        
        # Controls
        controls = self.create_controls()
        vbox.pack_start(controls, False, False, 0)
        
        # Start monitoring
        self.start_monitoring()
        
        self.connect('destroy', self.on_destroy)
    
    def create_controls(self):
        grid = Gtk.Grid()
        grid.set_column_spacing(10)
        grid.set_row_spacing(5)
        
        # Pause/Resume button
        self.pause_button = Gtk.Button(label="Pause")
        self.pause_button.connect('clicked', self.on_pause_clicked)
        grid.attach(self.pause_button, 0, 0, 1, 1)
        
        # Amplitude control
        label = Gtk.Label(label="Amplitude:")
        grid.attach(label, 0, 1, 1, 1)
        
        self.amplitude_scale = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, 0.1, 5.0, 0.1)
        self.amplitude_scale.set_value(1.0)
        self.amplitude_scale.set_size_request(200, -1)
        self.amplitude_scale.connect('value-changed', self.on_amplitude_changed)
        grid.attach(self.amplitude_scale, 1, 1, 2, 1)
        
        self.amplitude_label = Gtk.Label(label="1.0x")
        grid.attach(self.amplitude_label, 3, 1, 1, 1)
        
        # Graph length control
        label = Gtk.Label(label="History Length:")
        grid.attach(label, 0, 2, 1, 1)
        
        self.length_scale = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, 100, 2000, 50)
        self.length_scale.set_value(800)
        self.length_scale.set_size_request(200, -1)
        self.length_scale.connect('value-changed', self.on_length_changed)
        grid.attach(self.length_scale, 1, 2, 2, 1)
        
        self.length_label = Gtk.Label(label="800")
        grid.attach(self.length_label, 3, 2, 1, 1)
        
        # Wave color
        label = Gtk.Label(label="Wave Color:")
        grid.attach(label, 0, 3, 1, 1)
        
        self.color_button = Gtk.ColorButton()
        rgba = Gdk.RGBA()
        rgba.red, rgba.green, rgba.blue, rgba.alpha = 0.2, 0.8, 0.2, 1.0
        self.color_button.set_rgba(rgba)
        self.color_button.connect('color-set', self.on_color_changed)
        grid.attach(self.color_button, 1, 3, 1, 1)
        
        # Wave thickness
        label = Gtk.Label(label="Line Thickness:")
        grid.attach(label, 0, 4, 1, 1)
        
        self.thickness_scale = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, 0.5, 5.0, 0.5)
        self.thickness_scale.set_value(2.0)
        self.thickness_scale.set_size_request(200, -1)
        self.thickness_scale.connect('value-changed', self.on_thickness_changed)
        grid.attach(self.thickness_scale, 1, 4, 2, 1)
        
        self.thickness_label = Gtk.Label(label="2.0px")
        grid.attach(self.thickness_label, 3, 4, 1, 1)
        
        # Theme toggle
        self.theme_button = Gtk.Button(label="Toggle Theme")
        self.theme_button.connect('clicked', self.on_theme_clicked)
        grid.attach(self.theme_button, 0, 5, 1, 1)
        
        return grid
    
    def start_monitoring(self):
        monitor_name = self.monitor.get_default_sink()
        if not monitor_name:
            dialog = Gtk.MessageDialog(
                transient_for=self,
                flags=0,
                message_type=Gtk.MessageType.ERROR,
                buttons=Gtk.ButtonsType.OK,
                text="Cannot find default audio sink"
            )
            dialog.run()
            dialog.destroy()
            return
        
        self.monitor.start_capture(monitor_name)
        # Reduced update interval from 100ms to 50ms for faster response
        self.timeout_id = GLib.timeout_add(50, self.update_waveform)
    
    def update_waveform(self):
        samples = self.monitor.read_samples(self.buffer_size)
        self.waveform.set_samples(samples)
        return True
    
    def on_pause_clicked(self, button):
        self.monitor.paused = not self.monitor.paused
        if self.monitor.paused:
            button.set_label("Resume")
        else:
            button.set_label("Pause")
    
    def on_amplitude_changed(self, scale):
        value = scale.get_value()
        self.waveform.amplitude = value
        self.amplitude_label.set_text(f"{value:.1f}x")
    
    def on_length_changed(self, scale):
        value = int(scale.get_value())
        self.waveform.max_history = value
        self.length_label.set_text(str(value))
    
    def on_color_changed(self, button):
        rgba = button.get_rgba()
        self.waveform.wave_color = (rgba.red, rgba.green, rgba.blue)
    
    def on_thickness_changed(self, scale):
        value = scale.get_value()
        self.waveform.wave_thickness = value
        self.thickness_label.set_text(f"{value:.1f}px")
    
    def on_theme_clicked(self, button):
        self.waveform.dark_theme = not self.waveform.dark_theme
        self.waveform.queue_draw()
    
    def on_destroy(self, widget):
        if self.timeout_id:
            GLib.source_remove(self.timeout_id)
        self.monitor.stop_capture()
        Gtk.main_quit()

def main():
    # Check for required dependencies
    try:
        subprocess.run(['pactl', '--version'], capture_output=True, check=True)
        subprocess.run(['parec', '--version'], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Error: PulseAudio tools (pactl, parec) are required.")
        print("Install with: sudo apt install pulseaudio-utils")
        sys.exit(1)
    
    win = AudioVisualizerWindow()
    win.show_all()
    Gtk.main()

if __name__ == '__main__':
    main()
