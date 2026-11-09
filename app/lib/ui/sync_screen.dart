import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/library.dart';
import '../data/progress.dart';
import '../data/sync.dart';
import 'theme.dart';
import 'transport_bar.dart' show fmt;

/// Pull songs from the PC. Pair once by scanning the QR code shown in the
/// desktop app (or typing its address); the host is remembered.
class SyncScreen extends StatefulWidget {
  final LibraryStore store;
  final ProgressStore progress;
  const SyncScreen({super.key, required this.store, required this.progress});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  PcHost? host;
  List<RemotePackage>? remote;
  Set<String> local = {};
  final progress = <String, double>{};
  String? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    final saved = widget.progress.lastHost;
    if (saved != null) _connect(parseHost(saved));
  }

  Future<void> _connect(PcHost? h) async {
    if (h == null) {
      setState(() => error = 'That is not a Fretline address');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final list = await listPackages(h);
      final mine = await widget.store.list();
      await widget.progress.setLastHost('${h.address}:${h.port}');
      setState(() {
        host = h;
        remote = list;
        local = mine.map((m) => m.id).toSet();
      });
    } catch (e) {
      setState(() => error = 'Could not reach ${h.address}:${h.port}. '
          'Is the desktop app open and the tablet on the same Wi-Fi?');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _scan() async {
    final text = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const _ScanPage()));
    if (text != null) await _connect(parseHost(text));
  }

  Future<void> _type() async {
    final ctl = TextEditingController(text: widget.progress.lastHost ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('PC address'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: '192.168.1.20:8765'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Connect')),
        ],
      ),
    );
    if (text != null) await _connect(parseHost(text));
  }

  Future<void> _download(RemotePackage p) async {
    final h = host!;
    setState(() => progress[p.id] = 0);
    try {
      final bytes = await download(h, p, (f) => setState(() => progress[p.id] = f));
      await widget.store.importBytes(bytes);
      setState(() => local.add(p.id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${p.title}: $e')));
    } finally {
      if (mounted) setState(() => progress.remove(p.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Get songs from PC'),
        actions: [
          if (host != null) IconButton(tooltip: 'Refresh', onPressed: () => _connect(host), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(host != null ? Icons.link : Icons.link_off, color: host != null ? C.ok : C.dim),
                const SizedBox(width: 8),
                Text(host != null ? 'Connected to ${host!.address}:${host!.port}' : 'Not connected',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 6),
              const Text('Open Fretline on your PC and scan the QR code it shows.', style: TextStyle(color: C.dim)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                FilledButton.icon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan QR')),
                OutlinedButton.icon(onPressed: _type, icon: const Icon(Icons.keyboard), label: const Text('Type address')),
              ]),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: C.bad)),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 16),
        if (loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (!loading && remote != null && remote!.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No songs on the PC yet. Drop a song into the desktop app first.',
                style: TextStyle(color: C.dim), textAlign: TextAlign.center),
          ),
        if (!loading && remote != null)
          for (final p in remote!) _row(p),
      ]),
    );
  }

  Widget _row(RemotePackage p) {
    final have = local.contains(p.id);
    final prog = progress[p.id];
    return Card(
      child: ListTile(
        title: Text(p.title),
        subtitle: prog != null
            ? LinearProgressIndicator(value: prog, color: C.accent, backgroundColor: C.line)
            : Text('${p.artist.isEmpty ? 'Unknown artist' : p.artist} · ${fmt(p.duration)} · ${(p.size / 1e6).toStringAsFixed(1)} MB'),
        trailing: have
            ? const Chip(avatar: Icon(Icons.check, color: C.ok, size: 18), label: Text('On tablet'))
            : FilledButton.tonal(onPressed: prog == null ? () => _download(p) : null, child: const Text('Download')),
      ),
    );
  }
}

class _ScanPage extends StatefulWidget {
  const _ScanPage();
  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan the code on your PC')),
      body: Stack(children: [
        MobileScanner(
          onDetect: (capture) {
            if (_done) return;
            for (final b in capture.barcodes) {
              final v = b.rawValue;
              if (v != null && parseHost(v) != null) {
                _done = true;
                Navigator.pop(context, v);
                return;
              }
            }
          },
        ),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: C.accent, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ]),
    );
  }
}
