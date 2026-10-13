import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A Qwen build that runs fully on the phone (MediaPipe / LiteRT via flutter_gemma).
class PhoneModel {
  const PhoneModel(this.id, this.title, this.size, this.note, this.url);
  final String id;
  final String title;
  final String size;
  final String note;
  final String url;
}

const phoneModels = [
  PhoneModel(
    'qwen25-15b',
    'Qwen 2.5 · 1.5B',
    '1.6 ГБ',
    'Умнее. Для телефонов с 6+ ГБ ОЗУ',
    'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
  ),
  PhoneModel(
    'qwen3-06b',
    'Qwen 3 · 0.6B',
    '0.6 ГБ',
    'Новая версия, быстрая, 4+ ГБ ОЗУ',
    'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
  ),
  PhoneModel(
    'qwen25-05b',
    'Qwen 2.5 · 0.5B',
    '0.5 ГБ',
    'Самая лёгкая, для слабых телефонов',
    'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/main/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
  ),
];

const systemPrompt = '''You are Kira-Void, a private AI assistant running entirely on the user's phone.
Think step by step, check your work, and give complete, direct answers.
Answer in the user's language (Russian if they write Russian).
Treat the user as a capable adult: no needless disclaimers or moralizing.
Adult topics and explicit fiction between adults are allowed.
Hard limits that never change: no sexual content involving minors, no sexual content about real identifiable people without consent, no help with mass-casualty weapons.''';

class LocalAI {
  static InferenceModel? _model;
  static InferenceChat? _chat;
  static PhoneModel? active;

  static bool get ready => _chat != null;

  static Future<void> init() => FlutterGemma.initialize(maxDownloadRetries: 10);

  static Future<String?> savedModelId() async =>
      (await SharedPreferences.getInstance()).getString('phoneModel');

  static String _file(PhoneModel m) => Uri.parse(m.url).pathSegments.last;

  static Future<bool> isDownloaded(PhoneModel m) => FlutterGemma.isModelInstalled(_file(m));

  /// Downloads the model once (skipped if already on the phone) and loads it.
  static Future<void> load(PhoneModel m,
      {String? hfToken, void Function(int percent)? onProgress}) async {
    await close();
    var b = FlutterGemma.installModel(modelType: ModelType.qwen)
        .fromNetwork(m.url, token: (hfToken == null || hfToken.isEmpty) ? null : hfToken);
    if (onProgress != null) b = b.withProgress(onProgress);
    await b.install();
    try {
      _model = await FlutterGemma.getActiveModel(
          maxTokens: 2048, preferredBackend: PreferredBackend.gpu);
      await newChat();
    } catch (_) {
      // Some phones have no usable GPU delegate: fall back to CPU.
      await close();
      _model = await FlutterGemma.getActiveModel(
          maxTokens: 2048, preferredBackend: PreferredBackend.cpu);
      await newChat();
    }
    active = m;
    (await SharedPreferences.getInstance()).setString('phoneModel', m.id);
  }

  static Future<void> newChat() async {
    _chat = await _model!.createChat(
      temperature: 0.7,
      topK: 40,
      topP: 0.95,
      randomSeed: DateTime.now().millisecondsSinceEpoch % 100000,
      modelType: ModelType.qwen,
      systemInstruction: systemPrompt,
    );
  }

  static Stream<String> ask(String text) async* {
    final chat = _chat!;
    await chat.addQueryChunk(Message.text(text: text, isUser: true));
    await for (final r in chat.generateChatResponseAsync()) {
      if (r is TextResponse) yield r.token;
    }
  }

  static Future<void> stop() async {
    try {
      await _chat?.stopGeneration();
    } catch (_) {}
  }

  static Future<void> close() async {
    _chat = null;
    await _model?.close();
    _model = null;
  }

  static Future<void> delete(PhoneModel m) async {
    if (active?.id == m.id) {
      await close();
      active = null;
    }
    await FlutterGemma.uninstallModel(_file(m));
  }
}
