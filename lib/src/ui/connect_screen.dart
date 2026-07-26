import 'package:flutter/material.dart';

import '../app_session.dart';
import '../etapi/etapi_client.dart';
import '../etapi/etapi_exception.dart';
import '../storage/connection_profile.dart';

/// How the user proves who they are.
enum AuthMode { token, password }

/// First-run screen: point triliage at a Trilium instance and authenticate.
///
/// Connecting always performs a real `app-info` call before anything is saved,
/// so "Connect" succeeding means the credentials genuinely work rather than
/// merely being well-formed.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.session});

  final AppSession session;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _secretController = TextEditingController();

  AuthMode _mode = AuthMode.token;
  bool _obscureSecret = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.session.restoreError;
  }

  @override
  void dispose() {
    _serverController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final serverUrl = _serverController.text.trim();
      final secret = _secretController.text;

      // Password mode is a convenience wrapper: the session exchanges the
      // password for a token, stores only the token, and the password is never
      // held beyond this method.
      await switch (_mode) {
        AuthMode.token => widget.session.connect(
            ConnectionProfile(serverUrl: serverUrl, token: secret),
          ),
        AuthMode.password => widget.session.connectWithPassword(
            serverUrl: serverUrl,
            password: secret,
          ),
      };
      // On success the session flips to connected and this screen is replaced,
      // so there is deliberately no post-success setState here.
    } on EtapiException catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Turns an exception into something worth reading, with the likely fix.
  String _describe(EtapiException e) {
    return switch (e) {
      EtapiHttpException(isAuthFailure: true) => _mode == AuthMode.token
          ? 'Trilium rejected that token. Check it under Options, ETAPI.'
          : 'Trilium rejected that password.',
      EtapiHttpException(statusCode: 404) =>
        'No Trilium API at that URL. Check the address.',
      EtapiHttpException(:final message) => message,
      EtapiNetworkException(:final message) =>
        'Could not reach the server. $message',
      EtapiFormatException(:final message) => message,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToken = _mode == AuthMode.token;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Connect to Trilium', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'triliage talks to your own Trilium instance over its '
                    'External API. Nothing is sent anywhere else.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _serverController,
                    autofocus: true,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'https://notes.example.com',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    validator: _validateServer,
                  ),
                  const SizedBox(height: 20),
                  SegmentedButton<AuthMode>(
                    segments: const [
                      ButtonSegment(
                        value: AuthMode.token,
                        label: Text('ETAPI token'),
                        icon: Icon(Icons.key_outlined),
                      ),
                      ButtonSegment(
                        value: AuthMode.password,
                        label: Text('Password'),
                        icon: Icon(Icons.lock_outline),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: _busy
                        ? null
                        : (selection) => setState(() {
                              _mode = selection.first;
                              _error = null;
                            }),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _secretController,
                    enabled: !_busy,
                    obscureText: _obscureSecret,
                    decoration: InputDecoration(
                      labelText: isToken ? 'ETAPI token' : 'Trilium password',
                      helperText: isToken
                          ? 'Trilium: Options, ETAPI, Create new token'
                          : 'Exchanged for a token once. The password is not stored.',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureSecret
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        tooltip: _obscureSecret ? 'Show' : 'Hide',
                        onPressed: () =>
                            setState(() => _obscureSecret = !_obscureSecret),
                      ),
                    ),
                    onFieldSubmitted: (_) => _busy ? null : _submit(),
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'Required'
                        : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 20),
                    _ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Connect'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String? _validateServer(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    try {
      normalizeBaseUrl(value);
      return null;
    } on EtapiFormatException catch (e) {
      return e.message;
    }
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
