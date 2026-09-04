import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shrimphony/jellyfin.dart';
import 'package:shrimphony/playback.dart';
import 'support/jellyfin_server.dart';
import '../audit/launch_contract_test.dart' as audit;

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Condition did not become true');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  audit.main();
  late TestMusicServer server;
  late Directory directory;
  late JellyfinSessionStore store;
  late AppController controller;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    server = TestMusicServer();
    await server.start();
    directory = await Directory.systemTemp.createTemp(
      'shrimphony-reliability-',
    );
    store = JellyfinSessionStore(supportDirectory: directory);
    controller = AppController(store);
  });
  tearDown(() async {
    controller.dispose();
    await server.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await directory.delete(recursive: true);
  });

  test(
    'complete artist and multi-disc order, overlapping library deduplication',
    () async {
      await controller.connect(server.session);
      final album = await controller.children(
        const JellyfinItem(id: 'album', name: 'Album', type: 'MusicAlbum'),
      );
      expect(album.first.id, 'song-0');
      expect(album[6].parentIndexNumber, 2);
      final artist = await controller.children(
        const JellyfinItem(id: 'artist', name: 'Artist', type: 'MusicArtist'),
      );
      expect(artist.where((item) => item.isAudio), hasLength(12));
      final api = JellyfinClient(
        server.session,
        preferences: const AppPreferences(musicLibraryIds: {'a', 'b'}),
      );
      final merged = await api.songsForArtist('artist');
      expect(merged, hasLength(12));
      expect(
        merged.map((item) => item.id),
        List.generate(12, (i) => 'song-$i'),
      );
      api.close();
    },
  );

  test(
    'downloads retain artwork and collection ordering after offline cold connect',
    () async {
      await store.save(server.session);
      await controller.connect(server.session);
      final playlist = const JellyfinItem(
        id: 'playlist',
        name: 'Repeated Playlist',
        type: 'Playlist',
      );
      final children = await controller.children(playlist);
      expect(children.map((item) => item.id), ['song-0', 'song-1', 'song-0']);
      await controller.enqueueDownload(playlist);
      await until(
        () =>
            controller.downloads.length == 2 &&
            controller.downloadingItem == null,
      );
      expect(controller.artworkUris, contains('album'));
      controller.dispose();
      server.status = 503;
      controller = AppController(store);
      await controller.initialize();
      expect(controller.status, AppStatus.error);
      expect(controller.downloads, hasLength(2));
      final before = server.requests.length;
      expect((await controller.children(playlist)).map((item) => item.id), [
        'song-0',
        'song-1',
        'song-0',
      ]);
      expect(await controller.search('Test Artist'), isNotEmpty);
      expect(
        server.requests.length,
        before,
        reason: 'Offline search and details must not use the server',
      );
      expect(
        (await store.downloadedUris(server.session, [
          'song-0',
        ])).values.single.scheme,
        'file',
      );
    },
  );

  test(
    'failed jobs survive relaunch, retry succeeds, cancellation keeps completed files',
    () async {
      await store.save(server.session);
      await controller.connect(server.session);
      final tracks = controller.songs;
      server.brokenAudio = true;
      await controller.enqueueDownloads([tracks.first]);
      await until(
        () =>
            controller.failedDownloads.length == 1 &&
            controller.downloadingItem == null,
      );
      controller.dispose();
      controller = AppController(store);
      await controller.initialize();
      expect(controller.failedDownloads.single.id, tracks.first.id);
      server.brokenAudio = false;
      await controller.retryDownloads();
      await until(
        () =>
            controller.downloads.length == 1 &&
            controller.downloadingItem == null,
      );
      server.slowDownload = true;
      await controller.enqueueDownloads([tracks[1]]);
      await until(() => controller.downloadReceivedBytes > 0);
      await controller.cancelDownload(tracks[1].id);
      await until(() => controller.downloadingItem == null);
      expect(controller.downloads, hasLength(1));
      expect(controller.failedDownloads, isEmpty);
      expect(
        (await store.loadDownloadJobs(server.session))['pending'],
        isEmpty,
      );
      final partials = directory
          .listSync(recursive: true)
          .where((file) => file.path.endsWith('.part'));
      expect(partials, isEmpty);
    },
  );

  test(
    'pending job persists before transfer, pause/restart resumes, storage cap is enforced',
    () async {
      await store.save(server.session);
      await controller.connect(server.session);
      await controller.pauseDownloads();
      await controller.enqueueDownloads(controller.songs.take(2));
      expect(
        (await store.loadDownloadJobs(server.session))['pending'],
        hasLength(2),
      );
      controller.dispose();
      controller = AppController(store);
      await controller.initialize();
      expect(controller.downloadsPaused, isTrue);
      expect(controller.downloadQueue, hasLength(2));
      controller.preferences = controller.preferences.copyWith(
        downloadLimitBytes: 10,
      );
      await controller.resumeDownloads();
      await until(
        () =>
            controller.failedDownloads.length == 2 &&
            controller.downloadingItem == null,
      );
      expect(controller.downloads, isEmpty);
      expect(controller.downloadError, contains('storage limit'));
      controller.preferences = controller.preferences.copyWith(
        downloadLimitBytes: 0,
      );
      await controller.retryDownloads();
      await until(
        () =>
            controller.downloads.length == 2 &&
            controller.downloadingItem == null,
      );
    },
  );

  test(
    'Wi-Fi policy pauses without losing jobs and resumes on permitted network',
    () async {
      var wifi = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.thomaskleckner.shrimphony/network'),
            (_) async => wifi,
          );
      await controller.connect(server.session);
      controller.preferences = controller.preferences.copyWith(
        wifiOnlyDownloads: true,
      );
      await controller.enqueueDownloads(controller.songs.take(1));
      await until(
        () => controller.downloadsPaused && controller.downloadingItem == null,
      );
      expect(controller.downloadQueue, hasLength(1));
      wifi = true;
      await controller.resumeDownloads();
      await until(
        () =>
            controller.downloads.length == 1 &&
            controller.downloadingItem == null,
      );
    },
  );

  test(
    'account removal deletes only its downloads, cache, jobs, preferences and queue',
    () async {
      await store.save(server.session);
      await controller.connect(server.session);
      await controller.enqueueDownloads(controller.songs.take(1));
      await until(
        () =>
            controller.downloads.length == 1 &&
            controller.downloadingItem == null,
      );
      const other = JellyfinSession(
        serverUrl: 'http://localhost:8097',
        accessToken: 'other',
        userId: 'other',
        username: 'Other',
        deviceId: 'other',
      );
      await store.saveLibraryCache(other, {'marker': true});
      await store.savePreferences(
        server.session,
        const AppPreferences(downloadLimitBytes: 123),
      );
      await controller.removeServer(server.session);
      expect((await store.loadDownloads(server.session)).items, isEmpty);
      expect(await store.loadLibraryCache(server.session), isNull);
      expect(await store.loadDownloadJobs(server.session), isEmpty);
      expect(
        (await store.loadPreferences(server.session)).downloadLimitBytes,
        0,
      );
      expect(await store.loadLibraryCache(other), {'marker': true});
      expect(await store.load(), isNull);
    },
  );

  test('first songs publish before later pages finish', () async {
    await server.close();
    server = TestMusicServer(songCount: 1000);
    await server.start();
    server.pageGate = Completer<void>();
    final refresh = controller.connect(server.session);
    await until(() => controller.songs.length == 250);
    expect(controller.status, AppStatus.loading);
    server.pageGate!.complete();
    await refresh;
    expect(controller.songs, hasLength(1000));
  });

  test(
    'iOS now-playing artwork is remote or file, Android provider remains Android-only',
    () {
      final api = JellyfinClient(server.session);
      final item = JellyfinItem.fromJson(server.tracks.first);
      expect(
        vehiclePlayingMediaItem(
          api,
          item,
          'q',
          platform: TargetPlatform.iOS,
        ).artUri?.scheme,
        'http',
      );
      expect(
        vehiclePlayingMediaItem(
          api,
          item,
          'q',
          platform: TargetPlatform.android,
        ).artUri?.scheme,
        'content',
      );
      expect(
        vehiclePlayingMediaItem(
          api,
          item,
          'q',
          platform: TargetPlatform.iOS,
          artwork: Uri.file('/tmp/art.png'),
        ).artUri?.scheme,
        'file',
      );
      api.close();
    },
  );
  test(
    '50,000-track library publishes early and retains every song',
    () async {
      await server.close();
      server = TestMusicServer(songCount: 50000);
      await server.start();
      final watch = Stopwatch()..start();
      int? firstPageMs;
      controller.addListener(() {
        if (controller.songs.isNotEmpty) {
          firstPageMs ??= watch.elapsedMilliseconds;
        }
      });
      await controller.connect(server.session);
      expect(controller.songs, hasLength(50000));
      expect(controller.songs.map((song) => song.id).toSet(), hasLength(50000));
      expect(firstPageMs, lessThan(watch.elapsedMilliseconds));
      debugPrint(
        'SYNTHETIC 50k: first page ${firstPageMs}ms; complete refresh/cache ${watch.elapsedMilliseconds}ms',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
