import socket
import os
from datetime import datetime
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
import threading
import tkinter as tk
from tkinter import messagebox

BUILD_DIR = os.path.join(os.path.dirname(__file__), 'build', 'SCtest')
PDF_TEMPLATE = 'rapport_diagnostic_{date}.pdf'
PORT = 6000
HOST = '127.0.0.1'

os.makedirs(BUILD_DIR, exist_ok=True)

class RapportApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title('SCtest - Réception Diagnostic')
        self.geometry('400x300')
        self.status_var = tk.StringVar(value='En attente de connexion...')
        self.pdf_listbox = tk.Listbox(self)
        self.pdf_listbox.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        self.status_label = tk.Label(self, textvariable=self.status_var)
        self.status_label.pack(pady=5)
        self.open_btn = tk.Button(self, text='Ouvrir le PDF sélectionné', command=self.open_selected_pdf)
        self.open_btn.pack(pady=5)
        self.refresh_pdf_list()

    def refresh_pdf_list(self):
        self.pdf_listbox.delete(0, tk.END)
        pdfs = [f for f in os.listdir(BUILD_DIR) if f.endswith('.pdf')]
        pdfs.sort(reverse=True)
        for pdf in pdfs:
            self.pdf_listbox.insert(tk.END, pdf)

    def add_pdf(self, pdf_path):
        self.refresh_pdf_list()
        self.status_var.set(f'Nouveau rapport reçu: {os.path.basename(pdf_path)}')
        self.pdf_listbox.selection_clear(0, tk.END)
        self.pdf_listbox.selection_set(0)
        self.pdf_listbox.activate(0)
        self.update()
        try:
            os.startfile(pdf_path)
        except Exception as e:
            messagebox.showerror('Erreur', f'Impossible d\'ouvrir le PDF: {e}')

    def open_selected_pdf(self):
        selection = self.pdf_listbox.curselection()
        if not selection:
            messagebox.showinfo('Info', 'Sélectionnez un rapport PDF dans la liste.')
            return
        pdf_name = self.pdf_listbox.get(selection[0])
        pdf_path = os.path.join(BUILD_DIR, pdf_name)
        try:
            os.startfile(pdf_path)
        except Exception as e:
            messagebox.showerror('Erreur', f'Impossible d\'ouvrir le PDF: {e}')

app_instance = None

def generate_pdf(report_dict):
    date_str = datetime.now().strftime('%Y%m%d_%H%M%S')
    pdf_path = os.path.join(BUILD_DIR, PDF_TEMPLATE.format(date=date_str))
    c = canvas.Canvas(pdf_path, pagesize=A4)
    c.setFont('Helvetica-Bold', 20)
    c.drawString(50, 800, 'Rapport diagnostic complet')
    c.setFont('Helvetica', 12)
    y = 760
    for test, result in report_dict.items():
        color = {'OK': (0, 0.6, 0), 'KO': (0.8, 0, 0), 'NON_TESTE': (0.6, 0.6, 0)}.get(result, (0,0,0))
        c.setFillColorRGB(*color)
        c.drawString(60, y, f'{test} : {result}')
        y -= 24
    c.save()
    print(f'PDF généré : {pdf_path}')
    if app_instance:
        app_instance.add_pdf(pdf_path)

def parse_report(raw):
    items = raw.strip().split(';')
    return dict(item.split(':') for item in items if ':' in item)

def server_thread():
    global app_instance
    print(f'Attente du rapport sur {HOST}:{PORT}...')
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind((HOST, PORT))
        s.listen(1)
        while True:
            conn, addr = s.accept()
            with conn:
                print(f'Connecté à {addr}')
                if app_instance:
                    app_instance.status_var.set(f'Connecté à {addr}')
                while True:
                    data = conn.recv(4096)
                    if not data:
                        break
                    msg = data.decode('utf-8').strip()
                    if msg.startswith('DIAGNOSTIC_RAPPORT:'):
                        report_raw = msg[len('DIAGNOSTIC_RAPPORT:'):]
                        report_dict = parse_report(report_raw)
                        generate_pdf(report_dict)
                        if app_instance:
                            app_instance.status_var.set('Rapport reçu et PDF généré.')

if __name__ == '__main__':
    app_instance = RapportApp()
    threading.Thread(target=server_thread, daemon=True).start()
    app_instance.mainloop()
