import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'jellyfin.dart';
import 'playback.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = JellyfinSessionStore();
  final handler = await AudioService.init<JellyfinAudioHandler>(
    builder: () => JellyfinAudioHandler(store),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.thomaskleckner.shrimphony.playback',
      androidNotificationChannelName: 'Music playback',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      artDownscaleWidth: 512,
      artDownscaleHeight: 512,
      androidBrowsableRootExtras: {AndroidContentStyle.supportedKey: true},
    ),
  );
  await handler.initialize();

  final controller = AppController(store);
  JellyfinClient? attachedClient;
  void syncPlaybackClient() {
    final next = controller.client;
    if (!identical(next, attachedClient)) {
      attachedClient = next;
      handler.attachClient(next);
    }
  }

  controller.addListener(syncPlaybackClient);

  const carPlay = MethodChannel('com.thomaskleckner.shrimphony/carplay');
  carPlay.setMethodCallHandler((call) async {
    final arguments =
        (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
    switch (call.method) {
      case 'catalog':
        return handler.vehicleCatalog(arguments['id'] as String? ?? 'root');
      case 'play':
        await handler.vehiclePlay(arguments['id'] as String? ?? '');
        return null;
      default:
        throw MissingPluginException('Unknown CarPlay method ${call.method}');
    }
  });

  runApp(ShrimphonyApp(controller: controller, audioHandler: handler));
  await controller.initialize();
  syncPlaybackClient();
}
