import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

class BiometricTestWidget extends StatefulWidget {
  @override
  _BiometricTestWidgetState createState() => _BiometricTestWidgetState();
}

class _BiometricTestWidgetState extends State<BiometricTestWidget> {
  final LocalAuthentication auth = LocalAuthentication();
  String _authorized = 'Non authentifié';
  bool _isAuthenticating = false;

  Future<void> _authenticate() async {
    bool authenticated = false;
    setState(() {
      _isAuthenticating = true;
      _authorized = 'Authentification en cours...';
    });
    try {
      authenticated = await auth.authenticate(
        localizedReason: 'Veuillez vous authentifier',
        options: const AuthenticationOptions(
          useErrorDialogs: true,
          stickyAuth: true,
        ),
      );
      setState(() {
        _isAuthenticating = false;
        _authorized = authenticated ? 'Authentifié' : 'Échec de l\'authentification';
      });
    } catch (e) {
      setState(() {
        _isAuthenticating = false;
        _authorized = 'Erreur: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text('Statut: $_authorized'),
        SizedBox(height: 20),
        ElevatedButton(
          onPressed: _isAuthenticating ? null : _authenticate,
          child: Text('Tester la biométrie'),
        ),
      ],
    );
  }
}
