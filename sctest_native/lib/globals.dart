// Variable globale pour faire passer les événements natifs (Boutons, Capteurs) vers l'interface active
// Utilisée par MainActivity.kt (via MethodChannel) pour parler à l'écran actuel
Function(String)? onGlobalNativeEvent;