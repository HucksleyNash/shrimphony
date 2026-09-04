import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shrimphony/jellyfin.dart';
import 'package:shrimphony/playback.dart';

void main() {
  late Directory supportDirectory;

  setUpAll(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'shrimphony-test-',
    );
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    final playback = File('${supportDirectory.path}/playback.json');
    if (await playback.exists()) await playback.delete();
  });

  tearDownAll(() async {
    await supportDirectory.delete(recursive: true);
  });

  test('materializes shuffle order without changing the library order', () {
    final alphabetical = List.generate(20, (index) => index);

    final shuffled = materializedShuffle(alphabetical, random: Random(1));

    expect(shuffled, isNot(orderedEquals(alphabetical)));
    expect(shuffled.toSet(), alphabetical.toSet());
    expect(alphabetical, orderedEquals(List.generate(20, (index) => index)));
  });

  group('JellyfinClient', () {
    test('normalizes local server addresses and preserves subpaths', () {
      expect(
        JellyfinClient.normalizeServerUrl(' musicbox.local:8096/jellyfin/ '),
        'http://musicbox.local:8096/jellyfin',
      );
      expect(
        () => JellyfinClient.normalizeServerUrl('ftp://musicbox.local'),
        throwsFormatException,
      );
      expect(
        () => JellyfinClient.normalizeServerUrl(
          'https://user:password@music.example',
        ),
        throwsFormatException,
      );
      expect(
        JellyfinClient.normalizeServerUrl('http://192.168.1.20:8096'),
        'http://192.168.1.20:8096',
      );
      expect(
        JellyfinClient.normalizeServerUrl('http://[fd00::20]:8096'),
        'http://[fd00::20]:8096',
      );
      expect(
        JellyfinClient.normalizeServerUrl(
          'http://musicbox.example-tailnet.ts.net:8096',
        ),
        'http://musicbox.example-tailnet.ts.net:8096',
      );
      expect(
        () => JellyfinClient.normalizeServerUrl('http://music.example.com'),
        throwsFormatException,
      );

      const session = JellyfinSession(
        serverUrl: 'https://music.example/jellyfin',
        accessToken: 'secret',
        userId: 'user-1',
        username: 'Taylor',
        deviceId: 'device-1',
      );
      final client = JellyfinClient(session);
      expect(
        client.imageUri('album-1').path,
        '/jellyfin/Items/album-1/Images/Primary',
      );
      expect(client.imageUri('album-1').query, isNot(contains('secret')));
      expect(client.streamUri('song-1').query, isNot(contains('secret')));
      client.close();

      final limited = JellyfinClient(
        session,
        preferences: const AppPreferences(
          streamingQuality: StreamingQuality.high,
        ),
      );
      expect(
        limited.streamUri('song-1').queryParameters['MaxStreamingBitrate'],
        '320000',
      );
      expect(
        limited.streamUri('song-1', sourceContainer: 'flac').path,
        '/jellyfin/Audio/song-1/master.m3u8',
      );
      expect(
        limited
            .streamUri('song-1', mediaSourceId: 'source-2')
            .queryParameters['MediaSourceId'],
        'source-2',
      );
      expect(
        client.streamUri('song-1', sourceContainer: 'flac').path,
        '/jellyfin/Audio/song-1/stream.flac',
      );
      limited.close();
    });
  });

  test('maps Jellyfin ticks and artist metadata', () {
    final item = JellyfinItem.fromJson({
      'Id': 'track-1',
      'Name': 'A Song',
      'Type': 'Audio',
      'Album': 'An Album',
      'AlbumId': 'album-1',
      'MediaSources': [
        {
          'Id': 'source-1',
          'Container': 'flac',
          'MediaStreams': [
            {'Type': 'Audio', 'BitDepth': 32},
          ],
        },
      ],
      'AlbumPrimaryImageTag': 'album-tag',
      'RunTimeTicks': 125000000,
      'ArtistItems': [
        {'Id': 'artist-1', 'Name': 'An Artist'},
      ],
      'ImageTags': {'Primary': 'tag'},
      'PlaylistItemId': 'entry-1',
      'DateCreated': '2026-08-20T12:00:00Z',
      'UserData': {
        'IsFavorite': true,
        'LastPlayedDate': '2026-08-21T12:00:00Z',
        'PlaybackPositionTicks': 65000000,
      },
    });

    expect(item.audioBitDepth, 32);
    expect(
      JellyfinItem.fromJson(
        item.copyWith(name: 'Renamed').toJson(),
      ).mediaSourceId,
      'source-1',
    );
    expect(item.duration, const Duration(milliseconds: 12500));
    expect(item.artists, ['An Artist']);
    expect(item.artistIds, ['artist-1']);
    expect(item.subtitle, 'An Artist • An Album');
    expect(item.isFavorite, isTrue);
    expect(item.playbackPosition, const Duration(milliseconds: 6500));
    expect(item.artworkId, 'track-1');
    final restored = JellyfinItem.fromJson(item.toJson());
    expect(restored.lastPlayedDate, isNotNull);
    expect(restored.container, 'flac');
    expect(restored.playlistItemId, 'entry-1');
    expect(restored.albumImageTag, 'album-tag');
    expect(
      JellyfinItem.fromJson({
        'Id': 'track-2',
        'Name': 'Album Art Song',
        'Type': 'Audio',
        'AlbumId': 'album-2',
        'AlbumPrimaryImageTag': 'album-tag',
      }).artworkId,
      'album-2',
    );
    expect(
      const JellyfinItem(
        id: 'track-3',
        name: 'No Art Song',
        type: 'Audio',
        albumId: 'album-without-art',
      ).artworkId,
      isNull,
    );
    expect(safeAudioExtension('x-flac'), 'flac');
    expect(safeAudioExtension('mpeg'), 'mp3');
    expect(canPlayOriginalOffline('flac'), isTrue);
    expect(canPlayOriginalOffline('ogg'), isFalse);
  });

  test('keeps only unique, pending audio downloads', () {
    const song = JellyfinItem(id: 'song-1', name: 'Song', type: 'Audio');

    expect(
      pendingAudioDownloads(
        [
          song,
          song,
          const JellyfinItem(id: 'song-2', name: 'Song 2', type: 'Audio'),
          const JellyfinItem(id: 'album-1', name: 'Album', type: 'MusicAlbum'),
          const JellyfinItem(id: '', name: 'Missing ID', type: 'Audio'),
        ],
        const {'song-2'},
      ).map((item) => item.id),
      ['song-1'],
    );
  });

  test('round-trips preferences and safely rejects bad shuffle state', () {
    const preferences = AppPreferences(
      musicLibraryIds: {'library-1', 'library-2'},
      streamingQuality: StreamingQuality.dataSaver,
    );
    final restored = AppPreferences.fromJson(preferences.toJson());

    expect(restored.musicLibraryIds, preferences.musicLibraryIds);
    expect(restored.streamingQuality, StreamingQuality.dataSaver);
    expect(validShuffleOrder([2, 0, 1], 3), [2, 0, 1]);
    expect(validShuffleOrder([0, 0, 1], 3), isNull);
    expect(validShuffleOrder([0, 1, 3], 3), isNull);
    expect(validShuffleOrder([0.1, 1.9], 2), isNull);
  });

  test('keeps the Android Auto root small, browsable, and artwork local', () {
    final root = androidAutoRootItems();
    final actions = vehicleCollectionActions('Playlist', 'playlist-1');
    final artwork = vehicleArtworkUri('album-1');
    const session = JellyfinSession(
      serverUrl: 'https://music.example',
      accessToken: 'secret',
      userId: 'user-1',
      username: 'Taylor',
      deviceId: 'device-1',
    );
    final client = JellyfinClient(session);
    final playing = vehiclePlayingMediaItem(
      client,
      const JellyfinItem(
        id: 'song-1',
        name: 'Song',
        type: 'Audio',
        albumId: 'album-1',
        albumImageTag: 'image-tag',
      ),
      'queue:0',
      platform: TargetPlatform.android,
    );
    final suggested = vehicleBrowserMediaItem(
      client,
      const JellyfinItem(id: 'song-2', name: 'Suggested', type: 'Audio'),
      groupTitle: 'Suggested for you',
    );

    expect(root, hasLength(4));
    expect(root.every((item) => item.playable == false), isTrue);
    expect(root.map((item) => item.id), [
      'browse:home',
      'browse:recent',
      'browse:shuffle',
      'browse:library',
    ]);
    expect(
      root.first.extras?[AndroidContentStyle.playableHintKey],
      AndroidContentStyle.gridItemHintValue,
    );
    expect(actions.map((item) => item.id), [
      'action:play:Playlist:playlist-1',
      'action:mix:playlist-1',
    ]);
    expect(artwork.scheme, 'content');
    expect(artwork.authority, 'com.thomaskleckner.shrimphony.artwork');
    expect(artwork.pathSegments, ['album-1']);
    expect(playing.artUri, artwork);
    expect(
      playing.extras?['android.media.metadata.ALBUM_ART_URI'],
      artwork.toString(),
    );
    expect(
      playing.extras?['remoteArtUri'],
      client.imageUri('album-1').toString(),
    );
    expect(
      suggested.extras?['android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT'],
      'Suggested for you',
    );
    client.close();
  });

  test('round-trips sessions without passwords', () {
    const session = JellyfinSession(
      serverUrl: 'https://music.example',
      accessToken: 'token',
      userId: 'user',
      username: 'Sam',
      deviceId: 'device',
    );

    expect(
      JellyfinSession.fromJson(session.toJson()).toJson(),
      session.toJson(),
    );
    expect(session.toJson(), isNot(contains('password')));
  });

  test('uses Jellyfin playlist and remote-device APIs', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Map<String, dynamic>>[];
    server.listen((request) async {
      final text = await utf8.decoder.bind(request).join();
      requests.add({
        'method': request.method,
        'path': request.uri.path,
        'query': request.uri.queryParameters,
        'body': text.isEmpty ? null : jsonDecode(text),
      });
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'POST' && request.uri.path == '/Playlists') {
        request.response.write(jsonEncode({'Id': 'playlist-1'}));
      } else if (request.uri.path == '/Items/playlist-1') {
        request.response.write(
          jsonEncode({
            'Id': 'playlist-1',
            'Name': 'Road trip',
            'Type': 'Playlist',
          }),
        );
      } else if (request.method == 'GET' &&
          request.uri.path == '/Playlists/playlist-1/Items') {
        request.response.write(
          jsonEncode({
            'Items': [
              {
                'Id': 'song-1',
                'Name': 'Song',
                'Type': 'Audio',
                'PlaylistItemId': 'entry-1',
              },
              {
                'Id': 'song-1',
                'Name': 'Song',
                'Type': 'Audio',
                'PlaylistItemId': 'entry-2',
              },
            ],
            'TotalRecordCount': 2,
          }),
        );
      } else if (request.uri.path == '/Sessions') {
        request.response.write(
          jsonEncode([
            {
              'Id': 'session-2',
              'DeviceId': 'tv-device',
              'DeviceName': 'Living Room TV',
              'Client': 'Jellyfin Android TV',
              'SupportsRemoteControl': true,
            },
          ]),
        );
      } else if (request.uri.path == '/Items/song-1/InstantMix') {
        request.response.write(
          jsonEncode({
            'Items': [
              {'Id': 'mix-1', 'Name': 'Mix Song', 'Type': 'Audio'},
            ],
            'TotalRecordCount': 1,
          }),
        );
      }
      await request.response.close();
    });
    final client = JellyfinClient(
      JellyfinSession(
        serverUrl: 'http://127.0.0.1:${server.port}',
        accessToken: 'token',
        userId: 'user-1',
        username: 'Sam',
        deviceId: 'phone-device',
      ),
    );
    const song = JellyfinItem(id: 'song-1', name: 'Song', type: 'Audio');

    try {
      final playlist = await client.createPlaylist('Road trip', [song.id]);
      final playlistItems = await client.playlistItems(playlist.id);
      await client.addToPlaylist(playlist.id, [song.id]);
      await client.removeFromPlaylist(playlist.id, ['entry-1']);
      await client.movePlaylistItem(playlist.id, 'entry-1', 2);
      await client.renamePlaylist(playlist.id, 'Driving');
      final devices = await client.devices();
      final mix = await client.instantMix(song.id);
      await client.playOnDevice(devices.single, [song]);

      expect(playlist.id, 'playlist-1');
      expect(playlistItems.map((item) => item.playlistItemId), [
        'entry-1',
        'entry-2',
      ]);
      expect(devices.single.name, 'Living Room TV');
      expect(mix.single.id, 'mix-1');
      final create = requests.firstWhere(
        (request) => request['path'] == '/Playlists',
      );
      expect((create['body'] as Map)['Name'], 'Road trip');
      expect((create['body'] as Map)['Ids'], ['song-1']);
      final add = requests.firstWhere(
        (request) =>
            request['method'] == 'POST' &&
            request['path'] == '/Playlists/playlist-1/Items',
      );
      expect((add['query'] as Map)['ids'], 'song-1');
      final remove = requests.firstWhere(
        (request) => request['method'] == 'DELETE',
      );
      expect((remove['query'] as Map)['entryIds'], 'entry-1');
      expect(
        requests.any(
          (request) =>
              request['path'] == '/Playlists/playlist-1/Items/entry-1/Move/2',
        ),
        isTrue,
      );
      final handoff = requests.firstWhere(
        (request) => request['path'] == '/Sessions/session-2/Playing',
      );
      expect((handoff['query'] as Map)['playCommand'], 'PlayNow');
      expect((handoff['query'] as Map)['itemIds'], 'song-1');
    } finally {
      client.close();
      await server.close(force: true);
    }
  });

  test('starts shuffle all from one batch before paging the library', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Map<String, String>>[];
    server.listen((request) async {
      requests.add(request.uri.queryParameters);
      final random = request.uri.queryParameters['SortBy'] == 'Random';
      final start = int.parse(request.uri.queryParameters['StartIndex'] ?? '0');
      final limit = int.parse(request.uri.queryParameters['Limit'] ?? '100');
      final count = random ? limit : min(limit, 5 - start);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'Items': [
            for (var index = 0; index < count; index++)
              {
                'Id': '${random ? 'random' : 'song'}-${start + index}',
                'Name': 'Song ${start + index}',
                'Type': 'Audio',
              },
          ],
          'TotalRecordCount': random ? count : 5,
        }),
      );
      await request.response.close();
    });
    final client = JellyfinClient(
      JellyfinSession(
        serverUrl: 'http://127.0.0.1:${server.port}',
        accessToken: 'token',
        userId: 'user-1',
        username: 'Sam',
        deviceId: 'phone-device',
      ),
    );

    try {
      final initial = await client.randomSongs(limit: 3);
      final firstBatch = await client.songBatches(batchSize: 2).first;

      expect(initial.map((item) => item.id), [
        'random-0',
        'random-1',
        'random-2',
      ]);
      expect(firstBatch.map((item) => item.id), ['song-0', 'song-1']);
      expect(
        requests.where((query) => query['SortBy'] == 'Random'),
        hasLength(1),
      );
      expect(
        requests.where((query) => query['SortBy'] != 'Random'),
        hasLength(1),
      );
      requests.clear();
      final batches = await client.songBatches(batchSize: 2).toList();
      expect(batches.map((batch) => batch.length), [2, 2, 1]);
      expect(requests, hasLength(3));
    } finally {
      client.close();
      await server.close(force: true);
    }
  });

  test('saves, selects, and updates multiple servers', () async {
    final store = JellyfinSessionStore(supportDirectory: supportDirectory);
    const home = JellyfinSession(
      serverUrl: 'http://192.168.1.20:8096',
      accessToken: 'home-token',
      userId: 'home-user',
      username: 'Sam',
      deviceId: 'home-device',
    );
    const remote = JellyfinSession(
      serverUrl: 'https://music.example',
      accessToken: 'remote-token',
      userId: 'remote-user',
      username: 'Sam',
      deviceId: 'remote-device',
    );

    await store.save(home);
    await store.save(remote);

    expect((await store.load())?.deviceId, remote.deviceId);
    expect((await store.loadAll()).map((server) => server.deviceId), [
      remote.deviceId,
      home.deviceId,
    ]);

    const updatedHome = JellyfinSession(
      serverUrl: 'http://musicbox.example-tailnet.ts.net:8096',
      accessToken: 'new-home-token',
      userId: 'home-user',
      username: 'Sam',
      deviceId: 'new-home-device',
    );
    await store.save(updatedHome, replacingDeviceId: home.deviceId);

    expect((await store.loadAll()).map((server) => server.deviceId), [
      updatedHome.deviceId,
      remote.deviceId,
    ]);
  });

  test('clears playback when the active server changes', () async {
    final store = JellyfinSessionStore(supportDirectory: supportDirectory);
    const home = JellyfinSession(
      serverUrl: 'http://192.168.1.20:8096',
      accessToken: 'home-token',
      userId: 'home-user',
      username: 'Sam',
      deviceId: 'home-device',
    );
    const remote = JellyfinSession(
      serverUrl: 'https://music.example',
      accessToken: 'remote-token',
      userId: 'remote-user',
      username: 'Sam',
      deviceId: 'remote-device',
    );

    await store.save(home);
    await store.savePlayback({'queue': []});
    expect(await store.loadPlayback(), isNotNull);

    await store.save(remote);

    expect(await store.loadPlayback(), isNull);

    await store.savePlayback({'queue': []});
    await store.deactivate(clearPlayback: false);

    expect(await store.load(), isNull);
    expect(await store.loadPlayback(), isNotNull);
    expect((await store.loadAll()).first.deviceId, remote.deviceId);
  });

  test('serializes overlapping playback saves', () async {
    final store = JellyfinSessionStore(supportDirectory: supportDirectory);

    await Future.wait([
      for (var index = 0; index < 20; index++)
        store.savePlayback({'index': index, 'queue': []}),
    ]);

    expect((await store.loadPlayback())?['index'], 19);
  });

  test('clears the previous library before connecting a new server', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    });
    final controller =
        AppController(JellyfinSessionStore(supportDirectory: supportDirectory))
          ..albums = const [
            JellyfinItem(
              id: 'old-album',
              name: 'Old album',
              type: 'MusicAlbum',
            ),
          ];
    final session = JellyfinSession(
      serverUrl: 'http://127.0.0.1:${server.port}',
      accessToken: 'token',
      userId: 'user',
      username: 'Sam',
      deviceId: 'new-device',
    );

    try {
      await controller.connect(session);

      expect(controller.session, session);
      expect(controller.albums, isEmpty);
      expect(controller.status, AppStatus.error);
    } finally {
      controller.dispose();
      await server.close(force: true);
    }
  });

  test('signs out on auth expiry without losing the saved queue', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
    });
    final store = JellyfinSessionStore(supportDirectory: supportDirectory);
    final session = JellyfinSession(
      serverUrl: 'http://127.0.0.1:${server.port}',
      accessToken: 'expired-token',
      userId: 'user',
      username: 'Sam',
      deviceId: 'device',
    );
    await store.save(session);
    await store.savePlayback({'queue': []});
    final controller = AppController(store);
    var notifications = 0;
    controller.addListener(() => notifications++);

    try {
      await controller.connect(session);

      expect(controller.status, AppStatus.signedOut);
      expect(controller.session, isNull);
      expect(controller.editingServer?.deviceId, session.deviceId);
      expect(notifications, greaterThanOrEqualTo(3));
      expect(await store.load(), isNull);
      expect((await store.loadAll()).single.deviceId, session.deviceId);
      expect(await store.loadPlayback(), isNotNull);
    } finally {
      controller.dispose();
      await server.close(force: true);
    }
  });

  test('cancels server management back to the active session', () async {
    final store = JellyfinSessionStore(supportDirectory: supportDirectory);
    const session = JellyfinSession(
      serverUrl: 'http://192.168.1.20:8096',
      accessToken: 'home-token',
      userId: 'home-user',
      username: 'Sam',
      deviceId: 'home-device',
    );
    await store.save(session);
    final controller = AppController(store)
      ..session = session
      ..status = AppStatus.error
      ..errorMessage = 'Server unavailable.';

    await controller.manageServers();
    controller
      ..status = AppStatus.signedOut
      ..errorMessage = 'New server failed.'
      ..cancelServerManagement();

    expect(controller.managingServers, isFalse);
    expect(controller.session, session);
    expect(controller.status, AppStatus.error);
    expect(controller.errorMessage, 'Server unavailable.');
    expect((await store.load())?.deviceId, session.deviceId);
  });
}
