#!/usr/bin/env python3
"""
Real-time Audio Waveform Monitor
Monitors PulseAudio sources and displays waveform visualization
"""

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib
import subprocess
import struct
import sys
import os
import argparse

class AudioMonitor:
    def __init__(self):
        self.process = None
        self.paused = False
        
    def get_available_sources(self):
        """Get all available audio sources (monitors and inputs)"""
        try:
            result = subprocess.run(['pactl', 'list', 'sources', 'short'], 
                                  capture_output=True, text=True, check=True)
            sources = []
            for line in result.stdout.strip().split('\n'):
                if line:
                    parts = line.split('\t')
                    if len(parts) >= 2:
                        source_name = parts[1]
                        # Get a friendly description
                        description = self.get_source_description(source_name)
                        sources.append((source_name, description))
            return sources
        except subprocess.CalledProcessError:
            return []
    
    def get_source_description(self, source_name):
        """Get a human-readable description for a source"""
        try:
            result = subprocess.run(['pactl', 'list', 'sources'], 
                                  capture_output=True, text=True, check=True)
            lines = result.stdout.split('\n')
            found_source = False
            for i, line in enumerate(lines):
                if f'Name: {source_name}' in line:
                    found_source = True
                elif found_source and 'Description:' in line:
                    return line.split('Description:', 1)[1].strip()
            return source_name
        except subprocess.CalledProcessError:
            return source_name
    
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
        # Trim from the front to always show the most recent data
        while len(self.history) > self.max_history:
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
        
        # Calculate bar width - allow fractional values for thin bars
        bar_width = width / self.max_history
        middle = height / 2
        
        # Optimize drawing based on bar width
        if bar_width >= 1.0:
            # Normal mode: draw individual bars
            for i, amplitude in enumerate(self.history):
                x = i * bar_width
                
                # Scale amplitude with user control
                scaled_amp = amplitude * self.amplitude * middle * 0.9
                
                # Draw vertical bar from center
                cr.set_line_width(self.wave_thickness)
                cr.move_to(x, middle - scaled_amp)
                cr.line_to(x, middle + scaled_amp)
                cr.stroke()
        else:
            # Thin bar mode: draw more efficiently with rectangles
            # Use thinner line width for very dense waveforms
            effective_thickness = max(0.5, min(self.wave_thickness, bar_width))
            
            for i, amplitude in enumerate(self.history):
                x = i * bar_width
                
                # Scale amplitude with user control
                scaled_amp = amplitude * self.amplitude * middle * 0.9
                
                # Draw as a thin rectangle for better performance
                if scaled_amp > 0:
                    cr.rectangle(x, middle - scaled_amp, effective_thickness, scaled_amp * 2)
                    cr.fill()
        
        # Draw scrolling position indicator (rightmost edge highlighted)
        if self.dark_theme:
            cr.set_source_rgba(1.0, 1.0, 1.0, 0.3)
        else:
            cr.set_source_rgba(0.0, 0.0, 0.0, 0.3)
        cr.set_line_width(2)
        # Use actual width to ensure indicator is at the right edge
        x_pos = min(len(self.history) * bar_width, width - 1)
        cr.move_to(x_pos, 0)
        cr.line_to(x_pos, height)
        cr.stroke()

class AudioVisualizerWindow(Gtk.Window):
    def __init__(self, initial_source=None):
        super().__init__(title="Audio Waveform Monitor")
        self.set_default_size(900, 500)
        self.set_border_width(10)
        self.set_resizable(False)  # Make it float like volume control
        
        self.monitor = AudioMonitor()
        self.buffer_size = 2205  # Reduced to 0.05 seconds at 44100 Hz (was 0.1s)
        self.timeout_id = None
        self.current_source = initial_source
        
        # Main container
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)
        
        # Audio source selector
        source_box = self.create_source_selector()
        vbox.pack_start(source_box, False, False, 0)
        
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
    
    def create_source_selector(self):
        """Create the audio source selection dropdown"""
        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        
        label = Gtk.Label(label="Audio Source:")
        hbox.pack_start(label, False, False, 0)
        
        # Create combo box for source selection
        self.source_combo = Gtk.ComboBoxText()
        self.source_combo.set_size_request(400, -1)
        
        # Populate with available sources
        sources = self.monitor.get_available_sources()
        for source_name, description in sources:
            self.source_combo.append(source_name, description)
        
        # Set initial source based on parameter or default
        if self.current_source:
            # Try to set the specified source
            self.source_combo.set_active_id(self.current_source)
            # If that failed (source not found), fall back to default
            if self.source_combo.get_active_id() is None:
                print(f"Warning: Source '{self.current_source}' not found, using default")
                self.current_source = None
        
        if not self.current_source:
            # Set default to the default sink monitor
            default_source = self.monitor.get_default_sink()
            if default_source:
                self.source_combo.set_active_id(default_source)
                self.current_source = default_source
            elif sources:
                # Fall back to first available source
                self.source_combo.set_active(0)
                self.current_source = sources[0][0]
        
        self.source_combo.connect('changed', self.on_source_changed)
        hbox.pack_start(self.source_combo, True, True, 0)
        
        # Refresh button
        refresh_button = Gtk.Button(label="🔄 Refresh")
        refresh_button.connect('clicked', self.on_refresh_sources)
        hbox.pack_start(refresh_button, False, False, 0)
        
        return hbox
    
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
        if not self.current_source:
            dialog = Gtk.MessageDialog(
                transient_for=self,
                flags=0,
                message_type=Gtk.MessageType.ERROR,
                buttons=Gtk.ButtonsType.OK,
                text="No audio source available"
            )
            dialog.run()
            dialog.destroy()
            return
        
        self.monitor.start_capture(self.current_source)
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
    
    def on_source_changed(self, combo):
        """Handle audio source change"""
        source_name = combo.get_active_id()
        if source_name and source_name != self.current_source:
            self.current_source = source_name
            # Restart monitoring with new source
            self.monitor.stop_capture()
            self.monitor.start_capture(source_name)
            # Clear waveform history
            self.waveform.history = []
    
    def on_refresh_sources(self, button):
        """Refresh the list of available audio sources"""
        current_selection = self.source_combo.get_active_id()
        
        # Clear existing items
        self.source_combo.remove_all()
        
        # Repopulate
        sources = self.monitor.get_available_sources()
        for source_name, description in sources:
            self.source_combo.append(source_name, description)
        
        # Try to restore previous selection
        if current_selection:
            self.source_combo.set_active_id(current_selection)
        elif sources:
            self.source_combo.set_active(0)
    
    def on_destroy(self, widget):
        if self.timeout_id:
            GLib.source_remove(self.timeout_id)
        self.monitor.stop_capture()
        Gtk.main_quit()

def list_sources():
    """List all available audio sources"""
    monitor = AudioMonitor()
    sources = monitor.get_available_sources()
    
    if not sources:
        print("No audio sources found.")
        return
    
    print("Available audio sources:")
    print("-" * 80)
    for source_name, description in sources:
        print(f"  {source_name}")
        print(f"    → {description}")
        print()

def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(
        description='Real-time Audio Waveform Monitor',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  %(prog)s                                    # Use default audio source
  %(prog)s -d alsa_output.pci-0000_00_1f.3.analog-stereo.monitor
  %(prog)s --device my-device-name
  %(prog)s --list                             # List all available sources
        ''')
    
    parser.add_argument('-d', '--device', 
                        help='Audio source device name to monitor')
    parser.add_argument('-l', '--list', 
                        action='store_true',
                        help='List all available audio sources and exit')
    
    args = parser.parse_args()
    
    # Check for required dependencies
    try:
        subprocess.run(['pactl', '--version'], capture_output=True, check=True)
        subprocess.run(['parec', '--version'], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Error: PulseAudio tools (pactl, parec) are required.")
        print("Install with: sudo apt install pulseaudio-utils")
        sys.exit(1)
    
    # Handle --list option
    if args.list:
        list_sources()
        sys.exit(0)
    
    # Start the GUI with optional device specification
    win = AudioVisualizerWindow(initial_source=args.device)
    win.show_all()
    Gtk.main()

if __name__ == '__main__':
    main()