import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../models/lesson.dart';
import 'fretpack.dart';
import 'library_io.dart' if (dart.library.js_interop) 'library_web.dart' as impl;

/// Where songs live. Android: extracted on device, fully offline.
/// Web/PWA: streamed from the PC that served the app, plus in-memory imports.
abstract class LibraryStore {
  Future<List<Manifest>> list();
  Future<Manifest> importBytes(Uint8List bytes);
  Future<void> delete(String id);
  Future<LoadedSong> load(String id);

  /// True when songs can be pulled from a PC over the LAN (native only;
  /// on web the PC library is already the source).
  bool get supportsLanSync;

  /// Desktop "add songs" page when this app runs inside the PC (web build
  /// opened from the desktop app / localhost). Null on tablets.
  Uri? get desktopUiUrl => null;

  /// Leave the player for the desktop "add songs" page.
  void openDesktopUi() {}

  /// Song to open on start (`/app/?song=<id>`, used by the desktop library).
  String? get initialSongId => null;

  Future<Manifest> importDemo() async {
    final data = await rootBundle.load('assets/demo.fretpack');
    return importBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }
}

LibraryStore createLibraryStore() => impl.createStore();
