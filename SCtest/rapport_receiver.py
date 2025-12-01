import socket
import os
from datetime import datetime
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas

BUILD_DIR = os.path.join(os.path.dirname(__file__), 'build', 'SCtest')
PDF_TEMPLATE = 'rapport_diagnostic_{date}.pdf'
PORT = 16000
HOST = '127.0.0.1'

os.makedirs(BUILD_DIR, exist_ok=True)

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
    # Ouvre le PDF automatiquement (Windows)
    try:
        os.startfile(pdf_path)
    except Exception as e:
        print(f'Impossible d\'ouvrir le PDF automatiquement : {e}')

def parse_report(raw):
    # Format attendu: NomTest1:OK;NomTest2:KO;NomTest3:NON_TESTE;...
    items = raw.strip().split(';')
    return dict(item.split(':') for item in items if ':' in item)

def main():
    print(f'Attente du rapport sur {HOST}:{PORT}...')
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind((HOST, PORT))
        s.listen(1)
        while True:
            conn, addr = s.accept()
            with conn:
                print(f'Connecté à {addr}')
                while True:
                    data = conn.recv(4096)
                    if not data:
                        break
                    msg = data.decode('utf-8').strip()
                    if msg.startswith('DIAGNOSTIC_RAPPORT:'):
                        report_raw = msg[len('DIAGNOSTIC_RAPPORT:'):]
                        report_dict = parse_report(report_raw)
                        generate_pdf(report_dict)

if __name__ == '__main__':
    main()
