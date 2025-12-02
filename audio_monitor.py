#!/usr/bin/env python3
"""
Modular Audio Waveform Monitor
Can be used standalone or embedded in other GTK applications
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
    """Audio capture handler"""
    def __init__(self):
        self.process = None
        
    def get_available_sources(self):
        """Get all available audio sources"""
        try:
            result = subprocess.run(['pactl', 'list', 'sources', 'short'], 
                                  capture_output=True, text=True, check=True)
            sources = []
            for line in result.stdout.strip().split('\n'):
                if line:
                    parts = line.split('\t')
                    if len(parts) >= 2:
                        sources.append(parts[1])
            return sources
        except subprocess.CalledProcessError:
            return []
    
    def get_default_sink_monitor(self):
        """Get the default sink monitor name"""
        try:
            result = subprocess.run(['pactl', 'get-default-sink'], 
                                  capture_output=True, text=True, check=True)
            sink_name = result.stdout.strip()
            return f"{sink_name}.monitor"
        except subprocess.CalledProcessError:
            return None
    
    def start_capture(self, source_name):
        """Start capturing audio from the source"""
        if self.process:
            self.stop_capture()
        
        cmd = ['parec', 
               '--device', source_name, 
               '--format=s16le', 
               '--rate=44100', 
               '--channels=1',
               '--latency-msec=50']
        
        self.process = subprocess.Popen(cmd, 
                                       stdout=subprocess.PIPE, 
                                       stderr=subprocess.DEVNULL,
                                       bufsize=0)
        
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
        if not self.process:
            return [0] * num_samples
        
        try:
            data = self.process.stdout.read(num_samples * 2)
            if not data or len(data) < num_samples * 2:
                return [0] * num_samples
            
            samples = struct.unpack(f'{num_samples}h', data)
            return [s / 32768.0 for s in samples]
        except BlockingIOError:
            return [0] * num_samples
        except:
            return [0] * num_samples

class WaveformWidget(Gtk.DrawingArea):
    """Reusable waveform display widget"""
    def __init__(self, amplitude=1.0, history_length=800, color=(0.2, 0.8, 0.2), 
                 thickness=2.0, dark_theme=True):
        super().__init__()
        self.amplitude = amplitude
        self.max_history = history_length
        self.wave_color = color
        self.wave_thickness = thickness
        self.dark_theme = dark_theme
        self.history = []
        
        self.connect('draw', self.on_draw)
        self.set_size_request(800, 300)
    
    def set_samples(self, samples):
        """Update waveform with new audio samples"""
        if not samples:
            return
        
        rms = (sum(s * s for s in samples) / len(samples)) ** 0.5
        self.history.append(rms)
        
        while len(self.history) > self.max_history:
            self.history.pop(0)
        
        self.queue_draw()
    
    def clear_history(self):
        """Clear the waveform history"""
        self.history = []
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
        
        # Draw waveform
        if not self.history:
            return
        
        cr.set_source_rgb(*self.wave_color)
        
        bar_width = width / self.max_history
        middle = height / 2
        
        if bar_width >= 1.0:
            for i, amp in enumerate(self.history):
                x = i * bar_width
                scaled_amp = amp * self.amplitude * middle * 0.9
                cr.set_line_width(self.wave_thickness)
                cr.move_to(x, middle - scaled_amp)
                cr.line_to(x, middle + scaled_amp)
                cr.stroke()
        else:
            effective_thickness = max(0.5, min(self.wave_thickness, bar_width))
            for i, amp in enumerate(self.history):
                x = i * bar_width
                scaled_amp = amp * self.amplitude * middle * 0.9
                if scaled_amp > 0:
                    cr.rectangle(x, middle - scaled_amp, effective_thickness, scaled_amp * 2)
                    cr.fill()
        
        # Scrolling indicator
        if self.dark_theme:
            cr.set_source_rgba(1.0, 1.0, 1.0, 0.3)
        else:
            cr.set_source_rgba(0.0, 0.0, 0.0, 0.3)
        cr.set_line_width(2)
        x_pos = min(len(self.history) * bar_width, width - 1)
        cr.move_to(x_pos, 0)
        cr.line_to(x_pos, height)
        cr.stroke()

class AudioWaveformMonitor(Gtk.Box):
    """
    Complete audio monitor component that can be embedded in other applications.
    
    Usage in your GUI:
        monitor = AudioWaveformMonitor(source="your-device-name")
        your_container.pack_start(monitor, True, True, 0)
        monitor.start()  # Start monitoring
        monitor.stop()   # Stop monitoring
    """
    
    def __init__(self, source=None, amplitude=1.0, history_length=800, 
                 color=(0.2, 0.8, 0.2), thickness=2.0, dark_theme=True):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=5)
        
        self.monitor = AudioMonitor()
        self.buffer_size = 2205
        self.timeout_id = None
        self.source = source
        self.is_monitoring = False
        
        # Create waveform widget
        self.waveform = WaveformWidget(amplitude, history_length, color, thickness, dark_theme)
        
        # Add to container
        frame = Gtk.Frame()
        frame.add(self.waveform)
        self.pack_start(frame, True, True, 0)
    
    def start(self):
        """Start audio monitoring"""
        if self.is_monitoring:
            return
        
        if not self.source:
            self.source = self.monitor.get_default_sink_monitor()
            if not self.source:
                print("Error: No audio source available", file=sys.stderr)
                return False
        
        self.monitor.start_capture(self.source)
        self.timeout_id = GLib.timeout_add(50, self._update_waveform)
        self.is_monitoring = True
        return True
    
    def stop(self):
        """Stop audio monitoring"""
        if not self.is_monitoring:
            return
        
        if self.timeout_id:
            GLib.source_remove(self.timeout_id)
            self.timeout_id = None
        
        self.monitor.stop_capture()
        self.is_monitoring = False
    
    def toggle(self):
        """Toggle monitoring on/off"""
        if self.is_monitoring:
            self.stop()
        else:
            self.start()
        return self.is_monitoring
    
    def set_source(self, source_name):
        """Change the audio source"""
        was_monitoring = self.is_monitoring
        if was_monitoring:
            self.stop()
        
        self.source = source_name
        self.waveform.clear_history()
        
        if was_monitoring:
            self.start()
    
    def _update_waveform(self):
        """Internal method to update waveform display"""
        samples = self.monitor.read_samples(self.buffer_size)
        self.waveform.set_samples(samples)
        return True
    
    def cleanup(self):
        """Clean up resources (call this when destroying parent window)"""
        self.stop()


# ============================================================================
# Example usage: Standalone window
# ============================================================================

class StandaloneWindow(Gtk.Window):
    """Example standalone window using the monitor component"""
    def __init__(self, source, amplitude, history_length, color, thickness, dark_theme):
        super().__init__(title="Audio Waveform Monitor")
        
        self.set_default_size(900, 400)
        self.set_border_width(10)
        self.set_resizable(False)
        
        # Create the monitor component
        self.audio_monitor = AudioWaveformMonitor(
            source=source,
            amplitude=amplitude,
            history_length=history_length,
            color=color,
            thickness=thickness,
            dark_theme=dark_theme
        )
        
        self.add(self.audio_monitor)
        
        # Start monitoring
        self.audio_monitor.start()
        
        self.connect('destroy', self.on_destroy)
    
    def on_destroy(self, widget):
        self.audio_monitor.cleanup()
        Gtk.main_quit()


# ============================================================================
# Example: Integration with another GUI
# ============================================================================

class ExampleParentGUI(Gtk.Window):
    """
    Example showing how to integrate the audio monitor into your existing GUI
    """
    def __init__(self):
        super().__init__(title="My Application with Audio Monitor")
        self.set_default_size(900, 600)
        self.set_border_width(10)
        
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)
        
        # Your existing GUI content
        label = Gtk.Label(label="My Application")
        vbox.pack_start(label, False, False, 0)
        
        # Button to toggle audio monitor
        self.toggle_button = Gtk.Button(label="Show Audio Monitor")
        self.toggle_button.connect('clicked', self.on_toggle_monitor)
        vbox.pack_start(self.toggle_button, False, False, 0)
        
        # Container for audio monitor (initially empty)
        self.monitor_container = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        vbox.pack_start(self.monitor_container, True, True, 0)
        
        # Audio monitor (not added yet)
        self.audio_monitor = None
        self.monitor_visible = False
        
        self.connect('destroy', self.on_destroy)
    
    def on_toggle_monitor(self, button):
        """Toggle the audio monitor visibility"""
        if not self.monitor_visible:
            # Create and show monitor
            self.audio_monitor = AudioWaveformMonitor(
                amplitude=1.5,
                color=(0.2, 0.5, 0.8),  # Blue
                dark_theme=True
            )
            self.monitor_container.pack_start(self.audio_monitor, True, True, 0)
            self.audio_monitor.show_all()
            self.audio_monitor.start()
            
            self.toggle_button.set_label("Hide Audio Monitor")
            self.monitor_visible = True
        else:
            # Hide and destroy monitor
            if self.audio_monitor:
                self.audio_monitor.stop()
                self.monitor_container.remove(self.audio_monitor)
                self.audio_monitor = None
            
            self.toggle_button.set_label("Show Audio Monitor")
            self.monitor_visible = False
    
    def on_destroy(self, widget):
        if self.audio_monitor:
            self.audio_monitor.cleanup()
        Gtk.main_quit()


# ============================================================================
# Utility functions
# ============================================================================

def parse_color(color_str):
    """Parse color string in hex format (#RRGGBB) or named colors"""
    color_map = {
        'green': (0.2, 0.8, 0.2),
        'red': (0.8, 0.2, 0.2),
        'blue': (0.2, 0.2, 0.8),
        'yellow': (0.8, 0.8, 0.2),
        'cyan': (0.2, 0.8, 0.8),
        'magenta': (0.8, 0.2, 0.8),
        'white': (1.0, 1.0, 1.0),
        'orange': (1.0, 0.5, 0.0),
    }
    
    color_str = color_str.lower()
    if color_str in color_map:
        return color_map[color_str]
    
    if color_str.startswith('#'):
        color_str = color_str[1:]
    
    if len(color_str) == 6:
        try:
            r = int(color_str[0:2], 16) / 255.0
            g = int(color_str[2:4], 16) / 255.0
            b = int(color_str[4:6], 16) / 255.0
            return (r, g, b)
        except ValueError:
            pass
    
    return (0.2, 0.8, 0.2)

def list_sources():
    """List all available audio sources"""
    monitor = AudioMonitor()
    sources = monitor.get_available_sources()
    
    if not sources:
        print("No audio sources found.")
        return
    
    print("Available audio sources:")
    print("-" * 80)
    for source_name in sources:
        print(f"  {source_name}")
    print()
    
    default = monitor.get_default_sink_monitor()
    if default:
        print(f"Default sink monitor: {default}")


# ============================================================================
# Main entry point for standalone usage
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description='Modular Audio Waveform Monitor',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  # Standalone usage:
  %(prog)s --list
  %(prog)s -d my-device --amplitude 2.5 --color red
  
  # Integration example:
  %(prog)s --example
  
  # In your Python code:
  from audio_monitor import AudioWaveformMonitor
  monitor = AudioWaveformMonitor(source="device-name")
  your_container.add(monitor)
  monitor.start()
        ''')
    
    parser.add_argument('-d', '--device', 
                        help='Audio source device name to monitor')
    parser.add_argument('-l', '--list', 
                        action='store_true',
                        help='List all available audio sources and exit')
    parser.add_argument('-a', '--amplitude', 
                        type=float, 
                        default=1.0,
                        help='Amplitude multiplier (0.1-5.0, default: 1.0)')
    parser.add_argument('--history', 
                        type=int, 
                        default=800,
                        help='History length in samples (100-2000, default: 800)')
    parser.add_argument('-c', '--color', 
                        default='green',
                        help='Wave color: green, red, blue, yellow, cyan, magenta, white, orange, or hex (#RRGGBB)')
    parser.add_argument('-t', '--thickness', 
                        type=float, 
                        default=2.0,
                        help='Line thickness in pixels (0.5-5.0, default: 2.0)')
    parser.add_argument('--light', 
                        action='store_true',
                        help='Use light theme instead of dark')
    parser.add_argument('--example',
                        action='store_true',
                        help='Show example of integrating monitor into another GUI')
    
    args = parser.parse_args()
    
    # Check for required tools
    try:
        subprocess.run(['pactl', '--version'], capture_output=True, check=True)
        subprocess.run(['parec', '--version'], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Error: PulseAudio tools (pactl, parec) are required.")
        print("Install with: sudo apt install pulseaudio-utils")
        sys.exit(1)
    
    if args.list:
        list_sources()
        sys.exit(0)
    
    # Show integration example
    if args.example:
        win = ExampleParentGUI()
        win.show_all()
        Gtk.main()
        sys.exit(0)
    
    # Standalone mode
    if not args.device:
        monitor = AudioMonitor()
        args.device = monitor.get_default_sink_monitor()
        if not args.device:
            print("Error: No default audio source found. Use --list to see available sources.")
            sys.exit(1)
        print(f"Using default source: {args.device}")
    
    args.amplitude = max(0.1, min(5.0, args.amplitude))
    args.history = max(100, min(2000, args.history))
    args.thickness = max(0.5, min(5.0, args.thickness))
    color = parse_color(args.color)
    dark_theme = not args.light
    
    win = StandaloneWindow(
        args.device, 
        args.amplitude, 
        args.history, 
        color, 
        args.thickness, 
        dark_theme
    )
    win.show_all()
    Gtk.main()

if __name__ == '__main__':
    main()
