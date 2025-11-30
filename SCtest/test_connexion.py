import socket

HOST = '0.0.0.0'  # Écoute partout
PORT = 6000       # Le port du tunnel

print(f"--- 📡 SERVEUR EN ÉCOUTE SUR LE PORT {PORT} ---")
print("En attente que l'application Mobile se connecte...")

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.bind((HOST, PORT))
    s.listen()
    conn, addr = s.accept() # On attend une connexion ici (ça bloque tant que personne ne vient)
    
    with conn:
        print(f"\n✅ VICTOIRE ! Connexion reçue de : {addr}")
        
        while True:
            data = conn.recv(1024)
            if not data:
                break
            print(f"📩 Message du téléphone : {data.decode('utf-8')}")
            
            # On répond au téléphone
            conn.sendall(b"COUCOU_DU_PC")