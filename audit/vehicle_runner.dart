// Simulator-only manual vehicle acceptance: flutter run -t audit/vehicle_runner.dart
// --dart-define-from-file=/private/path/session-defines.json. Reinstall the normal
// app afterward; never distribute an artifact containing the test session.
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:shrimphony/jellyfin.dart';
import 'package:shrimphony/main.dart' as app;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const encoded = String.fromEnvironment('LIVE_SESSION');
  if (encoded.isEmpty) {
    throw StateError('Provide LIVE_SESSION for simulator QA.');
  }
  await JellyfinSessionStore().save(
    JellyfinSession.fromJson(
      (jsonDecode(encoded) as Map).cast<String, dynamic>(),
    ),
  );
  await app.main();
}
