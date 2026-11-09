import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/library.dart';
import '../data/progress.dart';
import '../models/lesson.dart';
import 'player_screen.dart';
import 'sync_screen.dart';
import 'theme.dart';
import 'transport_bar.dart' show fmt;
import '../models/notation.dart';

class LibraryScreen extends StatefulWidget {
  final LibraryStore store;
  final ProgressStore progress;
  const LibraryScreen({super.key, required this.store, required this.progress});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Manifest>? songs;
  String? error;

  @override
  void initState() {
    super.initState();
    _reload().then((_) {
      // deep link from the desktop library: /app/?song=<id>
      final id = widget.store.initialSongId;
      final m = songs?.where((s) => s.id == id).firstOrNull;
      if (m != null && mounted) _open(m);
    });
  }

  Future<void> _reload() async {
    try {
      final s = await widget.store.list();
      setState(() {
        songs = s;
        error = null;
      });
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _importFile() => _guard(() async {
        final file = await FilePicker.pickFile();
        if (file == null) return;
        final bytes = await file.readAsBytes();
        final m = await widget.store.importBytes(bytes);
        await _reload();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${m.title}')));
      });

  Future<void> _open(Manifest m) => _guard(() async {
        final song = await widget.store.load(m.id);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PlayerScreen(song: song, progress: widget.progress)),
        );
        setState(() {}); // refresh mastery
      });

  Future<void> _delete(Manifest m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove "${m.title}"?'),
        content: const Text('The song is deleted from this device. Your progress is kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) {
      await _guard(() async {
        await widget.store.delete(m.id);
        await _reload();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = songs;
    final lastId = widget.progress.lastPlayedSong;
    final last = list?.where((m) => m.id == lastId).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text.rich(TextSpan(children: [
          TextSpan(text: 'Fret', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: 'line', style: TextStyle(fontWeight: FontWeight.w800, color: C.accent)),
        ])),
        actions: [
          if (widget.store.desktopUiUrl != null)
            TextButton.icon(
              onPressed: widget.store.openDesktopUi,
              icon: const Icon(Icons.add),
              label: const Text('Add songs'),
            ),
          if (widget.store.supportsLanSync)
            TextButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SyncScreen(store: widget.store, progress: widget.progress)),
                );
                _reload();
              },
              icon: const Icon(Icons.wifi),
              label: const Text('Get songs from PC'),
            ),
          TextButton.icon(onPressed: _importFile, icon: const Icon(Icons.file_open), label: const Text('Open file')),
          PopupMenuButton<Notation>(
            tooltip: 'Note names',
            icon: const Icon(Icons.music_note),
            initialValue: notation.value,
            onSelected: (n) async {
              await setNotation(n);
              setState(() {});
            },
            itemBuilder: (_) => [
              const PopupMenuItem(enabled: false, child: Text('Note names')),
              for (final n in Notation.values)
                CheckedPopupMenuItem(
                  value: n,
                  checked: notation.value == n,
                  child: Text('${n.sample}  ·  ${n.label}'),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: error != null
            ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(error!))])
            : list == null
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? _empty()
                    : ListView(padding: const EdgeInsets.all(16), children: [
                        if (last != null) ...[
                          Card(
                            color: C.accent.withValues(alpha: 0.12),
                            child: ListTile(
                              leading: const Icon(Icons.play_circle_fill, color: C.accent, size: 40),
                              title: const Text('Continue'),
                              subtitle: Text(last.title),
                              onTap: () => _open(last),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        LayoutBuilder(builder: (context, box) {
                          final cols = (box.maxWidth / 300).floor().clamp(1, 5);
                          return GridView.count(
                            crossAxisCount: cols,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            childAspectRatio: 1.5,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            children: [for (final m in list) _card(m)],
                          );
                        }),
                      ]),
      ),
    );
  }

  Widget _empty() => ListView(children: [
        const SizedBox(height: 80),
        const Icon(Icons.library_music, size: 64, color: C.dim),
        const SizedBox(height: 16),
        const Center(child: Text('No songs yet', style: TextStyle(fontSize: 20))),
        const SizedBox(height: 8),
        const Center(
          child: Text('Process a song on your PC, then pull it here or open the .fretpack file.',
              style: TextStyle(color: C.dim), textAlign: TextAlign.center),
        ),
        const SizedBox(height: 24),
        Center(
          child: FilledButton.icon(
            onPressed: () => _guard(() async {
              await widget.store.importDemo();
              await _reload();
            }),
            icon: const Icon(Icons.music_note),
            label: const Text('Add the demo song'),
          ),
        ),
      ]);

  Widget _card(Manifest m) {
    final mastery = widget.progress.cachedMastery(m.id);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(m),
        onLongPress: () => _delete(m),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(m.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              PopupMenuButton<String>(
                onSelected: (_) => _delete(m),
                itemBuilder: (_) => [const PopupMenuItem(value: 'del', child: Text('Remove'))],
              ),
            ]),
            Text(m.artist.isEmpty ? 'Unknown artist' : m.artist, style: const TextStyle(color: C.dim)),
            const Spacer(),
            Text(
              [fmt(m.duration), '${m.bpm.round()} BPM', if (m.key != null) chordName(m.key!), if (m.capo > 0) 'capo ${m.capo}']
                  .join(' · '),
              style: const TextStyle(color: C.dim, fontSize: 12),
            ),
            const SizedBox(height: 8),
            for (final e in mastery.entries)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(children: [
                  SizedBox(width: 52, child: Text(e.key, style: const TextStyle(fontSize: 11, color: C.dim))),
                  Expanded(child: LinearProgressIndicator(value: e.value, color: C.ok, backgroundColor: C.line)),
                  SizedBox(width: 40, child: Text(' ${(e.value * 100).round()}%', style: const TextStyle(fontSize: 11))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
