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

Future<void> waitFor(
  WidgetTester tester,
  bool Function() condition, {
  int seconds = 30,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('App condition timed out');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  testWidgets(
    'phone workflows, real audio queue, restart and offline car contracts',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final server = TestMusicServer();
      await server.start();
      final directory = await Directory.systemTemp.createTemp(
        'shrimphony-device-test-',
      );
      final store = JellyfinSessionStore(supportDirectory: directory);
      final handler = await AudioService.init<JellyfinAudioHandler>(
        builder: () => JellyfinAudioHandler(store),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.thomaskleckner.shrimphony.test',
          androidNotificationChannelName: 'Playback tests',
          androidStopForegroundOnPause: false,
        ),
      );
      File? carCacheProbe;
      if (Platform.isAndroid) {
        final cache = Directory(
          '${(await getTemporaryDirectory()).path}/android-auto-artwork',
        );
        await cache.create(recursive: true);
        carCacheProbe = File('${cache.path}/qa-cleanup-probe');
        await carCacheProbe.writeAsString('fixture');
      }
      await handler.initialize();
      if (carCacheProbe != null) expect(await carCacheProbe.exists(), isFalse);
      var controller = AppController(store);
      JellyfinClient? attached;
      JellyfinAudioHandler? restored;
      void attach() {
        if (!identical(attached, controller.client)) {
          attached = controller.client;
          handler.attachClient(attached);
        }
      }

      controller.addListener(attach);
      try {
        await controller.initialize();
        await tester.pumpWidget(
          ShrimphonyApp(controller: controller, audioHandler: handler),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Connect'));
        await tester.pumpAndSettle();
        expect(
          find.text('Enter your Jellyfin server address.'),
          findsOneWidget,
        );
        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), server.session.serverUrl);
        await tester.enterText(fields.at(1), 'Tester');
        await tester.enterText(fields.at(2), 'wrong');
        await tester.ensureVisible(find.text('Connect'));
        await tester.tap(find.text('Connect'));
        await waitFor(
          tester,
          () =>
              controller.status == AppStatus.signedOut &&
              controller.errorMessage != null,
        );
        expect(controller.errorMessage, isNotNull);
        await tester.pumpAndSettle();
        await tester.ensureVisible(fields.at(2));
        await tester.tap(fields.at(2));
        await tester.pumpAndSettle();
        await tester.enterText(fields.at(2), 'test-password');
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(fields.at(2)).controller!.text,
          'test-password',
        );
        await tester.ensureVisible(find.text('Connect'));
        await tester.tap(find.text('Connect'));
        await waitFor(tester, () => controller.status == AppStatus.ready);
        expect(controller.songs, hasLength(12));
        debugPrint(
          'PASS sign-in validation, failed and successful authentication, library refresh',
        );

        server.brokenAudio = true;
        await expectLater(
          handler.playItems(controller.songs.take(2).toList()),
          throwsA(isA<Exception>()),
        );
        await tester.pumpAndSettle();
        expect(handler.playbackState.value.errorMessage, isNotNull);
        expect(handler.queue.value, hasLength(2));
        expect(find.byTooltip('Retry playback'), findsWidgets);
        server.brokenAudio = false;
        await tester.tap(find.byTooltip('Retry playback').first);
        await waitFor(
          tester,
          () =>
              handler.playbackState.value.playing &&
              handler.playbackState.value.errorMessage == null,
        );
        await handler.pause();
        debugPrint(
          'PASS playback failure keeps queue visible and Retry resumes native audio',
        );
        await handler.clearQueue();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Library').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Artists').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Test Artist').last);
        await waitFor(tester, () => find.text('Play').evaluate().isNotEmpty);
        await tester.ensureVisible(find.text('Play'));
        await tester.tap(find.text('Play'));
        await waitFor(
          tester,
          () =>
              handler.queue.value.length == 12 &&
              handler.playbackState.value.playing,
        );
        expect(handler.queue.value.first.title, 'Z first');
        await handler.seek(const Duration(seconds: 3));
        await handler.pause();
        expect(
          handler.playbackState.value.position.inSeconds,
          greaterThanOrEqualTo(2),
        );
        await handler.play();
        await handler.skipToNext();
        await waitFor(
          tester,
          () => handler.mediaItem.value?.title == 'A second',
        );
        await handler.skipToPrevious();
        await handler.pause();
        await waitFor(
          tester,
          () => server.reports.any(
            (report) =>
                report['path'] == '/Sessions/Playing/Stopped' &&
                report['ItemId'] == 'song-0' &&
                (report['PositionTicks'] as num) >= 20000000,
          ),
        );
        debugPrint(
          'PASS artist Play includes all songs; native play/pause/seek/next/previous',
        );
        await tester.tap(find.byTooltip('Download all songs'));
        await waitFor(
          tester,
          () =>
              controller.downloads.length == 12 &&
              controller.downloadingItem == null,
        );
        expect(controller.artworkUris, isNotEmpty);
        debugPrint('PASS artist download-all and durable artwork');
        await tester.pageBack();
        await tester.pumpAndSettle();

        final fiveHundred = List.generate(
          500,
          (i) => JellyfinItem.fromJson(
            server.tracks[i % 12],
          ).copyWith(name: 'Queue song $i'),
        );
        await handler.playItems(fiveHundred, initialIndex: 250, shuffle: true);
        await handler.pause();
        await handler.setRepeatMode(AudioServiceRepeatMode.all);
        await handler.seek(const Duration(seconds: 7));
        await handler.pause();
        final current = handler.mediaItem.value!.id;
        final index = handler.playbackState.value.queueIndex!;
        final next = JellyfinItem.fromJson(
          server.tracks[2],
        ).copyWith(name: 'Explicit Play Next');
        await handler.playNext(next);
        expect(handler.queue.value[index + 1].title, next.name);
        await handler.skipToNext();
        await waitFor(
          tester,
          () => handler.mediaItem.value?.title == next.name,
        );
        await handler.moveQueueItem(
          handler.queue.value.length - 1,
          handler.playbackState.value.queueIndex! + 1,
        );
        final visibleNext =
            handler.queue.value[handler.playbackState.value.queueIndex! + 1];
        await handler.skipToNext();
        await waitFor(
          tester,
          () => handler.mediaItem.value?.id == visibleNext.id,
        );
        await handler.removeQueueItem(
          handler.queue.value.firstWhere((item) => item.id == current),
        );
        expect(handler.queue.value, hasLength(500));
        await handler.seek(const Duration(seconds: 7));
        await handler.pause();
        final saved = await store.loadPlayback();
        expect(saved!['queue'], hasLength(500));
        expect(saved['shuffle'], isTrue);
        expect(saved['repeat'], 'all');
        final names = handler.queue.value.map((item) => item.title).toList();
        await handler.disposePlayer();
        restored = JellyfinAudioHandler(store);
        await restored.initialize();
        expect(restored.queue.value.map((item) => item.title), names);
        expect(
          restored.playbackState.value.shuffleMode,
          AudioServiceShuffleMode.all,
        );
        expect(
          restored.playbackState.value.repeatMode,
          AudioServiceRepeatMode.all,
        );
        expect(restored.playbackState.value.queueIndex, saved['index']);
        expect(restored.playbackState.value.position.inSeconds, 7);
        debugPrint(
          'PASS native shuffled Play Next/reorder/remove and complete 500-track restore with position/repeat',
        );

        controller.removeListener(attach);
        controller.dispose();
        server.status = 503;
        controller = AppController(store);
        await controller.initialize();
        restored.attachClient(controller.client);
        await tester.pumpWidget(
          ShrimphonyApp(controller: controller, audioHandler: restored),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Server unavailable'),
          findsNothing,
          reason: 'Downloads must retain access to app navigation',
        );
        await tester.tap(find.text('Search').last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(SearchBar), 'Test Artist');
        await tester.pump(const Duration(milliseconds: 500));
        await waitFor(tester, () => find.text('Songs').evaluate().isNotEmpty);
        final before = server.requests
            .where((uri) => !uri.path.startsWith('/Sessions/'))
            .length;
        final car = await restored.getChildren('browse:downloads');
        expect(car, isNotEmpty);
        await restored.playFromMediaId(
          car.firstWhere((item) => item.playable == true).id,
        );
        await restored.seek(const Duration(seconds: 5));
        await restored.skipToNext();
        await restored.pause();
        expect(
          server.requests
              .where((uri) => !uri.path.startsWith('/Sessions/'))
              .length,
          before,
        );
        final libraryRoutes = await restored.getChildren('browse:library');
        expect(
          libraryRoutes.map((item) => item.id),
          containsAll(['browse:downloads', 'browse:playlists']),
        );
        expect(await restored.vehicleCatalog('root'), hasLength(4));
        debugPrint(
          'PASS offline phone search, offline car selection with zero metadata/audio requests, car routes',
        );

        await tester.tap(find.byTooltip('More options').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Privacy'), 300);
        await Scrollable.ensureVisible(
          tester.element(find.text('Privacy')),
          alignment: .3,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Privacy'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Your password is not saved.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Open-source licenses'), 200);
        await Scrollable.ensureVisible(
          tester.element(find.text('Open-source licenses')),
          alignment: .3,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open-source licenses'));
        await tester.pumpAndSettle();
        expect(find.byType(LicensePage), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Support and diagnostics'),
          200,
        );
        await Scrollable.ensureVisible(
          tester.element(find.text('Support and diagnostics')),
          alignment: .3,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Support and diagnostics'));
        await tester.pumpAndSettle();
        expect(find.text('Copy diagnostics'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        debugPrint(
          'PASS Settings privacy, open-source licenses and support diagnostics',
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
        tester.view.viewInsets = FakeViewPadding.zero;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Large-text narrow layout',
        );
        tester.view.physicalSize = const Size(740, 360);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Large-text landscape layout',
        );
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
        tester.view.resetViewInsets();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.pumpAndSettle();
        final semantics = tester.ensureSemantics();
        expect(find.byTooltip('More options'), findsWidgets);
        expect(find.byTooltip('Refresh library'), findsOneWidget);
        semantics.dispose();
        debugPrint(
          'PASS large-text portrait/landscape, dark theme, labeled navigation controls',
        );
        await restored.clearQueue();
        expect(restored.queue.value, isEmpty);
        expect((await store.loadPlayback())!['queue'], isEmpty);
        await restored.disposePlayer();
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await handler.disposePlayer();
        await restored?.disposePlayer();
        await server.close();
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets('complete library shuffle and paginated vehicle catalogs', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final server = TestMusicServer(songCount: 1000);
    await server.start();
    final directory = await Directory.systemTemp.createTemp(
      'shrimphony-library-check-',
    );
    final store = JellyfinSessionStore(supportDirectory: directory);
    await store.save(server.session);
    final handler = JellyfinAudioHandler(store);
    await handler.initialize();
    try {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await handler.shuffleLibrary();
      await waitFor(tester, () => handler.queue.value.length == 1000);
      await handler.pause();
      expect(
        handler.queue.value
            .map((item) => (item.extras!['jellyfin'] as Map)['Id'])
            .toSet(),
        hasLength(1000),
      );
      final albums = await handler.getChildren('browse:albums');
      expect(albums.where((item) => item.id.startsWith('action:')), isEmpty);
      var page = await handler.getChildren('MusicArtist:artist');
      final ids = <String>{};
      while (true) {
        ids.addAll(
          page
              .where((item) => item.id.startsWith('Audio:'))
              .map((item) => item.id),
        );
        final more = page
            .where((item) => item.id.startsWith('page:'))
            .firstOrNull;
        if (more == null) break;
        page = await handler.getChildren(more.id);
      }
      expect(ids, hasLength(1000));
      debugPrint(
        'PASS shared library shuffle loads all 1000 songs; car pagination reaches every song; category routes omit invalid collection actions',
      );
    } finally {
      await handler.disposePlayer();
      await server.close();
      await tester.pumpWidget(const SizedBox());
      await directory.delete(recursive: true);
    }
  });

  const live = String.fromEnvironment('LIVE_SESSION');
  if (live.isNotEmpty) {
    testWidgets(
      'real Jellyfin library and audio integration',
      (tester) async {
        final session = JellyfinSession.fromJson(
          (jsonDecode(live) as Map).cast<String, dynamic>(),
        );
        final directory = await Directory.systemTemp.createTemp(
          'shrimphony-live-test-',
        );
        final store = JellyfinSessionStore(supportDirectory: directory);
        FlutterSecureStorage.setMockInitialValues({});
        await store.save(session);
        final controller = AppController(store);
        final watch = Stopwatch()..start();
        await controller.connect(session);
        debugPrint(
          'LIVE refresh ${watch.elapsedMilliseconds}ms, ${controller.songs.length} songs, ${controller.albums.length} albums, ${controller.artists.length} artists',
        );
        expect(controller.status, AppStatus.ready);
        expect(controller.songs, isNotEmpty);
        final handler = JellyfinAudioHandler(store);
        await handler.initialize();
        handler.attachClient(controller.client);
        try {
          final albums = controller.albums;
          final tracks = await controller.children(albums.first);
          final songs = tracks.where((item) => item.isAudio).toList();
          expect(songs, isNotEmpty);
          watch.reset();
          await handler.playItems(songs);
          await waitFor(
            tester,
            () =>
                handler.playbackState.value.playing &&
                handler.playbackState.value.position.inMilliseconds > 100,
          );
          debugPrint('LIVE playback start ${watch.elapsedMilliseconds}ms');
          await handler.seek(const Duration(seconds: 10));
          await handler.pause();
          for (final quality in [
            StreamingQuality.high,
            StreamingQuality.dataSaver,
          ]) {
            controller.client!.preferences = controller.client!.preferences
                .copyWith(streamingQuality: quality);
            await handler.playItems(songs);
            await waitFor(
              tester,
              () =>
                  handler.playbackState.value.playing &&
                  handler.playbackState.value.position.inMilliseconds > 100,
            );
            await handler.seek(const Duration(seconds: 5));
            await Future<void>.delayed(const Duration(milliseconds: 300));
            await handler.pause();
            expect(
              handler.playbackState.value.position.inSeconds,
              greaterThanOrEqualTo(4),
            );
            debugPrint(
              'LIVE ${quality.name} AAC transcode playback and seek PASS',
            );
          }
          controller.client!.preferences = controller.client!.preferences
              .copyWith(streamingQuality: StreamingQuality.original);
          await controller.enqueueDownloads(songs.take(1));
          await waitFor(
            tester,
            () =>
                controller.downloadingItem == null &&
                controller.downloadQueue.isEmpty,
            seconds: 120,
          );
          expect(controller.downloads, hasLength(1));
          await handler.playItems(controller.downloads);
          await handler.pause();
          debugPrint(
            'LIVE downloaded playback PASS; container ${controller.downloads.single.container}',
          );
          final results = await controller.search(songs.first.name);
          expect(results.map((item) => item.id), contains(songs.first.id));
          final devices = await controller.devices();
          debugPrint(
            'LIVE search PASS, remote device API PASS (${devices.length} devices)',
          );
        } finally {
          await handler.disposePlayer();
          controller.dispose();
          await directory.delete(recursive: true);
        }
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
