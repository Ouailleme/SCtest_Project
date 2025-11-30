import customtkinter as ctk
import threading
import time
import socket
import os
import subprocess
from pymobiledevice3.lockdown import create_using_usbmux

# --- CONFIGURATION ---
ctk.set_appearance_mode("Light") 
ctk.set_default_color_theme("dark-blue")

# --- LISTE DES TESTS ---
TESTS_LIST = [
    ("Wifi", "📶"), ("Bluetooth", "ᛒ"), ("Flash", "🔦"),
    ("Micro Avant", "🎙️"), ("Micro Arr.", "🎙️"),
    ("HP Écouteur", "👂"), ("HP Bas (Média)", "🔊"),
    ("Vibreur", "📳"), 
    ("Caméra Av.", "🤳"), ("Caméra Arr.", "📷"), 
    ("Écran", "🖥️"), 
    ("Accéléromètre", "🔄"), ("Proximité", "✋"), # NOUVEAUX
    ("Face ID", "🔓"), ("Boutons Vol", "Volumes"), ("Tactile", "👆")
]

class SCtestApp(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.title("SCtest Station - v13.0 (Sensors)")
        self.geometry("1150x750") 
        self.configure(fg_color="#F0F0F3")

        self.stop_thread = False
        self.server_socket = None
        self.mobile_client = None
        self.mobile_connected = False
        self.test_buttons = {}
        
        self.adb_path = os.path.expandvars(r"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe") 

        # --- HEADER ---
        self.header = ctk.CTkFrame(self, height=60, fg_color="white", corner_radius=0)
        self.header.pack(fill="x", side="top")
        self.lbl_titre = ctk.CTkLabel(self.header, text="SCtest Dashboard", font=("Segoe UI", 22, "bold"), text_color="#1A1A1A")
        self.lbl_titre.place(relx=0.02, rely=0.5, anchor="w")
        self.lbl_mobile_status = ctk.CTkLabel(self.header, text="📱 App Mobile : En attente...", text_color="orange", font=("Segoe UI", 12, "bold"))
        self.lbl_mobile_status.place(relx=0.80, rely=0.5, anchor="e")
        self.status_indicator = ctk.CTkLabel(self.header, text="● USB Déconnecté", text_color="red", font=("Segoe UI", 14))
        self.status_indicator.place(relx=0.98, rely=0.5, anchor="e")

        # --- MAIN ---
        self.main_view = ctk.CTkFrame(self, fg_color="transparent")
        self.main_view.pack(fill="both", expand=True, padx=20, pady=20)
        self.main_view.grid_columnconfigure(0, weight=1)
        self.main_view.grid_columnconfigure(1, weight=2)

        # 1. INFO
        self.card_info = self.create_card(self.main_view, "Device Information", 0, 0)
        self.lbl_model = ctk.CTkLabel(self.card_info, text="Connectez un appareil...", text_color="gray")
        self.lbl_model.pack(pady=20)

        # 2. CONTROL
        self.card_ctrl = self.create_card(self.main_view, "Actions", 1, 0)
        ctk.CTkButton(self.card_ctrl, text="Arrêter", fg_color="#FF3B30", command=self.close_app).pack(pady=10)

        # 3. DIAGNOSTICS
        self.card_diag = self.create_card(self.main_view, "Tests Fonctionnels", 0, 1)
        self.card_diag.grid(rowspan=2, sticky="nsew")
        self.create_test_grid()

        self.init_adb_tunnel()

        threading.Thread(target=self.usb_loop, daemon=True).start()
        threading.Thread(target=self.socket_server_loop, daemon=True).start()

    def create_card(self, parent, title, row, col):
        card = ctk.CTkFrame(parent, fg_color="white", corner_radius=12, border_width=1, border_color="#E5E5E5")
        card.grid(row=row, column=col, sticky="nsew", padx=10, pady=10)
        ctk.CTkLabel(card, text=f"▍ {title}", font=("Segoe UI", 15, "bold"), text_color="#F29F05").pack(anchor="w", padx=20, pady=15)
        return card

    def create_test_grid(self):
        grid_frame = ctk.CTkFrame(self.card_diag, fg_color="transparent")
        grid_frame.pack(fill="both", expand=True, padx=10, pady=10)
        
        for index, (test_name, icon) in enumerate(TESTS_LIST):
            row = index // 4
            col = index % 4
            # Mapping simple pour l'envoi
            cmd_name = test_name.upper().replace(" ", "_").replace("É", "E").replace("È", "E").replace(".", "").replace("(", "").replace(")", "")
            if test_name == "Accéléromètre": cmd_name = "ACCEL"
            if test_name == "Proximité": cmd_name = "PROXIMITE"

            btn = ctk.CTkButton(grid_frame, text=f"{icon}\n{test_name}", font=("Segoe UI", 12),
                                width=100, height=80, fg_color="#F0F0F5", text_color="#333",
                                hover_color="#E0E0E5",
                                command=lambda t=test_name, c=cmd_name: self.run_remote_test(t, c))
            btn.grid(row=row, column=col, padx=10, pady=10)
            self.test_buttons[test_name] = btn

    def init_adb_tunnel(self):
        print("Tentative tunnel ADB...")
        try:
            subprocess.run([self.adb_path, "reverse", "tcp:6000", "tcp:6000"], creationflags=subprocess.CREATE_NO_WINDOW)
            print("✅ Tunnel ADB OK")
        except: pass

    # --- MAPPING ET VALIDATION ---
    def map_command_to_test_name(self, command_status):
        # Format: TEST_NOM_OK ou TEST_NOM_FAIL
        if not command_status.startswith("TEST_"): return None, None
        
        status = "OK" if command_status.endswith("_OK") else "KO"
        raw_name = command_status.replace("TEST_", "").replace("_OK", "").replace("_FAIL", "")

        # Mapping inverse (Mobile -> PC)
        if raw_name == "ACCEL": return "Accéléromètre", status
        if raw_name == "PROXIMITE": return "Proximité", status
        if raw_name == "HP_ECOUTEUR": return "HP Écouteur", status
        if raw_name == "HP_BAS": return "HP Bas (Média)", status
        if raw_name == "ECRAN": return "Écran", status
        if raw_name == "FLASH": return "Flash", status
        if raw_name == "VIBREUR": return "Vibreur", status
        if raw_name == "BOUTONS_VOL": return "Boutons Vol", status
        if raw_name == "MIC_AVANT": return "Micro Avant", status
        if raw_name == "MIC_ARRIERE": return "Micro Arr.", status
        
        return None, None

    def validate_button(self, btn_name, status):
        col = "#34C759" if status == "OK" else "#FF3B30"
        if btn_name in self.test_buttons:
            self.test_buttons[btn_name].configure(fg_color=col, text_color="white")
            print(f"✅ Test {btn_name} validé par le mobile: {status}!")

    # --- SERVEUR ---
    def socket_server_loop(self):
        HOST = '0.0.0.0'
        PORT = 6000
        try:
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.bind((HOST, PORT))
            self.server_socket.listen()
            while not self.stop_thread:
                conn, addr = self.server_socket.accept()
                self.mobile_client = conn
                self.mobile_connected = True
                self.after(0, lambda: self.lbl_mobile_status.configure(text="📱 Connecté", text_color="#34C759"))
                try:
                    while True:
                        data = conn.recv(1024)
                        if not data: break
                        msg = data.decode('utf-8').strip()
                        print(f"Reçu: {msg}")
                        
                        # Synchro auto
                        if msg.startswith("TEST_"):
                            name, status = self.map_command_to_test_name(msg)
                            if name: self.after(0, lambda: self.validate_button(name, status))

                        if msg.startswith("TRIGGERED:"):
                             # Ouvre popup manuelle pour les HP
                             raw = msg.replace("TRIGGERED:", "")
                             name = "HP Bas (Média)" if raw == "HP_BAS" else "HP Écouteur"
                             self.after(0, lambda: self.open_validation_popup(name))
                except: pass
                self.mobile_connected = False
                self.mobile_client = None
                self.after(0, lambda: self.lbl_mobile_status.configure(text="📱 Déconnecté", text_color="orange"))
        except Exception as e: print(f"Err Server: {e}")

    def run_remote_test(self, test_name, cmd_name):
        if self.mobile_connected:
            try: self.mobile_client.sendall(cmd_name.encode('utf-8'))
            except: pass

    def open_validation_popup(self, test_name):
        dialog = ctk.CTkToplevel(self)
        dialog.title(f"Validation : {test_name}")
        dialog.geometry("300x200")
        dialog.attributes("-topmost", True)
        ctk.CTkLabel(dialog, text=f"Test : {test_name}", font=("Segoe UI", 16, "bold")).pack(pady=20)
        def set_res(res):
            self.validate_button(test_name, res)
            dialog.destroy()
        btn_frame = ctk.CTkFrame(dialog, fg_color="transparent")
        btn_frame.pack(pady=20)
        ctk.CTkButton(btn_frame, text="✅ OUI", fg_color="#34C759", width=100, command=lambda: set_res("OK")).pack(side="left", padx=10)
        ctk.CTkButton(btn_frame, text="❌ NON", fg_color="#FF3B30", width=100, command=lambda: set_res("KO")).pack(side="right", padx=10)

    def usb_loop(self):
        while not self.stop_thread:
            try:
                res = subprocess.run([self.adb_path, "devices"], capture_output=True, text=True, creationflags=subprocess.CREATE_NO_WINDOW)
                if "device" in res.stdout and len(res.stdout.strip().split('\n')) > 1:
                     self.update_status(True, "Android Connecté")
                else:
                     self.update_status(False, "Déconnecté")
            except: pass
            time.sleep(2)

    def update_status(self, connected, text):
        self.status_indicator.configure(text=f"● {text}", text_color="#34C759" if connected else "#FF3B30")

    def close_app(self):
        self.stop_thread = True
        try: self.server_socket.close()
        except: pass
        self.destroy()

if __name__ == "__main__":
    app = SCtestApp()
    app.protocol("WM_DELETE_WINDOW", app.close_app)
    app.mainloop()