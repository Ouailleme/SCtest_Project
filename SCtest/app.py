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
    ("Face ID", "🔓"), ("Boutons Vol", "Volumes"), ("Tactile", "👆")
]

# Liste des tests qui s'auto-valident
AUTO_VALIDATING_TESTS = [
    "Micro Avant", 
    "Micro Arr.", 
    "Écran", 
    "Flash", 
    "Vibreur"
]

class SCtestApp(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.title("SCtest Station - v10.1 (Final Sync)")
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
            cmd_name = test_name.replace("É", "E").replace(" ", "_").replace(".", "").replace("(", "").replace(")", "").upper()
            
            btn = ctk.CTkButton(grid_frame, text=f"{icon}\n{test_name}", font=("Segoe UI", 12),
                                width=100, height=80, fg_color="#F0F0F5", text_color="#333",
                                hover_color="#E0E0E5",
                                command=lambda t=test_name, c=cmd_name: self.run_remote_test(t, c))
            btn.grid(row=row, column=col, padx=10, pady=10)
            self.test_buttons[test_name] = btn

    def init_adb_tunnel(self):
        print("Tentative d'ouverture du tunnel ADB...")
        try:
            subprocess.run([self.adb_path, "reverse", "tcp:6000", "tcp:6000"], 
                           creationflags=subprocess.CREATE_NO_WINDOW)
            print("✅ Tunnel ADB ouvert avec succès !")
        except: 
            print("⚠️ ADB non trouvé")

    # --- LOGIQUE DE VALIDATION ---

    def map_command_to_test_name(self, command_status):
        # command_status exemple: TEST_HP_ECOUTEUR_OK
        
        if command_status.endswith("_OK"): status = "OK"
        elif command_status.endswith("_FAIL"): status = "KO"
        else: return None, None
        
        # Retire TEST_ et le statut
        core_name_raw = command_status.replace(f"_OK", "").replace(f"_FAIL", "").replace("TEST_", "")
        
        # MAPPING CORRIGÉ : On mappe le nom du signal vers le nom affiché sur le bouton
        if core_name_raw == "HP_ECOUTEUR": return "HP Écouteur", status
        if core_name_raw == "HP_BAS_MEDIA": return "HP Bas (Média)", status # Le mobile envoie ce format sans () ni espace
        if core_name_raw == "ECRAN": return "Écran", status
        if core_name_raw == "MIC_AVANT": return "Micro Avant", status
        if core_name_raw == "MIC_ARRIERE": return "Micro Arr.", status
        
        # Pour les noms simples (FLASH, VIBREUR, WIFI)
        return core_name_raw.title().replace("_", " "), status

    def validate_button(self, btn_name, status):
        col = "#34C759" if status == "OK" else "#FF3B30"
        if btn_name in self.test_buttons:
            self.test_buttons[btn_name].configure(fg_color=col, text_color="white")
            print(f"✅ Test {btn_name} validé par le mobile: {status}!")

    # --- SERVEUR SOCKET ---
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
                self.after(0, lambda: self.lbl_mobile_status.configure(text="📱 App Mobile : Connectée", text_color="#34C759"))
                
                try:
                    while True:
                        data = conn.recv(1024)
                        if not data: break
                        msg = data.decode('utf-8').strip()
                        print(f"Reçu du mobile: {msg}")
                        
                        # --- SYNCHRONISATION DE L'ÉTAT ---
                        if msg.startswith("TEST_") and (msg.endswith("_OK") or msg.endswith("_FAIL")):
                            final_test_name, status = self.map_command_to_test_name(msg)
                            if final_test_name in self.test_buttons:
                                self.after(0, lambda: self.validate_button(final_test_name, status))
                                
                        # --- DÉTECTION INFOS BATTERIE (Exemple) ---
                        if "INFO_BATTERY" in msg:
                            parts = msg.split(":")[1].split("|")
                            self.after(0, lambda: self.lbl_model.configure(text=f"Batterie: {parts[0]} - {parts[1]}", text_color="black"))

                except Exception as e: 
                    print(f"Erreur lecture: {e}")
                
                self.mobile_client = None
                self.mobile_connected = False
                self.after(0, lambda: self.lbl_mobile_status.configure(text="📱 App Mobile : Déconnectée", text_color="orange"))

        except Exception as e:
            if not self.stop_thread:
                print(f"Erreur Serveur: {e}")

    def run_remote_test(self, test_name, cmd_name):
        if self.mobile_connected and self.mobile_client:
            try:
                # Envoi de la commande simple (ex: HP_ECOUTEUR)
                self.mobile_client.sendall(cmd_name.encode('utf-8'))
                print(f"Commande envoyée au mobile : {cmd_name}")
            except Exception as e:
                print(f"Erreur envoi commande: {e}")
        
        # Le PC n'ouvre plus de popup. Il attend le résultat du mobile (ou le fait manuellement pour les HP).
        pass

    # --- DETECTION USB (Simplifié) ---
    def usb_loop(self):
        while not self.stop_thread:
            android = False
            try:
                adb_path = os.path.expandvars(r"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe")
                res = subprocess.run([adb_path, "devices"], capture_output=True, text=True, creationflags=subprocess.CREATE_NO_WINDOW)
                if len(res.stdout.strip().split('\n')) > 1 and "device" in res.stdout: android = True
            except: 
                pass

            if android: self.update_status(True, "Android Connecté")
            else: self.update_status(False, "Déconnecté")
            time.sleep(2)

    def update_status(self, connected, text):
        col = "#34C759" if connected else "#FF3B30"
        self.status_indicator.configure(text=f"● {text}", text_color=col)

    def close_app(self):
        self.stop_thread = True
        if self.server_socket:
            try:
                socket.socket(socket.AF_INET, socket.SOCK_STREAM).connect(('127.0.0.1', 6000))
            except:
                pass
            self.server_socket.close()
        self.destroy()

if __name__ == "__main__":
    app = SCtestApp()
    app.protocol("WM_DELETE_WINDOW", app.close_app)
    app.mainloop()