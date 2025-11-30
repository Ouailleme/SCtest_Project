import sys
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.diagnostics import DiagnosticsService
from pymobiledevice3.exceptions import NoDeviceConnectedError, PyMobileDevice3Exception

def main():
    print("\n" + "#"*40)
    print("   🔋 SCtest v1.2 - BATTERY INSPECTOR 🔋")
    print("#"*40)
    print("Connexion au système de gestion d'énergie...")

    try:
        # 1. Connexion de base (Lockdown)
        lockdown = create_using_usbmux()
        
        if not lockdown:
            print("❌ Aucun appareil trouvé via USB.")
            return

        # 2. On récupère le nom pour confirmer la connexion
        nom_appareil = lockdown.get_value(key='DeviceName')
        print(f"✅ Cible verrouillée : {nom_appareil}")

        # 3. LE COEUR DU RÉACTEUR : Service de Diagnostic
        print("💉 Injection de la demande de diagnostic...")
        diag_service = DiagnosticsService(lockdown=lockdown)
        
        # On demande les infos brutes de la batterie (GasGauge)
        battery_info = diag_service.get_battery()

        # 4. On extrait les données précieuses
        # Note : Les clés peuvent varier légèrement selon les modèles, on sécurise avec .get()
        cycle_count = battery_info.get('CycleCount', 'N/A')
        design_cap = battery_info.get('DesignCapacity', 'N/A')
        current_cap = battery_info.get('AppleRawMaxCapacity', 'N/A')
        
        # Calcul du pourcentage de santé réel (si les données sont dispos)
        sante = "Inconnue"
        if isinstance(current_cap, int) and isinstance(design_cap, int):
            sante_pct = (current_cap / design_cap) * 100
            sante = f"{sante_pct:.1f}%"

        # 5. AFFICHAGE DU RAPPORT
        print("\n" + "="*30)
        print("       RAPPORT BATTERIE")
        print("="*30)
        print(f"⚡ Cycles de charge : {cycle_count}")
        print(f"❤️ Santé Réelle     : {sante}")
        print(f"📏 Capacité Usine   : {design_cap} mAh")
        print(f"📉 Capacité Actuelle: {current_cap} mAh")
        print(f"🌡️ Température      : {battery_info.get('Temperature', 0) / 100}°C")
        print("="*30)

    except PyMobileDevice3Exception:
        print("\n🔒 ERREUR : L'accès aux diagnostics est refusé.")
        print("-> Assure-toi que l'iPhone est déverrouillé.")
        print("-> Essaie de débrancher/rebrancher.")

    except Exception as e:
        print(f"\n⚠️ Erreur technique : {e}")

if __name__ == "__main__":
    main()