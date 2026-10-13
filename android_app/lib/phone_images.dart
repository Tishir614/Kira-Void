import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stable Diffusion 1.5 running on the phone (MediaPipe Image Generator, see MainActivity.kt).
class PhoneImages {
  static const _channel = MethodChannel('kira_void/images');
  static const _vocab = 'bpe_simple_vocab_16e6.txt';
  static String? modelDir;

  static bool get ready => modelDir != null;

  static Future<void> load() async {
    final dir = (await SharedPreferences.getInstance()).getString('imageModelDir');
    if (dir != null && File('$dir/$_vocab').existsSync()) modelDir = dir;
  }

  static Future<Directory> _root() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/image_model');

  /// Unpacks the zip made by tools/convert_sd_for_phone.py (or the Codemagic workflow).
  static Future<void> installZip(String zipPath) async {
    final root = await _root();
    if (root.existsSync()) await root.delete(recursive: true);
    await root.create(recursive: true);
    final out = root.path;
    await Isolate.run(() => extractFileToDisk(zipPath, out));
    final vocab = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith(_vocab))
        .firstOrNull;
    if (vocab == null) {
      await root.delete(recursive: true);
      throw 'В архиве нет модели (не найден $_vocab)';
    }
    modelDir = vocab.parent.path;
    (await SharedPreferences.getInstance()).setString('imageModelDir', modelDir!);
  }

  /// Downloads a model zip from a direct link, then installs it.
  static Future<void> installFromUrl(String url, void Function(int percent) onProgress) async {
    final tmp = File('${(await getTemporaryDirectory()).path}/image-model.zip');
    final resp = await http.Client().send(http.Request('GET', Uri.parse(url.trim())));
    if (resp.statusCode != 200) throw 'Ошибка загрузки: ${resp.statusCode}';
    final total = resp.contentLength ?? 0;
    var got = 0;
    final sink = tmp.openWrite();
    await for (final chunk in resp.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress(got * 100 ~/ total);
    }
    await sink.close();
    try {
      await installZip(tmp.path);
    } finally {
      if (tmp.existsSync()) await tmp.delete();
    }
  }

  static Future<void> delete() async {
    await _channel.invokeMethod('close');
    final root = await _root();
    if (root.existsSync()) await root.delete(recursive: true);
    modelDir = null;
    (await SharedPreferences.getInstance()).remove('imageModelDir');
  }

  /// [photo] switches to photo mode: keeps the photo's outlines and repaints it by the prompt.
  static Future<Uint8List> generate(String prompt,
      {Uint8List? photo, int steps = 20, int? seed}) async {
    checkPrompt(prompt);
    final png = await _channel.invokeMethod<Uint8List>('generate', {
      'dir': modelDir,
      'prompt': '$prompt, masterpiece, best quality, highly detailed, sharp focus, '
          'anatomically correct, perfect hands',
      'steps': steps,
      'seed': seed ?? DateTime.now().millisecondsSinceEpoch % 1000000,
      'image': photo,
    });
    return png!;
  }
}

final _minor = RegExp(
  r'\b(child|children|kid|kids|minor|underage|under-age|loli|lolita|shota|toddler|'
  r'infant|preteen|pre-teen|teen|teenage|teenager|schoolgirl|schoolboy|young[- ]?looking)\b|'
  r'(ребен|ребён|детск|дети|малолет|несовершеннолет|школьниц|школьник|подрост|лоли)',
  caseSensitive: false,
  unicode: true,
);
final _age = RegExp(
  r'(\d{1,2})\s*[- ]?\s*(years?[- ]?old|yrs?[- ]?old|y/?o\b|yo\b|лет|летн|года?\b)|'
  r'\b(aged?|возраст\w*)\s*[:=]?\s*(\d{1,2})\b',
  caseSensitive: false,
  unicode: true,
);

/// Same hard limit as the PC version: nothing involving minors.
void checkPrompt(String prompt) {
  final ages = _age
      .allMatches(prompt)
      .map((m) => int.tryParse(m.group(1) ?? m.group(4) ?? ''))
      .whereType<int>();
  if (_minor.hasMatch(prompt) || ages.any((a) => a < 18)) {
    throw 'Заблокировано: запросы с участием несовершеннолетних запрещены.';
  }
}
