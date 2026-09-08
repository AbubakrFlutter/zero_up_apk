import 'dart:convert';
import 'dart:io';

/// Yangi versiya bor-yo'qligini npm registry dan tekshiradi.
///
/// Nega npm, GitHub emas: zup npm orqali tarqatiladi va o'rnatiladi, ya'ni
/// odamlar aynan o'sha yerdan oladi. `npm publish` qilingan zahoti versiya
/// o'zi yangilanadi — alohida sozlash, boshqa xizmat yoki qo'lda yangilash
/// kerak emas. Shuning uchun bu ma'lumot hech qachon eskirib qolmaydi.
class UpdateChecker {
  UpdateChecker({
    required this.currentVersion,
    this.packageName = 'zero_up_apk',
  });

  final String currentVersion;
  final String packageName;

  /// npm dagi oxirgi versiya. Ulanib bo'lmasa `null`.
  Future<String?> fetchLatestVersion() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);

      final request = await client
          .getUrl(Uri.parse('https://registry.npmjs.org/$packageName/latest'))
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(
            const Duration(seconds: 8),
          );

      if (response.statusCode != 200) return null;

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));

      final data = jsonDecode(body);
      if (data is! Map) return null;

      final version = data['version'];
      return version is String && version.trim().isNotEmpty
          ? version.trim()
          : null;
    } catch (_) {
      // Internet yo'q yoki npm javob bermadi — jim o'tamiz, yig'ish
      // yangilanish tekshiruvi tufayli to'xtab qolmasligi kerak.
      return null;
    } finally {
      client?.close(force: true);
    }
  }
}

/// Semantik solishtirish: [candidate] > [current] bo'lsa `true`.
///
/// Oddiy `!=` bilan solishtirish xato edi: mahalliy versiya yangiroq bo'lsa
/// ham "yangi versiya bor" deb ko'rsatardi.
bool isNewerVersion(String candidate, String current) {
  List<int> parse(String v) {
    final cleaned = v.trim().replaceFirst(RegExp('^v'), '');
    // "1.4.0+2" yoki "1.4.0-beta" — faqat raqamli qismini olamiz.
    final core = cleaned.split(RegExp('[+-]')).first;
    return core
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList();
  }

  final a = parse(candidate);
  final b = parse(current);
  final length = a.length > b.length ? a.length : b.length;

  for (var i = 0; i < length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}
