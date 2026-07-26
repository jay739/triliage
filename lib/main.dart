import 'dart:async';

import 'package:flutter/material.dart';

import 'src/app_session.dart';
import 'src/storage/credential_store.dart';
import 'src/ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final session = AppSession(store: const SecureCredentialStore());
  // Not awaited on purpose: the UI shows a splash until restore() flips the
  // session out of its restoring state, so blocking startup buys nothing.
  unawaited(session.restore());

  runApp(TriliageApp(session: session));
}
