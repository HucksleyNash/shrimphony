import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'jellyfin.dart';
import 'playback.dart';

const _brandCoral = Color(0xffff594c);
const _brandNavy = Color(0xff071a33);
const _brandNavySoft = Color(0xff0e2949);
const _brandCream = Color(0xfffff7ea);
const _brandCreamDeep = Color(0xfff4e8d6);
const _brandPaper = Color(0xfffffcf6);

class ShrimphonyApp extends StatelessWidget {
  const ShrimphonyApp({
    super.key,
    required this.controller,
    required this.audioHandler,
  });

  final AppController controller;
  final JellyfinAudioHandler audioHandler;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: appName,
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: _AppRoot(controller: controller, audioHandler: audioHandler),
  );

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _brandCoral,
          brightness: brightness,
        ).copyWith(
          primary: _brandCoral,
          onPrimary: _brandNavy,
          secondary: dark ? _brandCream : _brandNavy,
          onSecondary: dark ? _brandNavy : _brandCream,
          surface: dark ? _brandNavy : _brandCream,
          onSurface: dark ? _brandCream : _brandNavy,
          surfaceContainerLow: dark ? _brandNavySoft : _brandPaper,
          surfaceContainerHigh: dark
              ? const Color(0xff17395f)
              : _brandCreamDeep,
          surfaceContainerHighest: dark
              ? const Color(0xff1d456e)
              : _brandCreamDeep,
        );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: scheme.surface,
        indicatorColor: _brandCoral.withValues(alpha: 0.18),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _AppRoot extends StatelessWidget {
  const _AppRoot({required this.controller, required this.audioHandler});

  final AppController controller;
  final JellyfinAudioHandler audioHandler;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (controller.status == AppStatus.booting) {
        return const _LoadingScreen(label: 'Opening your library…');
      }
      if (controller.managingServers) {
        return _LoginScreen(controller: controller);
      }
      if (controller.session == null) {
        return _LoginScreen(controller: controller);
      }
      final hasLibrary =
          controller.albums.isNotEmpty || controller.songs.isNotEmpty;
      if (controller.status == AppStatus.loading && !hasLibrary) {
        return const _LoadingScreen(label: 'Loading your music…');
      }
      if (controller.status == AppStatus.error && !hasLibrary) {
        return _ConnectionError(controller: controller);
      }
      return _AppShell(controller: controller, audioHandler: audioHandler);
    },
  );
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Semantics(
        liveRegion: true,
        label: label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(label),
          ],
        ),
      ),
    ),
  );
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.controller});

  final AppController controller;

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final editing = widget.controller.editingServer;
    if (editing != null) {
      _server.text = editing.serverUrl;
      _username.text = editing.username;
    }
  }

  void _editServer(JellyfinSession server) {
    widget.controller.editServer(server);
    setState(() {
      _server.text = server.serverUrl;
      _username.text = server.username;
      _password.clear();
    });
  }

  void _cancelServerEdit() {
    widget.controller.cancelServerEdit();
    setState(() {
      _server.clear();
      _username.clear();
      _password.clear();
    });
  }

  void _cancelServerManagement() => widget.controller.cancelServerManagement();

  Future<void> _removeServer(JellyfinSession server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove server?'),
        content: Text(
          'Remove ${Uri.parse(server.serverUrl).host} for ${server.username}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final wasEditing =
        widget.controller.editingServer?.deviceId == server.deviceId;
    await widget.controller.removeServer(server);
    if (wasEditing && mounted) _cancelServerEdit();
  }

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await widget.controller.login(
      serverUrl: _server.text,
      username: _username.text,
      password: _password.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.controller.status == AppStatus.loading;
    final managingServers = widget.controller.managingServers;
    final canCancelServerManagement =
        widget.controller.canCancelServerManagement;
    return Scaffold(
      appBar: managingServers
          ? AppBar(
              automaticallyImplyLeading: false,
              leading: canCancelServerManagement
                  ? IconButton(
                      tooltip: 'Back',
                      onPressed: busy ? null : _cancelServerManagement,
                      icon: const BackButtonIcon(),
                    )
                  : null,
              title: const Text('Servers'),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        image: true,
                        label: 'Shrimphony logo',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Image.asset(
                            'assets/icon/shrimphony_icon.png',
                            width: 92,
                            height: 92,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        appName.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 3.2,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Your music. Your server.\n'),
                            TextSpan(
                              text: 'Your tempo.',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.08,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Connect to your Jellyfin music library.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 32),
                      if (widget.controller.servers.isNotEmpty) ...[
                        Text(
                          'Saved servers',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (final server in widget.controller.servers)
                                ListTile(
                                  enabled: !busy,
                                  leading: const Icon(Icons.dns_outlined),
                                  title: Text(Uri.parse(server.serverUrl).host),
                                  subtitle: Text(
                                    '${server.username} • ${server.serverUrl}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: busy
                                      ? null
                                      : () => widget.controller.selectServer(
                                          server,
                                        ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Edit server',
                                        onPressed: busy
                                            ? null
                                            : () => _editServer(server),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Remove server',
                                        onPressed: busy
                                            ? null
                                            : () => _removeServer(server),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      Text(
                        widget.controller.editingServer == null
                            ? 'Add server'
                            : 'Update server',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _server,
                        enabled: !busy,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.url],
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Jellyfin server',
                          hintText: 'http://192.168.1.20:8096',
                          prefixIcon: Icon(Icons.dns_outlined),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter your Jellyfin server address.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _username,
                        enabled: !busy,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter your Jellyfin username.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        enabled: !busy,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _login(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (widget.controller.errorMessage
                          case final message?) ...[
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            message,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: busy ? null : _login,
                        icon: busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login_rounded),
                        label: Text(
                          busy
                              ? 'Connecting…'
                              : widget.controller.editingServer == null
                              ? 'Connect'
                              : 'Update and connect',
                        ),
                      ),
                      if (widget.controller.editingServer != null ||
                          canCancelServerManagement)
                        TextButton(
                          onPressed: busy
                              ? null
                              : canCancelServerManagement
                              ? _cancelServerManagement
                              : _cancelServerEdit,
                          child: Text(
                            canCancelServerManagement
                                ? 'Cancel'
                                : 'Cancel update',
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        'HTTP works for private LAN addresses. Use HTTPS outside your trusted network. Your password is never saved.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionError extends StatelessWidget {
  const _ConnectionError({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(appName)),
    body: _EmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Server unavailable',
      message: controller.errorMessage ?? 'Jellyfin could not be reached.',
      action: FilledButton.icon(
        onPressed: controller.refresh,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
      ),
      secondaryAction: TextButton(
        onPressed: controller.manageServers,
        child: const Text('Change server'),
      ),
    ),
  );
}

class _AppShell extends StatefulWidget {
  const _AppShell({required this.controller, required this.audioHandler});

  final AppController controller;
  final JellyfinAudioHandler audioHandler;

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _index = 0;

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'This removes this saved server and clears the playback queue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.logout();
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Home', 'Search', 'Your Library'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          IconButton(
            tooltip: 'Refresh library',
            onPressed: widget.controller.status == AppStatus.loading
                ? null
                : widget.controller.refresh,
            icon: widget.controller.status == AppStatus.loading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (value) async {
              if (value == 'shuffle') {
                await _runPlayback(
                  context,
                  () => widget.audioHandler.playItems(
                    widget.controller.songs,
                    shuffle: true,
                  ),
                );
              } else if (value == 'settings') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _SettingsScreen(
                      controller: widget.controller,
                      audioHandler: widget.audioHandler,
                    ),
                  ),
                );
              } else if (value == 'servers') {
                await widget.controller.manageServers();
              } else if (value == 'logout') {
                await _logout();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Text(widget.controller.session?.username ?? 'Jellyfin'),
              ),
              if (_index == 0)
                PopupMenuItem(
                  value: 'shuffle',
                  enabled: widget.controller.songs.isNotEmpty,
                  child: const Text('Shuffle your library'),
                ),
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
              const PopupMenuItem(
                value: 'servers',
                child: Text('Change or add server'),
              ),
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.controller.status == AppStatus.error)
            MaterialBanner(
              content: Text(
                widget.controller.errorMessage ?? 'Server unavailable.',
              ),
              leading: const Icon(Icons.cloud_off_outlined),
              actions: [
                TextButton(
                  onPressed: widget.controller.refresh,
                  child: const Text('Retry'),
                ),
              ],
            ),
          if (widget.controller.downloadingItem != null ||
              widget.controller.downloadQueue.isNotEmpty ||
              widget.controller.downloadError != null)
            _DownloadStatusBar(controller: widget.controller),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                _HomePage(
                  controller: widget.controller,
                  audioHandler: widget.audioHandler,
                ),
                _SearchPage(
                  controller: widget.controller,
                  audioHandler: widget.audioHandler,
                ),
                _LibraryPage(
                  controller: widget.controller,
                  audioHandler: widget.audioHandler,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniPlayer(
            controller: widget.controller,
            audioHandler: widget.audioHandler,
          ),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: 'Library',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DownloadStatusBar extends StatelessWidget {
  const _DownloadStatusBar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final current = controller.downloadingItem;
    final failed = current == null ? controller.downloadError : null;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: failed == null
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.errorContainer,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              leading: current == null
                  ? const Icon(Icons.error_outline)
                  : const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
              title: Text(
                current == null
                    ? 'Download failed'
                    : 'Downloading ${current.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                failed ??
                    (controller.downloadQueue.isEmpty
                        ? 'Saving for offline play'
                        : '${controller.downloadQueue.length} waiting'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showDownloadQueue(context, controller),
            ),
            if (current != null) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen({required this.controller, required this.audioHandler});

  final AppController controller;
  final JellyfinAudioHandler audioHandler;

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  late bool _allLibraries;
  late Set<String> _selectedLibraries;
  late StreamingQuality _quality;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final preferences = widget.controller.preferences;
    _selectedLibraries = {...preferences.musicLibraryIds};
    _allLibraries = _selectedLibraries.isEmpty;
    _quality = preferences.streamingQuality;
  }

  Future<void> _save() async {
    if (!_allLibraries && _selectedLibraries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one music library.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.updatePreferences(
        AppPreferences(
          musicLibraryIds: _allLibraries ? const {} : _selectedLibraries,
          streamingQuality: _quality,
        ),
      );
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save settings: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Settings'),
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text('Playback', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        DropdownButtonFormField<StreamingQuality>(
          initialValue: _quality,
          decoration: const InputDecoration(
            labelText: 'Streaming quality',
            prefixIcon: Icon(Icons.high_quality_outlined),
          ),
          items: [
            for (final quality in StreamingQuality.values)
              DropdownMenuItem(value: quality, child: Text(quality.label)),
          ],
          onChanged: _saving
              ? null
              : (value) => setState(() => _quality = value ?? _quality),
        ),
        const SizedBox(height: 28),
        Text('Music libraries', style: Theme.of(context).textTheme.titleLarge),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Use all music libraries'),
          value: _allLibraries,
          onChanged: _saving
              ? null
              : (value) => setState(() {
                  _allLibraries = value;
                  if (!value && _selectedLibraries.isEmpty) {
                    _selectedLibraries = widget.controller.musicLibraries
                        .map((library) => library.id)
                        .toSet();
                  }
                }),
        ),
        for (final library in widget.controller.musicLibraries)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            enabled: !_allLibraries && !_saving,
            title: Text(library.name),
            value: _allLibraries || _selectedLibraries.contains(library.id),
            onChanged: (selected) => setState(() {
              if (selected == true) {
                _selectedLibraries.add(library.id);
              } else {
                _selectedLibraries.remove(library.id);
              }
            }),
          ),
        const SizedBox(height: 28),
        Text('Offline', style: Theme.of(context).textTheme.titleLarge),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.download_done_rounded),
          title: Text('${widget.controller.downloads.length} downloaded songs'),
          subtitle: Text(_formatBytes(widget.controller.downloadedBytes)),
        ),
        const SizedBox(height: 28),
        Text('Connection', style: Theme.of(context).textTheme.titleLarge),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.dns_outlined),
          title: Text(widget.controller.session?.username ?? 'Jellyfin'),
          subtitle: Text(widget.controller.session?.serverUrl ?? ''),
        ),
        StreamBuilder<List<MediaItem>>(
          stream: widget.audioHandler.queue,
          initialData: widget.audioHandler.queue.value,
          builder: (_, snapshot) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.queue_music_outlined),
            title: const Text('Restored queue'),
            subtitle: Text('${snapshot.data?.length ?? 0} songs'),
          ),
        ),
      ],
    ),
  );
}

class _HomePage extends StatelessWidget {
  const _HomePage({required this.controller, required this.audioHandler});

  final AppController controller;
  final JellyfinAudioHandler audioHandler;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: controller.refresh,
    child: ListView(
      key: const PageStorageKey('home'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          'Welcome back, ${controller.session?.username ?? ''}',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        _HorizontalSection(
          title: 'Recently played',
          items: controller.recentlyPlayed,
          controller: controller,
          audioHandler: audioHandler,
        ),
        _HorizontalSection(
          title: 'Recently added',
          items: controller.recentlyAdded,
          controller: controller,
          audioHandler: audioHandler,
        ),
        _HorizontalSection(
          title: 'Rediscover',
          items: controller.randomAlbums,
          controller: controller,
          audioHandler: audioHandler,
        ),
        _HorizontalSection(
          title: 'Albums',
          items: controller.albums,
          controller: controller,
          audioHandler: audioHandler,
        ),
        if (controller.favorites.isNotEmpty)
          _HorizontalSection(
            title: 'Favorites',
            items: controller.favorites,
            controller: controller,
            audioHandler: audioHandler,
          ),
        if (controller.recentlyAdded.isEmpty && controller.albums.isEmpty)
          const _EmptyState(
            icon: Icons.music_off_outlined,
            title: 'No music found',
            message: 'Add a music library in Jellyfin, then refresh here.',
          ),
      ],
    ),
  );
}

class _HorizontalSection extends StatelessWidget {
  const _HorizontalSection({
    required this.title,
    required this.items,
    required this.controller,
    required this.audioHandler,
  });

  final String title;
  final List<JellyfinItem> items;
  final AppController controller;
  final JellyfinAudioHandler audioHandler;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final shown = items.take(18).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 212,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: shown.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = shown[index];
                return _MediaCard(
                  item: item,
                  controller: controller,
                  onTap: () => _openOrPlay(
                    context,
                    controller,
                    audioHandler,
                    item,
                    contextItems: shown,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.item,
    required this.controller,
    required this.onTap,
  });

  final JellyfinItem item;
  final AppController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 148,
    child: Semantics(
      button: true,
      label: '${item.name}, ${item.subtitle}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Artwork(item: item, controller: controller, size: 148),
            const SizedBox(height: 8),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              item.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _SearchPage extends StatefulWidget {
  const _SearchPage({required this.controller, required this.audioHandler});

  final AppController controller;
  final JellyfinAudioHandler audioHandler;

  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  final _query = TextEditingController();
  Timer? _debounce;
  int _request = 0;
  bool _loading = false;
  String? _error;
  List<JellyfinItem> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    final request = ++_request;
    final term = value.trim();
    if (term.isEmpty) {
      setState(() {
        _loading = false;
        _error = null;
        _results = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final results = await widget.controller.search(term);
        if (!mounted || request != _request) return;
        setState(() {
          _results = results;
          _loading = false;
        });
      } on Object catch (error) {
        if (!mounted || request != _request) return;
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final audioContext = _results.where((item) => item.isAudio).toList();
    final groups = <String, List<JellyfinItem>>{
      'Songs': _results.where((item) => item.isAudio).toList(),
      'Albums': _results.where((item) => item.isAlbum).toList(),
      'Artists': _results.where((item) => item.isArtist).toList(),
      'Playlists': _results.where((item) => item.isPlaylist).toList(),
      'Genres': _results.where((item) => item.isGenre).toList(),
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SearchBar(
            controller: _query,
            hintText: 'Songs, artists, albums, playlists, genres',
            leading: const Icon(Icons.search),
            trailing: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_query.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _query.clear();
                    _search('');
                  },
                  icon: const Icon(Icons.clear),
                ),
            ],
            onChanged: (value) {
              setState(() {});
              _search(value);
            },
          ),
        ),
        Expanded(
          child: _query.text.trim().isEmpty
              ? const _EmptyState(
                  icon: Icons.search_rounded,
                  title: 'Search your library',
                  message:
                      'Find songs, artists, albums, playlists, and genres.',
                )
              : _error != null
              ? _EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Search failed',
                  message: _error!,
                )
              : !_loading && _results.isEmpty
              ? const _EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matches',
                  message: 'Try another title, artist, album, or playlist.',
                )
              : Semantics(
                  liveRegion: true,
                  label: '${_results.length} search results',
                  child: ListView(
                    key: const PageStorageKey('search-results'),
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      for (final group in groups.entries)
                        if (group.value.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                            child: Text(
                              group.key,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          for (final item in group.value)
                            _ItemTile(
                              item: item,
                              controller: widget.controller,
                              onTap: () => _openOrPlay(
                                context,
                                widget.controller,
                                widget.audioHandler,
                                item,
                                contextItems: audioContext,
                              ),
                              onMore: () => _showItemActions(
                                context,
                                widget.controller,
                                widget.audioHandler,
                                item,
                                contextItems: audioContext,
                              ),
                            ),
                        ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _LibraryPage extends StatefulWidget {
  const _LibraryPage({required this.controller, required this.audioHandler});

  final AppController controller;
  final JellyfinAudioHandler audioHandler;

  @override
  State<_LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<_LibraryPage> {
  String _filter = 'Albums';
  String _sort = 'A–Z';

  List<JellyfinItem> get _items {
    final items = [
      ...switch (_filter) {
        'Artists' => widget.controller.artists,
        'Songs' => widget.controller.songs,
        'Playlists' => widget.controller.playlists,
        'Favorites' => widget.controller.favorites,
        'Genres' => widget.controller.genres,
        'Downloads' => widget.controller.downloads,
        _ => widget.controller.albums,
      },
    ];
    items.sort(switch (_sort) {
      'Z–A' => (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
      'Newest' => (a, b) => (b.dateCreated ?? DateTime(0)).compareTo(
        a.dateCreated ?? DateTime(0),
      ),
      _ => (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    });
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final audioContext = items.where((item) => item.isAudio).toList();
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final filter in const [
                'Albums',
                'Artists',
                'Genres',
                'Songs',
                'Downloads',
                'Playlists',
                'Favorites',
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(filter),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
          child: Row(
            children: [
              Text('${items.length} ${_filter.toLowerCase()}'),
              const Spacer(),
              if (_filter == 'Songs' && items.isNotEmpty)
                IconButton.filledTonal(
                  tooltip: 'Shuffle songs',
                  icon: const Icon(Icons.shuffle),
                  onPressed: () => _runPlayback(
                    context,
                    () => widget.audioHandler.playItems(items, shuffle: true),
                  ),
                ),
              if (_filter == 'Playlists')
                IconButton.filledTonal(
                  tooltip: 'Create playlist',
                  icon: const Icon(Icons.playlist_add_rounded),
                  onPressed: () =>
                      _createPlaylistDialog(context, widget.controller),
                ),
              PopupMenuButton<String>(
                tooltip: 'Sort library',
                initialValue: _sort,
                onSelected: (value) => setState(() => _sort = value),
                itemBuilder: (_) => [
                  for (final sort in const ['A–Z', 'Z–A', 'Newest'])
                    PopupMenuItem(value: sort, child: Text(sort)),
                ],
                icon: const Icon(Icons.sort_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _EmptyState(
                  icon: Icons.library_music_outlined,
                  title: 'No ${_filter.toLowerCase()} found',
                  message: _filter == 'Downloads'
                      ? 'Download songs from their More menu for offline playback.'
                      : 'Add them in Jellyfin, then refresh your library.',
                )
              : ListView.builder(
                  key: PageStorageKey('library-$_filter-$_sort'),
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _ItemTile(
                      item: item,
                      controller: widget.controller,
                      onTap: () => _openOrPlay(
                        context,
                        widget.controller,
                        widget.audioHandler,
                        item,
                        contextItems: audioContext,
                      ),
                      onMore: () => _showItemActions(
                        context,
                        widget.controller,
                        widget.audioHandler,
                        item,
                        contextItems: audioContext,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    super.key,
    required this.item,
    required this.controller,
    required this.onTap,
    required this.onMore,
    this.reorderIndex,
  });

  final JellyfinItem item;
  final AppController controller;
  final VoidCallback onTap;
  final VoidCallback onMore;
  final int? reorderIndex;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 68,
    leading: _Artwork(item: item, controller: controller, size: 52),
    title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      item.subtitle.isEmpty ? item.type : item.subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: onTap,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.downloadingId == item.id)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (controller.isQueuedForDownload(item.id))
          const Icon(Icons.schedule_rounded, size: 20)
        else if (controller.isDownloaded(item.id))
          const Icon(Icons.offline_pin_rounded, size: 20),
        if (reorderIndex case final index?)
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.drag_handle_rounded),
            ),
          ),
        IconButton(
          tooltip: 'More options for ${item.name}',
          onPressed: onMore,
          icon: const Icon(Icons.more_vert),
        ),
      ],
    ),
  );
}

class _DetailScreen extends StatefulWidget {
  const _DetailScreen({
    required this.item,
    required this.controller,
    required this.audioHandler,
  });

  final JellyfinItem item;
  final AppController controller;
  final JellyfinAudioHandler audioHandler;

  @override
  State<_DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<_DetailScreen> {
  bool _loading = true;
  String? _error;
  List<JellyfinItem> _children = const [];
  late String _name;

  @override
  void initState() {
    super.initState();
    _name = widget.item.name;
    _load();
  }

  Future<void> _renamePlaylist() async {
    final name = await _promptForText(
      context,
      title: 'Rename playlist',
      initialValue: _name,
      action: 'Rename',
    );
    if (name == null) return;
    try {
      await widget.controller.renamePlaylist(widget.item, name);
      if (mounted) setState(() => _name = name.trim());
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not rename playlist: $error')),
      );
    }
  }

  Future<void> _movePlaylistItem(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= _children.length ||
        newIndex < 0 ||
        newIndex >= _children.length) {
      return;
    }
    final before = [..._children];
    final item = _children.removeAt(oldIndex);
    _children.insert(newIndex, item);
    setState(() {});
    try {
      await widget.controller.movePlaylistItem(widget.item, item, newIndex);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _children = before);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reorder playlist: $error')),
      );
    }
  }

  Widget _childTile(int index, {bool reorderable = false}) {
    final child = _children[index];
    final tracks = _children.where((item) => item.isAudio).toList();
    return _ItemTile(
      key: ValueKey(child.playlistItemId ?? '${child.id}-$index'),
      item: child,
      controller: widget.controller,
      reorderIndex: reorderable ? index : null,
      onTap: () => _openOrPlay(
        context,
        widget.controller,
        widget.audioHandler,
        child,
        contextItems: tracks,
      ),
      onMore: () => _showItemActions(
        context,
        widget.controller,
        widget.audioHandler,
        child,
        contextItems: tracks,
        playlist: widget.item.isPlaylist ? widget.item : null,
        onChanged: _load,
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final children = await widget.controller.children(widget.item);
      if (!mounted) return;
      setState(() {
        _children = children;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _children.where((item) => item.isAudio).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_name),
        actions: [
          if (tracks.any((track) => !widget.controller.isDownloaded(track.id)))
            IconButton(
              tooltip: 'Download all songs',
              onPressed: () =>
                  _downloadItems(context, widget.controller, tracks),
              icon: const Icon(Icons.download_for_offline_outlined),
            ),
          if (widget.item.isPlaylist)
            IconButton(
              tooltip: 'Rename playlist',
              onPressed: _renamePlaylist,
              icon: const Icon(Icons.edit_outlined),
            ),
          AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final item = widget.controller.currentItem(widget.item);
              return IconButton(
                tooltip: item.isFavorite ? 'Remove favorite' : 'Add favorite',
                onPressed: () =>
                    _toggleFavorite(context, widget.controller, item),
                icon: Icon(
                  item.isFavorite ? Icons.favorite : Icons.favorite_border,
                ),
              );
            },
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _Artwork(
                    item: widget.item,
                    controller: widget.controller,
                    size: 240,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _name,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.item.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(widget.item.subtitle, textAlign: TextAlign.center),
                  ],
                  if (widget.item.overview case final overview?) ...[
                    const SizedBox(height: 12),
                    Text(
                      overview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (tracks.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _runPlayback(
                            context,
                            () => widget.audioHandler.playItems(tracks),
                          ),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: () => _runPlayback(
                            context,
                            () => widget.audioHandler.playItems(
                              tracks,
                              shuffle: true,
                            ),
                          ),
                          icon: const Icon(Icons.shuffle),
                          label: const Text('Shuffle'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error case final error?)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load this item',
                message: error,
                action: FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
            )
          else if (_children.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                icon: Icons.music_off_outlined,
                title: 'Nothing here yet',
                message: 'This collection has no playable music.',
              ),
            )
          else if (widget.item.isPlaylist)
            SliverReorderableList(
              itemCount: _children.length,
              onReorderItem: _movePlaylistItem,
              itemBuilder: (context, index) =>
                  _childTile(index, reorderable: true),
            )
          else
            SliverList.builder(
              itemCount: _children.length,
              itemBuilder: (context, index) => _childTile(index),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.controller, required this.audioHandler});

  final AppController controller;
  final JellyfinAudioHandler audioHandler;

  @override
  Widget build(BuildContext context) => StreamBuilder<MediaItem?>(
    stream: audioHandler.mediaItem,
    initialData: audioHandler.mediaItem.value,
    builder: (context, snapshot) {
      final item = snapshot.data;
      if (item == null) return const SizedBox.shrink();
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _NowPlayingScreen(
                controller: controller,
                audioHandler: audioHandler,
              ),
            ),
          ),
          child: SizedBox(
            height: 66,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(7),
                  child: _MediaArtwork(item: item, size: 52),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        item.artist ?? item.album ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                StreamBuilder<PlaybackState>(
                  stream: audioHandler.playbackState,
                  initialData: audioHandler.playbackState.value,
                  builder: (context, state) {
                    final playing = state.data?.playing ?? false;
                    return IconButton(
                      tooltip: playing ? 'Pause' : 'Play',
                      onPressed: playing
                          ? audioHandler.pause
                          : audioHandler.play,
                      icon: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Next song',
                  onPressed: audioHandler.skipToNext,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _NowPlayingScreen extends StatelessWidget {
  const _NowPlayingScreen({
    required this.controller,
    required this.audioHandler,
  });

  final AppController controller;
  final JellyfinAudioHandler audioHandler;

  @override
  Widget build(BuildContext context) => StreamBuilder<MediaItem?>(
    stream: audioHandler.mediaItem,
    initialData: audioHandler.mediaItem.value,
    builder: (context, itemSnapshot) {
      final item = itemSnapshot.data;
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close Now Playing',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          title: const Text('Now Playing'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Choose audio output',
              onPressed: item == null
                  ? null
                  : () => _showOutputDevices(context, controller, audioHandler),
              icon: const Icon(Icons.speaker_group_outlined),
            ),
            IconButton(
              tooltip: 'Open queue',
              onPressed: item == null
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            _QueueScreen(audioHandler: audioHandler),
                      ),
                    ),
              icon: const Icon(Icons.queue_music_rounded),
            ),
          ],
        ),
        body: item == null
            ? const _EmptyState(
                icon: Icons.music_off_outlined,
                title: 'Nothing playing',
                message: 'Choose something from your library.',
              )
            : SafeArea(
                top: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final artSize = (constraints.maxWidth - 48).clamp(
                      180.0,
                      420.0,
                    );
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                      child: Column(
                        children: [
                          _MediaArtwork(item: item, size: artSize),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      item.artist ?? item.album ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge,
                                    ),
                                  ],
                                ),
                              ),
                              AnimatedBuilder(
                                animation: controller,
                                builder: (context, _) {
                                  final original = _itemForMedia(
                                    controller,
                                    item,
                                  );
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip:
                                            controller.isDownloaded(original.id)
                                            ? 'Remove download'
                                            : controller.isQueuedForDownload(
                                                original.id,
                                              )
                                            ? 'View downloads'
                                            : 'Download',
                                        onPressed: () =>
                                            controller.isQueuedForDownload(
                                              original.id,
                                            )
                                            ? _showDownloadQueue(
                                                context,
                                                controller,
                                              )
                                            : _toggleDownload(
                                                context,
                                                controller,
                                                original,
                                              ),
                                        icon: Icon(
                                          controller.isDownloaded(original.id)
                                              ? Icons.download_done_rounded
                                              : Icons.download_rounded,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: original.isFavorite
                                            ? 'Remove favorite'
                                            : 'Add favorite',
                                        onPressed: () => _toggleFavorite(
                                          context,
                                          controller,
                                          original,
                                        ),
                                        icon: Icon(
                                          original.isFavorite
                                              ? Icons.favorite
                                              : Icons.favorite_border,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _ProgressControl(
                            item: item,
                            audioHandler: audioHandler,
                          ),
                          const SizedBox(height: 8),
                          StreamBuilder<PlaybackState>(
                            stream: audioHandler.playbackState,
                            initialData: audioHandler.playbackState.value,
                            builder: (context, stateSnapshot) {
                              final state =
                                  stateSnapshot.data ?? PlaybackState();
                              return _TransportControls(
                                state: state,
                                audioHandler: audioHandler,
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      );
    },
  );
}

class _ProgressControl extends StatelessWidget {
  const _ProgressControl({required this.item, required this.audioHandler});

  final MediaItem item;
  final JellyfinAudioHandler audioHandler;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: audioHandler.positionStream,
    initialData: audioHandler.playbackState.value.position,
    builder: (context, snapshot) {
      final duration = item.duration ?? Duration.zero;
      final rawPosition = snapshot.data ?? Duration.zero;
      final position = rawPosition > duration && duration > Duration.zero
          ? duration
          : rawPosition;
      final max = duration.inMilliseconds <= 0
          ? 1.0
          : duration.inMilliseconds.toDouble();
      return Semantics(
        label:
            'Playback position ${_formatDuration(position)} of ${_formatDuration(duration)}',
        value: _formatDuration(position),
        child: Column(
          children: [
            Slider(
              value: position.inMilliseconds.clamp(0, max.toInt()).toDouble(),
              max: max,
              onChanged: duration <= Duration.zero
                  ? null
                  : (value) => audioHandler.seek(
                      Duration(milliseconds: value.round()),
                    ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(position)),
                Text('-${_formatDuration(duration - position)}'),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({required this.state, required this.audioHandler});

  final PlaybackState state;
  final JellyfinAudioHandler audioHandler;

  @override
  Widget build(BuildContext context) {
    final shuffle = state.shuffleMode != AudioServiceShuffleMode.none;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          tooltip: shuffle ? 'Turn shuffle off' : 'Turn shuffle on',
          isSelected: shuffle,
          onPressed: () => audioHandler.setShuffleMode(
            shuffle
                ? AudioServiceShuffleMode.none
                : AudioServiceShuffleMode.all,
          ),
          icon: const Icon(Icons.shuffle_rounded),
        ),
        IconButton(
          tooltip: 'Previous song',
          iconSize: 38,
          onPressed: audioHandler.skipToPrevious,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        IconButton.filled(
          tooltip: state.playing ? 'Pause' : 'Play',
          iconSize: 42,
          onPressed: state.playing ? audioHandler.pause : audioHandler.play,
          icon: Icon(
            state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          ),
        ),
        IconButton(
          tooltip: 'Next song',
          iconSize: 38,
          onPressed: audioHandler.skipToNext,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        IconButton(
          tooltip: switch (state.repeatMode) {
            AudioServiceRepeatMode.none => 'Repeat is off',
            AudioServiceRepeatMode.one => 'Repeat one song',
            _ => 'Repeat all songs',
          },
          isSelected: state.repeatMode != AudioServiceRepeatMode.none,
          onPressed: () =>
              audioHandler.setRepeatMode(switch (state.repeatMode) {
                AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
                AudioServiceRepeatMode.all ||
                AudioServiceRepeatMode.group => AudioServiceRepeatMode.one,
                AudioServiceRepeatMode.one => AudioServiceRepeatMode.none,
              }),
          icon: Icon(
            state.repeatMode == AudioServiceRepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
          ),
        ),
      ],
    );
  }
}

class _QueueScreen extends StatelessWidget {
  const _QueueScreen({required this.audioHandler});

  final JellyfinAudioHandler audioHandler;

  Future<void> _clear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear queue?'),
        content: const Text('This removes every song from the current queue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await audioHandler.clearQueue();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<MediaItem>>(
    stream: audioHandler.queue,
    initialData: audioHandler.queue.value,
    builder: (context, snapshot) {
      final items = snapshot.data ?? const [];
      return Scaffold(
        appBar: AppBar(
          title: const Text('Queue'),
          actions: [
            if (items.isNotEmpty)
              IconButton(
                tooltip: 'Clear queue',
                onPressed: () => _clear(context),
                icon: const Icon(Icons.clear_all_rounded),
              ),
          ],
        ),
        body: items.isEmpty
            ? const _EmptyState(
                icon: Icons.queue_music_outlined,
                title: 'Your queue is empty',
                message: 'Play a song or collection to start a queue.',
              )
            : ReorderableListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: items.length,
                onReorderItem: audioHandler.moveQueueItem,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    key: ValueKey(item.id),
                    minTileHeight: 68,
                    leading: _MediaArtwork(item: item, size: 52),
                    title: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      item.artist ?? item.album ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => audioHandler.skipToQueueItem(index),
                    trailing: IconButton(
                      tooltip: 'Remove ${item.title} from queue',
                      onPressed: () => audioHandler.removeQueueItem(item),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  );
                },
              ),
      );
    },
  );
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.item,
    required this.controller,
    required this.size,
  });

  final JellyfinItem item;
  final AppController controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    final client = controller.client;
    final artworkId = item.artworkId;
    return Semantics(
      image: true,
      label: 'Artwork for ${item.name}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: size,
          child: client == null || artworkId == null
              ? const _ArtworkPlaceholder()
              : Image.network(
                  client.imageUri(artworkId, width: size.ceil()).toString(),
                  headers: client.authorizationHeaders,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const _ArtworkPlaceholder(),
                ),
        ),
      ),
    );
  }
}

class _MediaArtwork extends StatelessWidget {
  const _MediaArtwork({required this.item, required this.size});

  final MediaItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final remote = item.extras?['remoteArtUri'];
    final artwork = remote is String ? Uri.tryParse(remote) : item.artUri;
    return Semantics(
      image: true,
      label: 'Artwork for ${item.title}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: size,
          child: artwork == null
              ? const _ArtworkPlaceholder()
              : Image.network(
                  artwork.toString(),
                  headers: item.artHeaders,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const _ArtworkPlaceholder(),
                ),
        ),
      ),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Center(child: Icon(Icons.music_note_rounded, size: 38)),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.secondaryAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 54, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 20), action!],
          ?secondaryAction,
        ],
      ),
    ),
  );
}

Future<void> _openOrPlay(
  BuildContext context,
  AppController controller,
  JellyfinAudioHandler audioHandler,
  JellyfinItem item, {
  List<JellyfinItem>? contextItems,
}) async {
  if (item.isAudio) {
    await _runPlayback(
      context,
      () => audioHandler.playItem(item, context: contextItems),
    );
  } else {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DetailScreen(
          item: item,
          controller: controller,
          audioHandler: audioHandler,
        ),
      ),
    );
  }
}

Future<void> _runPlayback(
  BuildContext context,
  Future<void> Function() operation,
) async {
  try {
    await operation();
  } on Object catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Playback failed: $error')));
  }
}

Future<void> _showItemActions(
  BuildContext context,
  AppController controller,
  JellyfinAudioHandler audioHandler,
  JellyfinItem item, {
  List<JellyfinItem>? contextItems,
  JellyfinItem? playlist,
  Future<void> Function()? onChanged,
}) async {
  final current = controller.currentItem(item);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: Icon(item.isAudio ? Icons.play_arrow : Icons.open_in_new),
            title: Text(item.isAudio ? 'Play now' : 'Open'),
            onTap: () {
              Navigator.pop(sheetContext);
              _openOrPlay(
                context,
                controller,
                audioHandler,
                item,
                contextItems: contextItems,
              );
            },
          ),
          if (item.isAudio)
            ListTile(
              leading: const Icon(Icons.queue_play_next),
              title: const Text('Play next'),
              onTap: () {
                Navigator.pop(sheetContext);
                _runPlayback(context, () => audioHandler.playNext(item));
              },
            ),
          if (item.isAudio)
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: const Text('Add to queue'),
              onTap: () {
                Navigator.pop(sheetContext);
                _runPlayback(context, () => audioHandler.addItemToQueue(item));
              },
            ),
          if (item.isAudio)
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('Add to playlist'),
              onTap: () {
                Navigator.pop(sheetContext);
                _choosePlaylist(context, controller, item);
              },
            ),
          if (item.isAudio || item.isAlbum || item.isArtist || item.isPlaylist)
            ListTile(
              leading: Icon(
                controller.isDownloaded(item.id)
                    ? Icons.download_done_rounded
                    : controller.isQueuedForDownload(item.id)
                    ? Icons.schedule_rounded
                    : Icons.download_rounded,
              ),
              title: Text(
                controller.downloadingId == item.id
                    ? 'Downloading…'
                    : controller.isQueuedForDownload(item.id)
                    ? 'View downloads'
                    : controller.isDownloaded(item.id)
                    ? 'Remove download'
                    : item.isAudio
                    ? 'Download song'
                    : 'Download ${item.isAlbum
                          ? 'album'
                          : item.isArtist
                          ? 'artist'
                          : 'playlist'}',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                if (controller.isQueuedForDownload(item.id)) {
                  _showDownloadQueue(context, controller);
                } else if (item.isAudio) {
                  _toggleDownload(context, controller, item);
                } else {
                  _queueCollectionDownload(context, controller, item);
                }
              },
            ),
          if (playlist != null && item.playlistItemId != null)
            ListTile(
              leading: const Icon(Icons.playlist_remove_rounded),
              title: const Text('Remove from this playlist'),
              onTap: () async {
                Navigator.pop(sheetContext);
                try {
                  await controller.removeFromPlaylist(playlist, item);
                  await onChanged?.call();
                } on Object catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Could not update playlist: $error'),
                    ),
                  );
                }
              },
            ),
          ListTile(
            leading: Icon(
              current.isFavorite ? Icons.heart_broken : Icons.favorite_border,
            ),
            title: Text(
              current.isFavorite ? 'Remove favorite' : 'Add favorite',
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              _toggleFavorite(context, controller, current);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _toggleFavorite(
  BuildContext context,
  AppController controller,
  JellyfinItem item,
) async {
  try {
    await controller.toggleFavorite(item);
  } on Object catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not update favorite: $error')),
    );
  }
}

Future<void> _toggleDownload(
  BuildContext context,
  AppController controller,
  JellyfinItem item,
) async {
  final removing = controller.isDownloaded(item.id);
  if (removing) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove download?'),
        content: Text('${item.name} will no longer be available offline.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
  }
  try {
    if (removing) {
      await controller.removeDownload(item);
    } else {
      await controller.enqueueDownload(item);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removing ? 'Download removed.' : '${item.name} added to downloads.',
        ),
      ),
    );
  } on Object catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not update download: $error')),
    );
  }
}

Future<void> _downloadItems(
  BuildContext context,
  AppController controller,
  List<JellyfinItem> items,
) async {
  final pending = items
      .where((item) => !controller.isDownloaded(item.id))
      .toList();
  if (pending.isEmpty) return;
  final queued = controller.enqueueDownloads(pending);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        queued == 0
            ? 'These songs are already downloaded or queued.'
            : '$queued ${queued == 1 ? 'song' : 'songs'} added to downloads.',
      ),
    ),
  );
}

Future<void> _queueCollectionDownload(
  BuildContext context,
  AppController controller,
  JellyfinItem item,
) async {
  try {
    final queued = await controller.enqueueDownload(item);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          queued == 0
              ? '${item.name} is already downloaded or queued.'
              : '$queued ${queued == 1 ? 'song' : 'songs'} added to downloads.',
        ),
      ),
    );
  } on Object catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not queue download: $error')));
  }
}

Future<void> _showDownloadQueue(
  BuildContext context,
  AppController controller,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheetContext) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final current = controller.downloadingItem;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 16, 12),
                child: Row(
                  children: [
                    Text(
                      'Downloads',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    if (controller.downloadError != null)
                      TextButton(
                        onPressed: controller.clearDownloadError,
                        child: const Text('Dismiss error'),
                      ),
                  ],
                ),
              ),
              if (controller.downloadError case final error?)
                ListTile(
                  leading: Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: const Text('Download failed'),
                  subtitle: Text(error),
                ),
              if (current != null)
                ListTile(
                  leading: const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  title: Text(current.name),
                  subtitle: const Text('Downloading for offline play'),
                ),
              for (
                var index = 0;
                index < controller.downloadQueue.length;
                index++
              )
                ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(controller.downloadQueue[index].name),
                  subtitle: const Text('Waiting'),
                ),
              if (current == null &&
                  controller.downloadQueue.isEmpty &&
                  controller.downloadError == null)
                const ListTile(
                  leading: Icon(Icons.download_done_rounded),
                  title: Text('Downloads complete'),
                ),
            ],
          ),
        ),
      );
    },
  ),
);

Future<void> _showOutputDevices(
  BuildContext context,
  AppController controller,
  JellyfinAudioHandler audioHandler,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: FutureBuilder<List<JellyfinDevice>>(
        future: controller.devices(),
        builder: (context, snapshot) {
          final devices = snapshot.data ?? const [];
          return ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Text(
                  'Choose audio output',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.phone_iphone_rounded),
                title: Text(
                  Platform.isIOS
                      ? 'This device, Bluetooth, or AirPlay'
                      : 'This device or connected audio',
                ),
                subtitle: const Text('Keep playback controlled by Shrimphony'),
                onTap: Platform.isAndroid
                    ? () async {
                        try {
                          await const MethodChannel(
                            'com.thomaskleckner.shrimphony/audio_output',
                          ).invokeMethod<void>('show');
                        } on PlatformException catch (error) {
                          if (!sheetContext.mounted) return;
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(content: Text(error.message ?? '$error')),
                          );
                        }
                      }
                    : null,
                trailing: Platform.isIOS
                    ? const SizedBox.square(
                        dimension: 48,
                        child: UiKitView(
                          viewType:
                              'com.thomaskleckner.shrimphony/audio_route_picker',
                        ),
                      )
                    : const Icon(Icons.chevron_right_rounded),
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 4),
                child: Text('Jellyfin devices'),
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: const Text('Could not load Jellyfin devices'),
                  subtitle: Text('${snapshot.error}'),
                )
              else if (devices.isEmpty)
                const ListTile(
                  leading: Icon(Icons.tv_off_outlined),
                  title: Text('No other controllable clients are online'),
                )
              else
                for (final device in devices)
                  ListTile(
                    leading: const Icon(Icons.cast_connected_rounded),
                    title: Text(device.name),
                    subtitle: Text(device.client),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      try {
                        await audioHandler.playOnDevice(device);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Playback sent to ${device.name}.'),
                          ),
                        );
                      } on Object catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Could not connect: $error')),
                        );
                      }
                    },
                  ),
            ],
          );
        },
      ),
    ),
  );
}

Future<void> _choosePlaylist(
  BuildContext context,
  AppController controller,
  JellyfinItem item,
) async {
  const create = '__create_playlist__';
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded),
            title: const Text('New playlist'),
            onTap: () => Navigator.pop(context, create),
          ),
          for (final playlist in controller.playlists)
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: Text(playlist.name),
              onTap: () => Navigator.pop(context, playlist.id),
            ),
        ],
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  if (choice == create) {
    await _createPlaylistDialog(context, controller, firstItem: item);
    return;
  }
  final playlist = controller.playlists.firstWhere(
    (playlist) => playlist.id == choice,
  );
  try {
    await controller.addToPlaylist(playlist, item);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Added to ${playlist.name}.')));
    }
  } on Object catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not update playlist: $error')),
    );
  }
}

Future<void> _createPlaylistDialog(
  BuildContext context,
  AppController controller, {
  JellyfinItem? firstItem,
}) async {
  final name = await _promptForText(
    context,
    title: 'New playlist',
    action: 'Create',
  );
  if (name == null) return;
  try {
    final playlist = await controller.createPlaylist(
      name,
      firstItem: firstItem,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Created ${playlist.name}.')));
    }
  } on Object catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not create playlist: $error')),
    );
  }
}

Future<String?> _promptForText(
  BuildContext context, {
  required String title,
  required String action,
  String initialValue = '',
}) async {
  final input = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: input,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) {
          if (input.text.trim().isNotEmpty) {
            Navigator.pop(context, input.text.trim());
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (input.text.trim().isNotEmpty) {
              Navigator.pop(context, input.text.trim());
            }
          },
          child: Text(action),
        ),
      ],
    ),
  );
  input.dispose();
  return result;
}

JellyfinItem _itemForMedia(AppController controller, MediaItem media) {
  final raw = media.extras?['jellyfin'];
  final fallback = raw is Map
      ? JellyfinItem.fromJson(raw.cast<String, dynamic>())
      : JellyfinItem(id: media.id, name: media.title, type: 'Audio');
  return controller.currentItem(fallback);
}

String _formatDuration(Duration value) {
  final safe = value.isNegative ? Duration.zero : value;
  final minutes = safe.inMinutes;
  final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _formatBytes(int value) {
  if (value < 1024) return '$value B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  if (value < 1024 * 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
