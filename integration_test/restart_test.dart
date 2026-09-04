// Run twice with --dart-define=RESTART_STAGE=seed, then verify, terminating the app between runs.
import 'dart:convert';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shrimphony/app.dart';
import 'package:shrimphony/jellyfin.dart';
import 'package:shrimphony/playback.dart';
import '../test/support/jellyfin_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'queue and offline playback survive actual process restart',
    (tester) async {
      const seed = String.fromEnvironment('RESTART_STAGE') == 'seed';
      final directory = Directory(
        '${(await getApplicationSupportDirectory()).path}/shrimphony-restart-check',
      );
      await directory.create(recursive: true);
      final sessionFile = File('${directory.path}/test-session.json');
      final expectedFile = File('${directory.path}/expected.json');
      final store = JellyfinSessionStore(supportDirectory: directory);
      TestMusicServer? server;
      late JellyfinSession session;
      if (seed) {
        server = TestMusicServer();
        await server.start();
        session = server.session;
        await sessionFile.writeAsString(
          jsonEncode(session.toJson()),
          flush: true,
        );
      } else {
        session = JellyfinSession.fromJson(
          (jsonDecode(await sessionFile.readAsString()) as Map)
              .cast<String, dynamic>(),
        );
      }
      // Only the test server's dummy token is used. Personal saved accounts are untouched.
      FlutterSecureStorage.setMockInitialValues({
        'jellyfin_session': jsonEncode(session.toJson()),
      });
      final handler = await AudioService.init<JellyfinAudioHandler>(
        builder: () => JellyfinAudioHandler(store),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.thomaskleckner.shrimphony.restart',
          androidNotificationChannelName: 'Restart check',
        ),
      );
      await handler.initialize();
      if (seed) {
        final client = JellyfinClient(session);
        final song = JellyfinItem.fromJson(server!.tracks.first);
        await store.downloadTrack(session, client, song);
        await handler.playItems(
          List.generate(500, (i) => song.copyWith(name: 'Restart song $i')),
          shuffle: true,
        );
        await handler.pause();
        await handler.skipToQueueItem(250);
        await handler.seek(const Duration(seconds: 9));
        await handler.setRepeatMode(AudioServiceRepeatMode.one);
        await handler.pause();
        await expectedFile.writeAsString(
          jsonEncode(handler.queue.value.map((item) => item.title).toList()),
          flush: true,
        );
        debugPrint(
          'RESTART SEEDED: 500 entries, index 250, 9 seconds, shuffled, repeat one, offline WAV',
        );
        await handler.disposePlayer();
        await server.close();
        client.close();
      } else {
        expect(
          handler.queue.value.map((item) => item.title),
          jsonDecode(await expectedFile.readAsString()),
        );
        expect(handler.playbackState.value.queueIndex, 250);
        expect(handler.playbackState.value.position.inSeconds, 9);
        expect(
          handler.playbackState.value.shuffleMode,
          AudioServiceShuffleMode.all,
        );
        expect(
          handler.playbackState.value.repeatMode,
          AudioServiceRepeatMode.one,
        );
        final controller = AppController(store);
        await controller.initialize();
        expect(controller.status, AppStatus.error);
        expect(controller.downloads, hasLength(1));
        handler.attachClient(controller.client);
        await tester.pumpWidget(
          ShrimphonyApp(controller: controller, audioHandler: handler),
        );
        await tester.pumpAndSettle();
        expect(find.text('Library'), findsOneWidget);
        await handler.play();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await handler.pause();
        expect(
          handler.playbackState.value.position.inMilliseconds,
          greaterThan(9000),
        );
        final car = await handler.getChildren('browse:downloads');
        await handler.playFromMediaId(
          car.firstWhere((item) => item.playable == true).id,
        );
        await handler.pause();
        debugPrint(
          'RESTART VERIFIED: complete queue/state restored; phone and car play local audio with original server stopped',
        );
        await handler.disposePlayer();
        controller.dispose();
        await tester.pumpWidget(const SizedBox());
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
