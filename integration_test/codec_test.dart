// Start audit/serve_audio_fixtures.py. Android: adb reverse tcp:8765 tcp:8765.
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shrimphony/jellyfin.dart';
import 'package:shrimphony/playback.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native format decoding, fallback and automatic track transition',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      const session = JellyfinSession(
        serverUrl: 'http://127.0.0.1:8765',
        accessToken: 'fixture',
        userId: 'fixture',
        username: 'Fixture',
        deviceId: 'fixture',
      );
      final directory = await Directory.systemTemp.createTemp(
        'shrimphony-codec-check-',
      );
      final store = JellyfinSessionStore(supportDirectory: directory);
      await store.save(session);
      final handler = await AudioService.init<JellyfinAudioHandler>(
        builder: () => JellyfinAudioHandler(store),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.thomaskleckner.shrimphony.codec',
          androidNotificationChannelName: 'Codec check',
        ),
      );
      await handler.initialize();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final failures = <String>[];
      try {
        for (final format in [
          'mp3',
          'aac',
          'm4a',
          'alac',
          'flac',
          'flac24',
          'flac32',
          'ogg',
          'opus',
          'wav',
        ]) {
          try {
            await handler.playItems([
              JellyfinItem(
                id: format,
                name: format,
                type: 'Audio',
                container: format == 'alac'
                    ? 'm4a'
                    : format.startsWith('flac')
                    ? 'flac'
                    : format,
                audioBitDepth: format == 'flac32'
                    ? 32
                    : format == 'flac24'
                    ? 24
                    : 16,
                duration: const Duration(seconds: 2),
              ),
            ]);
            final deadline = DateTime.now().add(const Duration(seconds: 5));
            while (handler.playbackState.value.position.inMilliseconds <= 100 &&
                DateTime.now().isBefore(deadline)) {
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            expect(
              handler.playbackState.value.processingState,
              isNot(AudioProcessingState.error),
            );
            expect(
              handler.playbackState.value.position.inMilliseconds,
              greaterThan(100),
            );
            await handler.pause();
            final song = JellyfinItem(
              id: format,
              name: format,
              type: 'Audio',
              container: format == 'alac'
                  ? 'm4a'
                  : format.startsWith('flac')
                  ? 'flac'
                  : format,
              audioBitDepth: format == 'flac32' ? 32 : 16,
              duration: const Duration(seconds: 2),
            );
            final api = JellyfinClient(session);
            await store.downloadTrack(session, api, song);
            api.close();
            await handler.playItems([song]);
            await Future<void>.delayed(const Duration(milliseconds: 300));
            expect(
              handler.playbackState.value.position.inMilliseconds,
              greaterThan(100),
            );
            await handler.pause();
            debugPrint('CODEC $format streaming and downloaded playback PASS');
          } on Object catch (error) {
            debugPrint(
              'STATE $format: ${handler.playbackState.value.processingState}, playing ${handler.playbackState.value.playing}, position ${handler.playbackState.value.position}, index ${handler.playbackState.value.queueIndex}',
            );
            failures.add(format);
            debugPrint('CODEC $format FAILED: $error');
          }
        }
        final song = const JellyfinItem(
          id: 'flac',
          name: 'Gapless fixture',
          type: 'Audio',
          container: 'flac',
        );
        await handler.playItems([song, song]);
        await Future<void>.delayed(const Duration(milliseconds: 2500));
        expect(handler.playbackState.value.queueIndex, 1);
        expect(
          handler.playbackState.value.position.inMilliseconds,
          lessThan(1500),
        );
        debugPrint(
          'AUTOMATIC adjacent FLAC track transition PASS (no manual skip)',
        );
        expect(failures, isEmpty);
      } finally {
        await handler.disposePlayer();
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
