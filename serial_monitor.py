import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox
import serial
import serial.tools.list_ports
import threading
import time
from datetime import datetime

class SerialMonitor:
    def __init__(self, root):
        self.root = root
        self.root.title("")
        self.root.geometry("900x600")
        # Custom title bar
        self.theme = {
            'bg': '#1d1f21',
            'panel_bg': '#282a2e',
            'text_bg': '#373b41',
            'text_fg': '#c5c8c6',
            'accent': '#81a2be',
            'button_bg': '#5f676a',
            'button_fg': '#c5c8c6',
            'entry_bg': '#373b41',
            'entry_fg': '#c5c8c6',
            'success': '#b5bd68',
            'warning': '#f0c674',
            'error': '#cc6666',
            'info': '#81a2be',
            'left_bg': '#f8f8f8'  # Sol panel için açık renk
        }
        self.root.configure(bg=self.theme['bg'])
        
        # Şimdi title bar ve diğer widget'lar
        self.title_bar = tk.Frame(self.root, bg=self.theme['panel_bg'], relief='raised', bd=0, highlightthickness=0)
        self.title_bar.pack(fill=tk.X, side=tk.TOP)
        self.title_label = tk.Label(self.title_bar, text="Serial Monitor", bg=self.theme['panel_bg'], fg=self.theme['text_fg'], font=('Arial', 11, 'bold'))
        self.title_label.pack(side=tk.LEFT, padx=10, pady=2)
        self.close_btn = tk.Button(self.title_bar, text="✕", command=self.root.destroy, bg=self.theme['panel_bg'], fg=self.theme['error'], bd=0, font=('Arial', 11, 'bold'), activebackground=self.theme['panel_bg'], activeforeground=self.theme['error'], highlightthickness=0)
        self.close_btn.pack(side=tk.RIGHT, padx=8, pady=2)
        self.title_bar.bind('<B1-Motion>', self.move_window)
        self.title_bar.bind('<Button-1>', self.get_pos)
        self.title_label.bind('<B1-Motion>', self.move_window)
        self.title_label.bind('<Button-1>', self.get_pos)
        self.root.overrideredirect(True)
        
        # Serial bağlantı değişkenleri
        self.serial_connection = None
        self.is_connected = False
        self.reading_thread = None
        self.stop_reading = False
        
        self.setup_ui()
        self.refresh_ports()
        
    def setup_ui(self):
        # Ana frame
        main_frame = tk.Frame(self.root, bg=self.theme['bg'])
        main_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        
        # Sol panel - Serial port listesi (yeniden boyutlandırılabilir)
        left_frame = tk.Frame(main_frame, bg=self.theme['left_bg'], relief=tk.RAISED, bd=2)
        left_frame.pack(side=tk.LEFT, fill=tk.BOTH, padx=(0, 10))
        
        # Serial port başlığı
        self.port_title = tk.Label(left_frame, text="Available Serial Ports", font=('Arial', 12, 'bold'), bg=self.theme['left_bg'], fg='#333')
        self.port_title.pack(pady=10)
        
        # Port listesi (yeniden boyutlandırılabilir)
        listbox_frame = tk.Frame(left_frame, bg=self.theme['left_bg'])
        listbox_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=5)
        
        self.port_listbox = tk.Listbox(listbox_frame, width=45, font=('Consolas', 10), bg=self.theme['left_bg'],fg='#333', selectbackground=self.theme['accent'])
        self.port_listbox.pack(fill=tk.BOTH, expand=True)
        
        # Listbox kaydırma çubuğu
        scrollbar = tk.Scrollbar(listbox_frame, orient=tk.VERTICAL, command=self.port_listbox.yview)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.port_listbox.config(yscrollcommand=scrollbar.set)
        
        # Yenile butonu
        self.refresh_btn = tk.Button(left_frame, text="Refresh", command=self.refresh_ports,
                                    bg=self.theme['success'], fg='#333', font=('Arial', 10, 'bold'))
        self.refresh_btn.pack(pady=5)
        
        # Baud rate seçimi
        baud_frame = tk.Frame(left_frame, bg=self.theme['left_bg'])
        baud_frame.pack(pady=5)
        
        self.baud_label = tk.Label(baud_frame, text="Baud Rate:", bg=self.theme['left_bg'], font=('Arial', 10), fg='#333')
        self.baud_label.pack()
        self.baud_var = tk.StringVar(value="115200")
        self.baud_combo = ttk.Combobox(baud_frame, textvariable=self.baud_var, values=["9600", "19200", "38400", "57600", "115200", "230400"],width=10, state="readonly")
        self.baud_combo.pack(pady=2)
        
        # Yeniden boyutlandırma çubuğu
        separator = tk.Frame(main_frame, bg='#cccccc', width=5, cursor='sb_h_double_arrow')
        separator.pack(side=tk.LEFT, fill=tk.Y)
        separator.bind('<Button-1>', self.start_resize)
        separator.bind('<B1-Motion>', self.do_resize)
        
        # Sağ panel
        self.right_frame = tk.Frame(main_frame, bg=self.theme['panel_bg'], relief=tk.RAISED, bd=2)
        self.right_frame.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True)
        
        # Üst butonlar
        button_frame = tk.Frame(self.right_frame, bg=self.theme['panel_bg'])
        button_frame.pack(fill=tk.X, padx=10, pady=5)
        
        self.connect_btn = tk.Button(button_frame, text="Connect", command=self.toggle_connection,
                                    bg=self.theme['info'], fg=self.theme['panel_bg'], font=('Arial', 12, 'bold'),
                                    width=8)
        self.connect_btn.pack(side=tk.LEFT, padx=5)
        
        self.copy_btn = tk.Button(button_frame, text="Copy", command=self.copy_data,bg=self.theme['warning'], fg=self.theme['panel_bg'], font=('Arial', 12, 'bold'),width=8)
        self.copy_btn.pack(side=tk.LEFT, padx=5)
        
        self.clear_btn = tk.Button(button_frame, text="Clear", command=self.clear_output,bg=self.theme['error'], fg=self.theme['panel_bg'], font=('Arial', 12, 'bold'),width=8)
        self.clear_btn.pack(side=tk.LEFT, padx=5)
        
        self.process_btn = tk.Button(button_frame, text="Process", command=self.process_data,
                                    bg=self.theme['accent'], fg=self.theme['panel_bg'], font=('Arial', 12, 'bold'),
                                    width=8)
        self.process_btn.pack(side=tk.RIGHT, padx=5)
        
        # Veri görüntüleme alanı başlığı
        self.data_title = tk.Label(self.right_frame, text="Data Input/Output Area", font=('Arial', 12, 'bold'), bg=self.theme['panel_bg'], fg=self.theme['text_fg'])
        self.data_title.pack(pady=10)
        
        # Veri görüntüleme alanı
        self.data_text = scrolledtext.ScrolledText(self.right_frame, width=60, height=25,font=('Consolas', 10), bg=self.theme['text_bg'],fg=self.theme['text_fg'], wrap=tk.WORD,insertbackground=self.theme['accent'])
        self.data_text.pack(padx=10, pady=5, fill=tk.BOTH, expand=True)
        
        # Veri gönderme alanı
        send_frame = tk.Frame(self.right_frame, bg=self.theme['panel_bg'])
        send_frame.pack(fill=tk.X, padx=10, pady=5)
        
        self.send_label = tk.Label(send_frame, text="Send Data:", bg=self.theme['panel_bg'], font=('Arial', 10, 'bold'), fg=self.theme['text_fg'])
        self.send_label.pack(anchor=tk.W)
        
        input_frame = tk.Frame(send_frame, bg=self.theme['panel_bg'])
        input_frame.pack(fill=tk.X, pady=2)
        
        self.input_entry = tk.Entry(input_frame, font=('Consolas', 10), bg=self.theme['entry_bg'],fg=self.theme['entry_fg'], insertbackground=self.theme['accent'])
        self.input_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 5))
        self.input_entry.bind('<Return>', lambda e: self.send_data())
        
        self.send_btn = tk.Button(input_frame, text="Send", command=self.send_data,bg=self.theme['success'], fg=self.theme['panel_bg'], font=('Arial', 10, 'bold'))
        self.send_btn.pack(side=tk.RIGHT)
        
        # Durum çubuğu
        self.status_var = tk.StringVar(value="Waiting for connection...")
        self.status_bar = tk.Label(self.root, textvariable=self.status_var, relief=tk.SUNKEN, anchor=tk.W, bg=self.theme['text_bg'],fg=self.theme['text_fg'])
        self.status_bar.pack(side=tk.BOTTOM, fill=tk.X)
        
        # Yeniden boyutlandırma için değişkenler
        self.resize_start_x = 0
        self.left_frame_ref = left_frame
        
    def start_resize(self, event):
        """Start resizing"""
        self.resize_start_x = event.x_root
        
    def do_resize(self, event):
        """Perform resizing"""
        diff = event.x_root - self.resize_start_x
        current_width = self.left_frame_ref.winfo_width()
        new_width = max(200, min(600, current_width + diff))
        
        # Sol panelin genişliğini güncelle
        self.left_frame_ref.config(width=new_width)
        self.resize_start_x = event.x_root
        
    def toggle_connection(self):
        """Open/close serial connection"""
        if not self.is_connected:
            self.connect_serial()
        else:
            self.disconnect_serial()
            
    def connect_serial(self):
        """Establish serial connection"""
        try:
            selection = self.port_listbox.curselection()
            if not selection:
                messagebox.showwarning("Warning", "Please select a port!")
                return
            port_text = self.port_listbox.get(selection[0])
            if "Port bulunamadı" in port_text:
                messagebox.showerror("Error", "Please select a valid port!")
                return
                
            port_name = port_text.split(" - ")[0]
            baud_rate = int(self.baud_var.get())
            
            self.serial_connection = serial.Serial(port_name, baud_rate, timeout=1)
            self.is_connected = True
            
            # Okuma thread'ini başlat
            self.stop_reading = False
            self.reading_thread = threading.Thread(target=self.read_serial_data)
            self.reading_thread.daemon = True
            self.reading_thread.start()
            
            self.connect_btn.config(text="Disconnect", bg='#F44336')
            self.status_var.set(f"Connected: {port_name} @ {baud_rate} baud")
            self.append_to_output(f"[{datetime.now().strftime('%H:%M:%S')}] Connected: {port_name}\n")
            
        except Exception as e:
            messagebox.showerror("Error", f"Connection error: {str(e)}")
            
    def disconnect_serial(self):
        """Close serial connection"""
        try:
            self.stop_reading = True
            self.is_connected = False
            
            if self.serial_connection:
                self.serial_connection.close()
                self.serial_connection = None
                
            self.connect_btn.config(text="Connect", bg='#2196F3')
            self.status_var.set("Disconnected")
            self.append_to_output(f"[{datetime.now().strftime('%H:%M:%S')}] Disconnected\n")
            
        except Exception as e:
            messagebox.showerror("Error", f"Disconnection error: {str(e)}")
            
    def read_serial_data(self):
        """Continuously read serial data"""
        while not self.stop_reading and self.is_connected:
            try:
                if self.serial_connection and self.serial_connection.in_waiting:
                    data = self.serial_connection.readline().decode('utf-8', errors='ignore').strip()
                    if data:
                        timestamp = datetime.now().strftime('%H:%M:%S')
                        self.append_to_output(f"[{timestamp}] RX: {data}\n")
                        
            except Exception as e:
                self.append_to_output(f"[{datetime.now().strftime('%H:%M:%S')}] Read error: {str(e)}\n")
                break
                
            time.sleep(0.01)
            
    def send_data(self):
        """Send data"""
        if not self.is_connected:
            messagebox.showwarning("Warning", "Connect first!")
            return
            
        data = self.input_entry.get().strip()
        if not data:
            return
            
        try:
            self.serial_connection.write((data + '\n').encode('utf-8'))
            timestamp = datetime.now().strftime('%H:%M:%S')
            self.append_to_output(f"[{timestamp}] TX: {data}\n")
            self.input_entry.delete(0, tk.END)
            
        except Exception as e:
            messagebox.showerror("Error", f"Send error: {str(e)}")
            
    def append_to_output(self, text):
        """Append text to output area"""
        self.data_text.insert(tk.END, text)
        self.data_text.see(tk.END)
        
    def copy_data(self):
        """Copy data to clipboard"""
        try:
            data = self.data_text.get(1.0, tk.END)
            self.root.clipboard_clear()
            self.root.clipboard_append(data)
            messagebox.showinfo("Info", "Data copied to clipboard!")
        except Exception as e:
            messagebox.showerror("Error", f"Copy error: {str(e)}")
            
    def clear_output(self):
        """Clear output area"""
        self.data_text.delete(1.0, tk.END)
        
    def process_data(self):
        """Process data function (to be sent to Tang Nano 9K)"""
        if not self.is_connected:
            messagebox.showwarning("Warning", "Connect first!")
            return
        # Send process image command
        try:
            command = "PROCESS_IMAGE"
            self.serial_connection.write((command + '\n').encode('utf-8'))
            timestamp = datetime.now().strftime('%H:%M:%S')
            self.append_to_output(f"[{timestamp}] TX: {command} (Process image command)\n")
        except Exception as e:
            messagebox.showerror("Error", f"Command send error: {str(e)}")

    def refresh_ports(self):
        """List available serial ports"""
        self.port_listbox.delete(0, tk.END)
        ports = serial.tools.list_ports.comports()
        if not ports:
            self.port_listbox.insert(tk.END, "No port found")
        else:
            for port in ports:
                port_info = f"{port.device} - {port.description}"
                self.port_listbox.insert(tk.END, port_info)

    def get_pos(self, event):
        self.xwin = event.x
        self.ywin = event.y

    def move_window(self, event):
        self.root.geometry(f'+{event.x_root - self.xwin}+{event.y_root - self.ywin}')

def main():
    root = tk.Tk()
    app = SerialMonitor(root)
    
    def on_closing():
        if app.is_connected:
            app.disconnect_serial()
        root.destroy()
    
    root.protocol("WM_DELETE_WINDOW", on_closing)
    root.mainloop()

if __name__ == "__main__":
    main()