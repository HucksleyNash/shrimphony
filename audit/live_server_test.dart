// Explicit opt-in: SHRIMPHONY_LIVE_SESSION=/path/to/private-session.json flutter test audit/live_server_test.dart
// Creates one temporary playlist and restores the selected track's original favorite state.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:shrimphony/jellyfin.dart';

void main() {
  final path = Platform.environment['SHRIMPHONY_LIVE_SESSION'];
  test(
    'real-server library, collection, favorites, playlist and reporting contracts',
    () async {
      final session = JellyfinSession.fromJson(
        (jsonDecode(await File(path!).readAsString()) as Map)
            .cast<String, dynamic>(),
      );
      final client = JellyfinClient(session);
      final directory = await Directory.systemTemp.createTemp(
        'shrimphony-live-api-',
      );
      final store = JellyfinSessionStore(supportDirectory: directory);
      String? playlistId;
      JellyfinItem? original;
      var reportingStarted = false;
      try {
        final watch = Stopwatch()..start();
        final songs = await client.songs();
        debugPrint(
          'LIVE complete songs: ${songs.length}; ${watch.elapsedMilliseconds}ms',
        );
        expect(songs.length, greaterThan(100));
        final albums = await client.albums();
        final artists = await client.artists();
        final genres = await client.genres();
        final libraries = await client.musicLibraries();
        expect(albums, isNotEmpty);
        expect(artists, isNotEmpty);
        expect(genres, isNotEmpty);
        expect(libraries, isNotEmpty);
        final albumTracks = (await client.children(
          albums.first.id,
        )).where((item) => item.isAudio).toList();
        expect(albumTracks, isNotEmpty);
        for (var i = 1; i < albumTracks.length; i++) {
          final before = albumTracks[i - 1];
          final after = albumTracks[i];
          expect(
            (before.parentIndexNumber ?? 0) * 100000 +
                (before.indexNumber ?? 0),
            lessThanOrEqualTo(
              (after.parentIndexNumber ?? 0) * 100000 +
                  (after.indexNumber ?? 0),
            ),
          );
        }
        final artistTracks = await client.songsForArtist(artists.first.id);
        expect(artistTracks, isNotEmpty);
        original = await client.item(songs.first.id);
        final searched = await client.search(original.name);
        expect(searched.map((item) => item.id), contains(original.id));
        await client.setFavorite(original.id, !original.isFavorite);
        expect(
          (await client.item(original.id)).isFavorite,
          !original.isFavorite,
        );
        await client.setFavorite(original.id, original.isFavorite);
        final name = 'Shrimphony QA ${DateTime.now().microsecondsSinceEpoch}';
        final playlist = await client.createPlaylist(name, [
          songs[0].id,
          songs[1].id,
        ]);
        playlistId = playlist.id;
        await client.addToPlaylist(playlist.id, [songs[0].id]);
        var entries = await client.playlistItems(playlist.id);
        expect(entries.map((item) => item.id).take(2), [
          songs[0].id,
          songs[1].id,
        ]);
        expect(
          entries.map((item) => item.playlistItemId).toSet(),
          hasLength(entries.length),
        );
        debugPrint(
          'LIVE duplicate playlist insertion: ${entries.length == 3 ? 'retained' : 'deduplicated by server'}',
        );
        final reordered = [...entries];
        reordered.insert(0, reordered.removeLast());
        await client.renamePlaylist(playlist.id, '$name renamed');
        expect((await client.item(playlist.id)).name, '$name renamed');
        await client.movePlaylistItem(
          playlist.id,
          entries.last.playlistItemId!,
          0,
        );
        entries = await client.playlistItems(playlist.id);
        expect(
          entries.map((item) => item.id),
          reordered.map((item) => item.id),
        );
        await client.removeFromPlaylist(playlist.id, [
          entries.first.playlistItemId!,
        ]);
        await client.addToPlaylist(playlist.id, [songs[2].id]);
        expect(
          (await client.playlistItems(playlist.id)).map((item) => item.id),
          [...reordered.skip(1).map((item) => item.id), songs[2].id],
        );
        expect(await client.instantMix(original.id), isNotEmpty);
        await client.devices();
        reportingStarted = true;
        await client.reportPlayback('start', original.id, Duration.zero);
        await client.reportPlayback(
          'progress',
          original.id,
          const Duration(seconds: 3),
          paused: true,
        );
        final statusClient = HttpClient();
        try {
          final request = await statusClient.getUrl(
            client.uri('/Sessions', {'deviceId': session.deviceId}),
          );
          client.authorizationHeaders.forEach(request.headers.set);
          final response = await request.close();
          expect(response.statusCode, 200);
          final sessions =
              jsonDecode(await utf8.decoder.bind(response).join()) as List;
          final current = sessions.cast<Map>().firstWhere(
            (value) => value['DeviceId'] == session.deviceId,
          );
          expect(current['NowPlayingItem']['Id'], original.id);
          expect(current['PlayState']['IsPaused'], isTrue);
          expect(current['PlayState']['PositionTicks'], 30000000);
        } finally {
          statusClient.close(force: true);
        }
        await client.reportPlayback(
          'stop',
          original.id,
          const Duration(seconds: 3),
        );
        reportingStarted = false;
        debugPrint(
          'LIVE server playback reporting reflects selected song, pause and exact position',
        );

        await store.downloadTrack(session, client, original);
        expect(
          (await store.loadDownloads(session)).items.single.id,
          original.id,
        );
        expect(
          (await store.downloadedUris(session, [
            original.id,
          ])).values.single.scheme,
          'file',
        );
        debugPrint(
          'LIVE PASS albums, artists, genres, libraries, search, favorites, playlist create/rename/add/reorder/remove with duplicates, Instant Mix, devices, download',
        );
      } finally {
        if (reportingStarted && original != null) {
          await client.reportPlayback(
            'stop',
            original.id,
            const Duration(seconds: 3),
          );
        }
        if (original != null) {
          await client.setFavorite(original.id, original.isFavorite);
        }
        if (playlistId != null) {
          final http = HttpClient();
          try {
            final request = await http.deleteUrl(
              client.uri('/Items/$playlistId'),
            );
            client.authorizationHeaders.forEach(request.headers.set);
            final response = await request.close();
            await response.drain<void>();
            expect(response.statusCode, anyOf(200, 204));
            debugPrint(
              'LIVE temporary playlist deleted; original favorite state restored',
            );
          } finally {
            http.close(force: true);
          }
        }
        client.close();
        await directory.delete(recursive: true);
      }
    },
    skip: path == null ? 'No opt-in private test session provided.' : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
