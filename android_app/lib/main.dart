import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_ai.dart';

const violet = Color(0xFF9D6BFF);
const violetDeep = Color(0xFF5B2EDB);
const bgTop = Color(0xFF0B0816);
const bgBottom = Color(0xFF1C0F3A);
const surface = Color(0xFF17122A);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalAI.init();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: bgTop,
  ));
  runApp(const KiraVoidApp());
}

/// Connection settings + API calls to the Kira-Void server (python kira_void.py web --lan).
class Api {
  static String server = '';
  static String token = '';
  static String hfToken = '';
  static bool onPhone = true; // true: Qwen runs on the phone, false: on the PC server

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    server = p.getString('server') ?? '';
    token = p.getString('token') ?? '';
    hfToken = p.getString('hfToken') ?? '';
    onPhone = p.getBool('onPhone') ?? true;
  }

  static Future<void> setMode(bool phone) async {
    onPhone = phone;
    (await SharedPreferences.getInstance()).setBool('onPhone', phone);
  }

  static Future<void> setHfToken(String t) async {
    hfToken = t.trim();
    (await SharedPreferences.getInstance()).setString('hfToken', hfToken);
  }

  static Future<void> save(String s, String t) async {
    server = s.trim().replaceAll(RegExp(r'/+$'), '');
    if (server.isNotEmpty && !server.startsWith('http')) server = 'http://$server';
    token = t.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString('server', server);
    await p.setString('token', token);
  }

  static Map<String, String> get headers =>
      {'Content-Type': 'application/json', 'X-Kira-Token': token};

  static Uri uri(String path) => Uri.parse('$server$path');

  static Future<String> ping() async {
    final r = await http.get(uri('/ping'), headers: headers).timeout(const Duration(seconds: 8));
    if (r.statusCode == 401) throw 'Неверный пароль';
    if (r.statusCode != 200) throw 'Ошибка ${r.statusCode}';
    return (jsonDecode(r.body) as Map)['model'].toString();
  }

  static Stream<String> chat(List<Map<String, String>> messages) async* {
    final req = http.Request('POST', uri('/'))
      ..headers.addAll(headers)
      ..body = jsonEncode(messages);
    final resp = await http.Client().send(req);
    if (resp.statusCode == 401) throw 'Неверный пароль';
    yield* resp.stream.transform(utf8.decoder);
  }

  static Future<Uint8List> image(String prompt, {Uint8List? source}) async {
    final body = <String, String>{'prompt': prompt};
    if (source != null) body['image'] = base64Encode(source);
    final r = await http.post(uri(source == null ? '/image' : '/edit'),
        headers: headers, body: jsonEncode(body));
    if (r.statusCode != 200) throw utf8.decode(r.bodyBytes);
    return r.bodyBytes;
  }
}

class KiraVoidApp extends StatelessWidget {
  const KiraVoidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kira-Void',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
            seedColor: violet, brightness: Brightness.dark, surface: surface),
        scaffoldBackgroundColor: Colors.transparent,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      home: const Home(),
    );
  }
}

class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [bgTop, bgBottom]),
      ),
      child: Stack(children: [
        Positioned(
          top: -120,
          right: -80,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
              BoxShadow(color: violet.withValues(alpha: 0.25), blurRadius: 140, spreadRadius: 40)
            ]),
          ),
        ),
        child,
      ]),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    Api.load().then((_) {
      setState(() {
        ready = true;
        if (!Api.onPhone && Api.server.isEmpty) tab = 2;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Backdrop(child: SizedBox.expand());
    final pages = [const ChatPage(), const ImagePage(), const SettingsPage()];
    return Backdrop(
      child: Scaffold(
        body: SafeArea(child: IndexedStack(index: tab, children: pages)),
        bottomNavigationBar: NavigationBar(
          backgroundColor: bgTop.withValues(alpha: 0.9),
          indicatorColor: violet.withValues(alpha: 0.3),
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Чат'),
            NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Изображения'),
            NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Настройки'),
          ],
        ),
      ),
    );
  }
}

class Header extends StatelessWidget {
  const Header(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: violet, width: 3),
            boxShadow: [BoxShadow(color: violet.withValues(alpha: 0.6), blurRadius: 14)],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ShaderMask(
            shaderCallback: (r) =>
                const LinearGradient(colors: [Colors.white, violet]).createShader(r),
            child: Text(title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ),
        if (action != null) action!,
      ]),
    );
  }
}

// ---------------- Chat ----------------

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  List<Map<String, String>> msgs = [];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final raw = p.getString('history');
      if (raw != null) {
        setState(() => msgs = (jsonDecode(raw) as List)
            .map((e) => Map<String, String>.from(e as Map))
            .toList());
      }
    });
  }

  Future<void> persist() async =>
      (await SharedPreferences.getInstance()).setString('history', jsonEncode(msgs));

  void toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
      });

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || busy) return;
    input.clear();
    setState(() {
      msgs.add({'role': 'user', 'content': text});
      busy = true;
    });
    final history = List<Map<String, String>>.from(msgs);
    final answer = {'role': 'assistant', 'content': ''};
    setState(() => msgs.add(answer));
    toBottom();
    try {
      final stream = Api.onPhone ? LocalAI.ask(text) : Api.chat(history);
      await for (final t in stream) {
        setState(() => answer['content'] = answer['content']! + t);
        toBottom();
      }
    } catch (e) {
      setState(() => answer['content'] = '${answer['content']}\n⚠️ $e');
    }
    setState(() => busy = false);
    persist();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Header('Kira-Void',
          action: IconButton(
            tooltip: 'Новый чат',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () async {
              if (busy) await LocalAI.stop();
              if (LocalAI.ready) await LocalAI.newChat();
              setState(() => msgs = []);
              persist();
            },
          )),
      if (Api.onPhone && !LocalAI.ready)
        Expanded(child: ModelSetup(onReady: () => setState(() {})))
      else ...[
      Expanded(
        child: msgs.isEmpty
            ? const Center(
                child: Text('Спроси что угодно', style: TextStyle(color: Colors.white54, fontSize: 16)))
            : ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                itemCount: msgs.length,
                itemBuilder: (_, i) => Bubble(msgs[i], typing: busy && i == msgs.length - 1),
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: input,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => send(),
              decoration: const InputDecoration(hintText: 'Сообщение…'),
            ),
          ),
          const SizedBox(width: 8),
          GradientButton(
              icon: busy ? Icons.stop_rounded : Icons.arrow_upward,
              onTap: busy && Api.onPhone ? LocalAI.stop : send),
        ]),
      ),
      ],
    ]);
  }
}

class Bubble extends StatelessWidget {
  const Bubble(this.m, {super.key, this.typing = false});
  final Map<String, String> m;
  final bool typing;

  @override
  Widget build(BuildContext context) {
    final mine = m['role'] == 'user';
    final text = m['content']!;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Скопировано')));
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          decoration: BoxDecoration(
            gradient: mine ? const LinearGradient(colors: [violetDeep, violet]) : null,
            color: mine ? null : Colors.white.withValues(alpha: 0.07),
            border: mine ? null : Border.all(color: Colors.white.withValues(alpha: 0.08)),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(mine ? 20 : 6),
              bottomRight: Radius.circular(mine ? 6 : 20),
            ),
          ),
          child: text.isEmpty && typing
              ? const SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: violet))
              : SelectableText(text, style: const TextStyle(fontSize: 15.5, height: 1.4)),
        ),
      ),
    );
  }
}

class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.icon, required this.onTap, this.label});
  final IconData icon;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Ink(
          padding: EdgeInsets.symmetric(horizontal: label == null ? 14 : 22, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [violetDeep, violet]),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: violet.withValues(alpha: 0.45), blurRadius: 16)],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white),
            if (label != null) ...[
              const SizedBox(width: 8),
              Text(label!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ],
          ]),
        ),
      ),
    );
  }
}

// ---------------- Images ----------------

class ImagePage extends StatefulWidget {
  const ImagePage({super.key});
  @override
  State<ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<ImagePage> {
  final prompt = TextEditingController();
  Uint8List? source;
  Uint8List? result;
  bool busy = false;
  String? error;

  Future<void> pick() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1536);
    if (f != null) {
      final bytes = await f.readAsBytes();
      setState(() => source = bytes);
    }
  }

  Future<void> run() async {
    if (prompt.text.trim().isEmpty || busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (Api.server.isEmpty) throw 'Укажи адрес компьютера в настройках';
      final png = await Api.image(prompt.text.trim(), source: source);
      setState(() => result = png);
    } catch (e) {
      setState(() => error = e.toString());
    }
    setState(() => busy = false);
  }

  Future<void> share() async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/kira-void-${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(result!);
    await Share.shareXFiles([XFile(f.path)]);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      const Header('Создать'),
      if (Api.onPhone)
        const InfoCard(
            'Картинки рисует компьютер: SDXL слишком тяжёлая для телефона. '
            'Чат работает офлайн на телефоне, а для изображений запусти на ПК '
            '«python kira_void.py web --lan» и укажи его адрес в настройках.'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: Colors.white.withValues(alpha: 0.05),
                border: Border.all(color: violet.withValues(alpha: 0.35)),
              ),
              clipBehavior: Clip.antiAlias,
              child: busy
                  ? const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(color: violet),
                      SizedBox(height: 14),
                      Text('Рисую…', style: TextStyle(color: Colors.white70)),
                    ]))
                  : result != null
                      ? InteractiveViewer(child: Image.memory(result!, fit: BoxFit.contain))
                      : const Center(
                          child: Icon(Icons.auto_awesome, size: 64, color: Colors.white24)),
            ),
          ),
          if (result != null && !busy)
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton.icon(
                  onPressed: () => setState(() {
                        source = result;
                        result = null;
                      }),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Изменить это')),
              TextButton.icon(
                  onPressed: share, icon: const Icon(Icons.ios_share), label: const Text('Сохранить')),
            ]),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
            ),
          const SizedBox(height: 14),
          Row(children: [
            GestureDetector(
              onTap: pick,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white.withValues(alpha: 0.06),
                  border: Border.all(color: Colors.white12),
                ),
                clipBehavior: Clip.antiAlias,
                child: source == null
                    ? const Icon(Icons.add_photo_alternate_outlined, color: Colors.white60)
                    : Image.memory(source!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                source == null
                    ? 'Новое изображение по описанию.\nНажми слева, чтобы изменить своё фото.'
                    : 'Режим правки: опиши, что изменить.',
                style: const TextStyle(color: Colors.white60, height: 1.35),
              ),
            ),
            if (source != null)
              IconButton(
                  onPressed: () => setState(() => source = null), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: prompt,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
                hintText: source == null ? 'Опиши изображение…' : 'Что изменить…'),
          ),
          const SizedBox(height: 14),
          GradientButton(
              icon: Icons.auto_awesome,
              label: source == null ? 'Создать' : 'Изменить',
              onTap: run),
        ]),
      ),
    ]);
  }
}

// ---------------- Settings ----------------

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final server = TextEditingController(text: Api.server);
  late final token = TextEditingController(text: Api.token);
  late final hf = TextEditingController(text: Api.hfToken);
  String status = '';
  bool ok = false;

  Future<void> test() async {
    await Api.save(server.text, token.text);
    server.text = Api.server;
    setState(() => status = 'Проверяю…');
    try {
      final model = await Api.ping();
      setState(() {
        ok = true;
        status = 'Подключено · модель $model';
      });
    } catch (e) {
      setState(() {
        ok = false;
        status = 'Нет связи: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      const Header('Настройки'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Где работает чат', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, icon: Icon(Icons.smartphone), label: Text('На телефоне')),
              ButtonSegment(value: false, icon: Icon(Icons.computer), label: Text('На компьютере')),
            ],
            selected: {Api.onPhone},
            onSelectionChanged: (v) async {
              await Api.setMode(v.first);
              setState(() {});
            },
          ),
          const SizedBox(height: 18),
          if (Api.onPhone) ...[
            const PhoneModelsCard(),
            const SizedBox(height: 12),
            TextField(
              controller: hf,
              obscureText: true,
              onChanged: Api.setHfToken,
              decoration: const InputDecoration(
                  labelText: 'HuggingFace токен (если загрузка просит)',
                  prefixIcon: Icon(Icons.key_outlined)),
            ),
            const SizedBox(height: 28),
            const Text('Компьютер (для картинок)', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: violet.withValues(alpha: 0.10),
              border: Border.all(color: violet.withValues(alpha: 0.3)),
            ),
            child: const Text(
              'Kira-Void работает на твоём компьютере, телефон подключается к нему по Wi-Fi.\n\n'
              '1. На ПК: python kira_void.py web --lan\n'
              '2. Впиши сюда адрес, который он покажет (например http://192.168.1.5:8080)\n'
              '3. Телефон и ПК должны быть в одной сети',
              style: TextStyle(height: 1.45, color: Colors.white70),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: server,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
                labelText: 'Адрес сервера', prefixIcon: Icon(Icons.computer_outlined)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: token,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Пароль (KIRA_TOKEN), если задан', prefixIcon: Icon(Icons.lock_outline)),
          ),
          const SizedBox(height: 18),
          GradientButton(icon: Icons.wifi_tethering, label: 'Сохранить и проверить', onTap: test),
          const SizedBox(height: 14),
          if (status.isNotEmpty)
            Row(children: [
              Icon(ok ? Icons.check_circle : Icons.error_outline,
                  color: ok ? Colors.greenAccent : Colors.orangeAccent),
              const SizedBox(width: 8),
              Expanded(child: Text(status)),
            ]),
        ]),
      ),
    ]);
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: violet.withValues(alpha: 0.10),
        border: Border.all(color: violet.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white70, height: 1.4)),
    );
  }
}

// ---------------- On-phone model ----------------

/// First-run screen: pick a Qwen size, download it once, then chat offline.
class ModelSetup extends StatefulWidget {
  const ModelSetup({super.key, required this.onReady});
  final VoidCallback onReady;
  @override
  State<ModelSetup> createState() => _ModelSetupState();
}

class _ModelSetupState extends State<ModelSetup> {
  PhoneModel choice = phoneModels.first;
  int? progress;
  String? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    // Auto-load the model used last time (no download if it is already on the phone).
    LocalAI.savedModelId().then((id) async {
      final m = phoneModels.where((m) => m.id == id).firstOrNull;
      if (m != null && await LocalAI.isDownloaded(m)) {
        setState(() => choice = m);
        start();
      }
    });
  }

  Future<void> start() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
      progress = null;
    });
    try {
      await LocalAI.load(choice,
          hfToken: Api.hfToken, onProgress: (p) => mounted ? setState(() => progress = p) : null);
      widget.onReady();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
      const Text('Нейросеть прямо на телефоне',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text(
          'Модель скачивается один раз, дальше всё работает без интернета и без серверов. Лучше качать по Wi-Fi.',
          style: TextStyle(color: Colors.white60, height: 1.4)),
      const SizedBox(height: 16),
      for (final m in phoneModels)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: loading ? null : () => setState(() => choice = m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: choice == m ? violet.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.05),
                border: Border.all(color: choice == m ? violet : Colors.white12, width: choice == m ? 2 : 1),
              ),
              child: Row(children: [
                Icon(choice == m ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: choice == m ? violet : Colors.white38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(m.note, style: const TextStyle(color: Colors.white60, fontSize: 13)),
                  ]),
                ),
                Text(m.size, style: const TextStyle(color: Colors.white70)),
              ]),
            ),
          ),
        ),
      const SizedBox(height: 8),
      if (loading) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            minHeight: 10,
            value: progress == null || progress! >= 100 ? null : progress! / 100,
            color: violet,
            backgroundColor: Colors.white10,
          ),
        ),
        const SizedBox(height: 8),
        Text(progress == null || progress! >= 100 ? 'Загружаю модель в память…' : 'Скачивание: $progress%',
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
      ] else
        GradientButton(icon: Icons.download_rounded, label: 'Скачать и запустить', onTap: start),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('Ошибка: $error', style: const TextStyle(color: Colors.redAccent)),
        ),
    ]);
  }
}

/// Settings card: which models are on the phone, with delete buttons to free space.
class PhoneModelsCard extends StatefulWidget {
  const PhoneModelsCard({super.key});
  @override
  State<PhoneModelsCard> createState() => _PhoneModelsCardState();
}

class _PhoneModelsCardState extends State<PhoneModelsCard> {
  Map<String, bool> downloaded = {};

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final d = <String, bool>{};
    for (final m in phoneModels) {
      try {
        d[m.id] = await LocalAI.isDownloaded(m);
      } catch (_) {
        d[m.id] = false;
      }
    }
    if (mounted) setState(() => downloaded = d);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(LocalAI.active == null ? 'Модель не запущена' : 'Работает: ${LocalAI.active!.title}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        for (final m in phoneModels)
          if (downloaded[m.id] == true)
            Row(children: [
              const Icon(Icons.memory, size: 18, color: violet),
              const SizedBox(width: 8),
              Expanded(child: Text('${m.title} · ${m.size}')),
              IconButton(
                tooltip: 'Удалить с телефона',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await LocalAI.delete(m);
                  refresh();
                },
              ),
            ]),
        if (!downloaded.containsValue(true))
          const Text('Скачанных моделей нет. Открой вкладку «Чат», чтобы скачать.',
              style: TextStyle(color: Colors.white60)),
      ]),
    );
  }
}
