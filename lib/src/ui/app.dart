import 'package:flutter/material.dart';

import '../app_session.dart';
import 'browse_screen.dart';
import 'connect_screen.dart';

/// Root widget. Owns the theme and picks the screen for the current session
/// state; there is no router yet because there are only two destinations.
class TriliageApp extends StatelessWidget {
  const TriliageApp({super.key, required this.session});

  final AppSession session;

  static const _seed = Color(0xFF4C6EF5);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'triliage',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) => switch (session.status) {
          SessionStatus.restoring => const _Splash(),
          SessionStatus.disconnected => ConnectScreen(
              // Keyed on the restore error so a newly failed restore rebuilds
              // the form with that message instead of reusing stale state.
              key: ValueKey(session.restoreError),
              session: session,
            ),
          SessionStatus.connected => BrowseScreen(session: session),
        },
      ),
    );
  }

  static ThemeData _theme(Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      ),
      visualDensity: VisualDensity.comfortable,
      useMaterial3: true,
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
