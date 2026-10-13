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

/// Linux build: no on-device engine (flutter_gemma is removed by tools/prepare_linux.sh);
/// chat goes to the local Kira-Void server instead.
class LocalAI {
  static PhoneModel? active;
  static bool get ready => false;
  static Future<void> init() async {}
  static Future<String?> savedModelId() async =>
      (await SharedPreferences.getInstance()).getString('phoneModel');
  static Future<bool> isDownloaded(PhoneModel m) async => false;
  static Future<void> load(PhoneModel m,
          {String? hfToken, void Function(int percent)? onProgress}) async =>
      throw UnsupportedError('On-device models are not available on Linux');
  static Future<void> newChat() async {}
  static Stream<String> ask(String text) => const Stream.empty();
  static Future<void> stop() async {}
  static Future<void> close() async {}
  static Future<void> delete(PhoneModel m) async {}
}
