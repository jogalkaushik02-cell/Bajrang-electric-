import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

const _apiKey = String.fromEnvironment('GEMINI_API_KEY');
const _model = String.fromEnvironment(
  'GEMINI_MODEL',
  defaultValue: 'gemini-2.5-flash',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FoodDatabase.instance.database;
  runApp(const NutritionApp());
}

class NutritionApp extends StatelessWidget {
  const NutritionApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00BFA5),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Nutrition Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF101514),
        cardTheme: const CardThemeData(
          color: Color(0xFF1A2220),
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
      ),
      home: const TrackerHome(),
    );
  }
}

class NutritionSource {
  final String title;
  final String url;
  const NutritionSource({required this.title, required this.url});
}

class FoodLog {
  final int? id;
  final String name;
  final String category;
  final String mealType;
  final double grams;
  final double kcal100;
  final double protein100;
  final double carbs100;
  final double fat100;
  final double fiber100;
  final double sugar100;
  final double sodium100;
  final String confidence;
  final String note;
  final String createdAt;
  final List<NutritionSource> sources;

  const FoodLog({
    this.id,
    required this.name,
    required this.category,
    this.mealType = 'Other',
    required this.grams,
    required this.kcal100,
    required this.protein100,
    required this.carbs100,
    required this.fat100,
    required this.fiber100,
    required this.sugar100,
    required this.sodium100,
    required this.confidence,
    required this.note,
    required this.createdAt,
    required this.sources,
  });

  double get factor => grams / 100;
  double get kcal => kcal100 * factor;
  double get protein => protein100 * factor;
  double get carbs => carbs100 * factor;
  double get fat => fat100 * factor;
  double get fiber => fiber100 * factor;
  double get sugar => sugar100 * factor;
  double get sodium => sodium100 * factor;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'mealType': mealType,
        'grams': grams,
        'kcal100': kcal100,
        'protein100': protein100,
        'carbs100': carbs100,
        'fat100': fat100,
        'fiber100': fiber100,
        'sugar100': sugar100,
        'sodium100': sodium100,
        'confidence': confidence,
        'note': note,
        'createdAt': createdAt,
        'sourcesJson': jsonEncode(sources.map((s) => {
              'title': s.title,
              'url': s.url,
            }).toList()),
      };

  factory FoodLog.fromMap(Map<String, Object?> m) {
    final rawSources = jsonDecode((m['sourcesJson'] as String?) ?? '[]')
        as List<dynamic>;
    return FoodLog(
      id: m['id'] as int?,
      name: m['name'] as String,
      category: m['category'] as String,
      mealType: (m['mealType'] as String?) ?? 'Other',
      grams: (m['grams'] as num).toDouble(),
      kcal100: (m['kcal100'] as num).toDouble(),
      protein100: (m['protein100'] as num).toDouble(),
      carbs100: (m['carbs100'] as num).toDouble(),
      fat100: (m['fat100'] as num).toDouble(),
      fiber100: (m['fiber100'] as num).toDouble(),
      sugar100: (m['sugar100'] as num).toDouble(),
      sodium100: (m['sodium100'] as num).toDouble(),
      confidence: m['confidence'] as String,
      note: m['note'] as String,
      createdAt: m['createdAt'] as String,
      sources: rawSources.map((e) {
        final s = e as Map<String, dynamic>;
        return NutritionSource(
          title: (s['title'] as String?) ?? 'Source',
          url: (s['url'] as String?) ?? '',
        );
      }).toList(),
    );
  }
}

class FoodDatabase {
  FoodDatabase._();
  static final instance = FoodDatabase._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final base = await getDatabasesPath();
    _db = await openDatabase(
      p.join(base, 'nutrition_tracker.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE food_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            mealType TEXT NOT NULL DEFAULT 'Other',
            grams REAL NOT NULL,
            kcal100 REAL NOT NULL,
            protein100 REAL NOT NULL,
            carbs100 REAL NOT NULL,
            fat100 REAL NOT NULL,
            fiber100 REAL NOT NULL,
            sugar100 REAL NOT NULL,
            sodium100 REAL NOT NULL,
            confidence TEXT NOT NULL,
            note TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            sourcesJson TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute("ALTER TABLE food_logs ADD COLUMN mealType TEXT NOT NULL DEFAULT 'Other'");
          } catch (_) {}
        }
      },
    );
    return _db!;
  }

  Future<int> add(FoodLog food) async =>
      (await database).insert('food_logs', food.toMap()..remove('id'));

  Future<List<FoodLog>> allForDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day).toIso8601String();
    final end = DateTime(date.year, date.month, date.day + 1).toIso8601String();
    final rows = await (await database).query(
      'food_logs',
      where: 'createdAt >= ? AND createdAt < ?',
      whereArgs: [start, end],
      orderBy: 'createdAt ASC',
    );
    return rows.map(FoodLog.fromMap).toList();
  }

  Future<List<FoodLog>> allForToday() async => allForDate(DateTime.now());

  Future<void> update(FoodLog f) async {
    await (await database).update(
      'food_logs',
      f.toMap()..remove('sourcesJson'),
      where: 'id = ?',
      whereArgs: [f.id],
    );
  }

  Future<void> delete(int id) async =>
      (await database).delete('food_logs', where: 'id = ?', whereArgs: [id]);

  Future<List<Map<String, dynamic>>> getUniqueDates() async {
    final rows = await (await database).rawQuery('''
      SELECT DISTINCT DATE(createdAt) as date
      FROM food_logs
      ORDER BY date DESC
    ''');
    return rows;
  }
}

class AiFoodResult {
  final String summary;
  final List<FoodLog> foods;
  final List<String> warnings;
  const AiFoodResult(this.summary, this.foods, this.warnings);
}

class GeminiNutritionService {
  Future<AiFoodResult> lookup({
    required String query,
    required double grams,
    Uint8List? imageBytes,
    String mimeType = 'image/jpeg',
  }) async {
    if (_apiKey.isEmpty || _apiKey == 'YOUR_GEMINI_API_KEY') {
      throw Exception(
        'Gemini API key missing. Run with --dart-define=GEMINI_API_KEY=YOUR_KEY.',
      );
    }

    final prompt = '''
You are a careful nutrition research assistant. Research the food: "$query".
Requested portion: ${grams.toStringAsFixed(1)} grams.
If an image is attached, identify visible foods separately and estimate grams for each,
but explicitly mark weights as estimates. Search for nutrition evidence when useful.
Source priority:
1. Official manufacturer nutrition label for the exact branded product/variant.
2. Official government or recognized food composition database (e.g. USDA FoodData Central,
   ICMR-NIN resources where applicable).
3. Reputable secondary source.
4. Recipe-based estimate if no reliable match is available.

Do not claim a source supports a value unless it actually does. Do not invent a citation.
Return one JSON object only, with this schema:
{
 "meal_summary":"brief summary",
 "items":[{
  "item_name":"food name",
  "category":"category",
  "estimated_grams":${grams.toStringAsFixed(1)},
  "kcal_per_100g":null,
  "protein_per_100g":null,
  "carbs_per_100g":null,
  "fat_per_100g":null,
  "fiber_per_100g":null,
  "sugar_per_100g":null,
  "sodium_mg_per_100g":null,
  "confidence":"verified|estimated|uncertain",
  "nutrition_note":"explain match, assumptions, and uncertainty",
  "health_warnings":[]
 }]
}
Use null for any nutrient that cannot be responsibly estimated. Values must be numeric or null.
Do not return fabricated source URLs; the app will use grounding metadata for sources.
For a text query, return one item. For a plate image, return one item per distinct food.
''';

    final parts = <Map<String, dynamic>>[];
    if (imageBytes != null) {
      parts.add({
        'inline_data': {
          'mime_type': mimeType,
          'data': base64Encode(imageBytes),
        }
      });
    }
    parts.add({'text': prompt});

    final response = await http
        .post(
          Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent',
          ),
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': _apiKey,
          },
          body: jsonEncode({
            'contents': [
              {'parts': parts}
            ],
            'tools': [
              {'google_search': {}}
            ],
            'generationConfig': {'temperature': 0.1},
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception('Gemini API returned ${response.statusCode}: ${_safeError(response.body)}');
    }

    final root = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = root['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini returned no candidates.');
    }
    final candidate = candidates.first as Map<String, dynamic>;
    final content = candidate['content'] as Map<String, dynamic>?;
    final responseParts = content?['parts'] as List<dynamic>? ?? [];
    final text = responseParts
        .whereType<Map<String, dynamic>>()
        .map((p) => p['text'] as String? ?? '')
        .join()
        .trim();
    final parsed = jsonDecode(_extractJson(text)) as Map<String, dynamic>;

    final metadata =
        candidate['groundingMetadata'] as Map<String, dynamic>? ?? {};
    final chunks = metadata['groundingChunks'] as List<dynamic>? ?? [];
    final sources = <NutritionSource>[];
    final seen = <String>{};
    for (final c in chunks) {
      if (c is! Map<String, dynamic>) continue;
      final web = c['web'] as Map<String, dynamic>?;
      if (web == null) continue;
      final url = web['uri'] as String? ?? '';
      final title = web['title'] as String? ?? url;
      if (url.startsWith('http') && seen.add(url)) {
        sources.add(NutritionSource(title: title, url: url));
      }
    }

    final rawItems = parsed['items'] as List<dynamic>? ?? [];
    if (rawItems.isEmpty) throw Exception('No foods could be identified.');
    final now = DateTime.now().toIso8601String();
    final foods = <FoodLog>[];
    for (final raw in rawItems) {
      if (raw is! Map<String, dynamic>) continue;
      final itemGrams = _number(raw['estimated_grams']) ?? grams;
      foods.add(FoodLog(
        name: (raw['item_name'] as String?)?.trim().isNotEmpty == true
            ? (raw['item_name'] as String).trim()
            : 'Unidentified food',
        category: raw['category'] as String? ?? 'Food',
        grams: itemGrams.clamp(1, 3000).toDouble(),
        kcal100: _number(raw['kcal_per_100g']) ?? 0,
        protein100: _number(raw['protein_per_100g']) ?? 0,
        carbs100: _number(raw['carbs_per_100g']) ?? 0,
        fat100: _number(raw['fat_per_100g']) ?? 0,
        fiber100: _number(raw['fiber_per_100g']) ?? 0,
        sugar100: _number(raw['sugar_per_100g']) ?? 0,
        sodium100: _number(raw['sodium_mg_per_100g']) ?? 0,
        confidence: _confidence(raw['confidence']),
        note: [
          raw['nutrition_note'] as String? ?? '',
          if (_hasMissingNutrients(raw)) 'One or more nutrient values were missing; shown as 0 for calculation. Treat totals as incomplete.',
        ].where((s) => s.isNotEmpty).join(' '),
        createdAt: now,
        sources: sources,
      ));
    }
    final warnings = <String>[];
    for (final raw in rawItems) {
      if (raw is Map<String, dynamic>) {
        final w = raw['health_warnings'];
        if (w is List) warnings.addAll(w.map((e) => e.toString()));
      }
    }
    return AiFoodResult(
      parsed['meal_summary'] as String? ?? 'Nutrition results',
      foods,
      warnings.toSet().toList(),
    );
  }

  static String _safeError(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      return (m['error'] as Map<String, dynamic>?)?['message'] as String? ??
          'Please check API key, model access, and quota.';
    } catch (_) {
      return 'Please check API key, model access, and quota.';
    }
  }

  static String _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('Gemini did not return a JSON object.');
    }
    return text.substring(start, end + 1);
  }

  static double? _number(dynamic v) {
    if (v is num) return v.toDouble();
    return null;
  }

  static bool _hasMissingNutrients(Map<String, dynamic> m) {
    const keys = [
      'kcal_per_100g',
      'protein_per_100g',
      'carbs_per_100g',
      'fat_per_100g',
      'fiber_per_100g',
      'sugar_per_100g',
      'sodium_mg_per_100g',
    ];
    return keys.any((k) => m[k] == null || m[k] is! num);
  }

  static String _confidence(dynamic value) {
    const valid = {'verified', 'estimated', 'uncertain'};
    return valid.contains(value) ? value as String : 'uncertain';
  }
}

class TrackerHome extends StatefulWidget {
  const TrackerHome({super.key});
  @override
  State<TrackerHome> createState() => _TrackerHomeState();
}

class _TrackerHomeState extends State<TrackerHome> {
  final _service = GeminiNutritionService();
  final _picker = ImagePicker();
  final _foodController = TextEditingController();
  final _gramsController = TextEditingController(text: '150');
  String _mealType = 'Breakfast';
  List<FoodLog> _foods = [];
  bool _loading = false;
  String? _summary;
  String? _error;
  List<String> _warnings = [];
  DateTime _selectedDate = DateTime.now();

  static const List<String> _mealTypes = [
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snack',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _foodController.dispose();
    _gramsController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final rows = await FoodDatabase.instance.allForDate(_selectedDate);
    if (mounted) setState(() => _foods = rows);
  }

  double get _kcal => _foods.fold(0, (sum, f) => sum + f.kcal);
  double get _protein => _foods.fold(0, (sum, f) => sum + f.protein);
  double get _carbs => _foods.fold(0, (sum, f) => sum + f.carbs);
  double get _fat => _foods.fold(0, (sum, f) => sum + f.fat);

  Future<void> _lookup({Uint8List? image, String mime = 'image/jpeg'}) async {
    final query = _foodController.text.trim();
    if (image == null && query.isEmpty) {
      setState(() => _error = 'Enter a food name first.');
      return;
    }
    final grams = double.tryParse(_gramsController.text.trim());
    if (grams == null || grams <= 0 || grams > 3000) {
      setState(() => _error = 'Enter a weight between 1 and 3000 grams.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _warnings = [];
    });
    try {
      final result = await _service.lookup(
        query: query.isEmpty ? 'Foods visible in the attached meal plate' : query,
        grams: grams,
        imageBytes: image,
        mimeType: mime,
      );
      for (final food in result.foods) {
        await FoodDatabase.instance.add(FoodLog(
          id: food.id,
          name: food.name,
          category: food.category,
          mealType: _mealType,
          grams: food.grams,
          kcal100: food.kcal100,
          protein100: food.protein100,
          carbs100: food.carbs100,
          fat100: food.fat100,
          fiber100: food.fiber100,
          sugar100: food.sugar100,
          sodium100: food.sodium100,
          confidence: food.confidence,
          note: food.note,
          createdAt: food.createdAt,
          sources: food.sources,
        ));
      }
      await _reload();
      if (!mounted) return;
      setState(() {
        _summary = result.summary;
        _warnings = result.warnings;
        if (image == null) _foodController.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scan(ImageSource source) async {
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 85,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      await _lookup(image: bytes, mime: image.mimeType ?? 'image/jpeg');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not read image: $e');
    }
  }

  Future<void> _editGrams(FoodLog food) async {
    final gramsController = TextEditingController(text: food.grams.toStringAsFixed(0));
    String selectedMeal = food.mealType;
    final value = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('Edit ${food.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: gramsController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Weight in grams'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedMeal,
                decoration: const InputDecoration(labelText: 'Meal type'),
                items: _mealTypes
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setStateDialog(() => selectedMeal = v ?? 'Other'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final g = double.tryParse(gramsController.text.trim());
                if (g != null && g > 0 && g <= 3000) {
                  Navigator.pop(context, {'grams': g, 'mealType': selectedMeal});
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    gramsController.dispose();
    if (value == null) return;
    await FoodDatabase.instance.update(FoodLog(
      id: food.id,
      name: food.name,
      category: food.category,
      mealType: value['mealType'] ?? food.mealType,
      grams: value['grams'],
      kcal100: food.kcal100,
      protein100: food.protein100,
      carbs100: food.carbs100,
      fat100: food.fat100,
      fiber100: food.fiber100,
      sugar100: food.sugar100,
      sodium100: food.sodium100,
      confidence: food.confidence,
      note: food.note,
      createdAt: food.createdAt,
      sources: food.sources,
    ));
    await _reload();
  }

  Future<void> _delete(FoodLog food) async {
    if (food.id != null) await FoodDatabase.instance.delete(food.id!);
    await _reload();
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Today';
    final yesterday = now.subtract(const Duration(days: 1));
    if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) return 'Yesterday';
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NutriLens AI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              ).then((_) => _reload());
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(_formatDate(_selectedDate)),
              ),
              if (!(_selectedDate.year == DateTime.now().year &&
                  _selectedDate.month == DateTime.now().month &&
                  _selectedDate.day == DateTime.now().day))
                TextButton(
                  onPressed: () {
                    setState(() => _selectedDate = DateTime.now());
                    _reload();
                  },
                  child: const Text('Go to Today'),
                ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [Color(0xFF124F47), Color(0xFF1B2D29)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatDate(_selectedDate).toUpperCase(), style: const TextStyle(letterSpacing: 2, color: Colors.white70)),
                const SizedBox(height: 4),
                Text('${_kcal.round()} kcal', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _macro('Protein', _protein, 'g'),
                    _macro('Carbs', _carbs, 'g'),
                    _macro('Fat', _fat, 'g'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Log food', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('Search or scan and tag as breakfast/lunch/dinner/snack.'),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _mealType,
                    decoration: const InputDecoration(
                      labelText: 'Meal type',
                      prefixIcon: Icon(Icons.restaurant_menu),
                      border: OutlineInputBorder(),
                    ),
                    items: _mealTypes
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setState(() => _mealType = v ?? 'Breakfast'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _foodController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _loading ? null : _lookup(),
                    decoration: const InputDecoration(
                      labelText: 'Food / brand / dish',
                      hintText: 'e.g. Amul Masti Dahi',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _gramsController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Portion weight (grams)',
                      prefixIcon: Icon(Icons.scale_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : () => _lookup(),
                      icon: const Icon(Icons.travel_explore),
                      label: const Text('Search nutrition online'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : () => _scan(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Scan plate'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : () => _scan(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Choose photo'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Researching nutrition and checking sources…'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            _message(_error!, isError: true),
          ],
          if (_summary != null) ...[
            const SizedBox(height: 12),
            _message(_summary!),
          ],
          for (final warning in _warnings) ...[
            const SizedBox(height: 8),
            _message('⚠ $warning', isError: true),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Meals for ${_formatDate(_selectedDate)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text('${_foods.length} items', style: const TextStyle(color: Colors.white60)),
            ],
          ),
          const SizedBox(height: 10),
          if (_foods.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Text('No meals logged for this day.')),
            ),
          for (final food in _foods) _foodCard(food),
          const SizedBox(height: 24),
          const Text(
            'Nutrition estimates are informational, not medical advice. Photo-based portion sizes and recipes can be uncertain. Verify values against the package label when possible.',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _macro(String title, double value, String unit) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text('${value.toStringAsFixed(1)}$unit', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _message(String message, {bool isError = false}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isError ? Colors.red.withValues(alpha: .12) : const Color(0xFF1A2220),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isError ? Colors.redAccent.withValues(alpha: .5) : Colors.white10),
        ),
        child: Text(message),
      );

  Widget _foodCard(FoodLog food) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: Color(0xFF24433C),
                    child: Icon(
                      food.mealType == 'Breakfast'
                          ? Icons.free_breakfast
                          : food.mealType == 'Lunch'
                              ? Icons.lunch_dining
                              : food.mealType == 'Dinner'
                                  ? Icons.dinner_dining
                                  : food.mealType == 'Snack'
                                      ? Icons.cookie
                                      : Icons.restaurant,
                      color: const Color(0xFF77E3CB),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(food.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text('${food.mealType} • ${food.category} • ${food.grams.toStringAsFixed(0)} g',
                            style: const TextStyle(color: Colors.white60, fontSize: 12)),
                        const SizedBox(height: 4),
                        _confidenceBadge(food.confidence),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${food.kcal.round()} kcal', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _editGrams(food);
                          if (v == 'delete') _delete(food);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit grams')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill('P ${food.protein.toStringAsFixed(1)}g'),
                  _pill('C ${food.carbs.toStringAsFixed(1)}g'),
                  _pill('F ${food.fat.toStringAsFixed(1)}g'),
                  _pill('Fiber ${food.fiber.toStringAsFixed(1)}g'),
                  _pill('Sugar ${food.sugar.toStringAsFixed(1)}g'),
                  _pill('Sodium ${food.sodium.round()}mg'),
                ],
              ),
              if (food.note.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(food.note, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
              if (food.sources.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Web sources', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                for (final source in food.sources.take(5))
                  InkWell(
                    onTap: () async {
                      final uri = Uri.tryParse(source.url);
                      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.open_in_new, size: 14, color: Color(0xFF77E3CB)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              source.title,
                              style: const TextStyle(
                                color: Color(0xFF77E3CB),
                                decoration: TextDecoration.underline,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ] else ...[
                const SizedBox(height: 8),
                const Text('No grounding source was returned for this result.',
                    style: TextStyle(fontSize: 12, color: Colors.orangeAccent)),
              ],
            ],
          ),
        ),
      );

  Widget _confidenceBadge(String value) {
    final color = switch (value) {
      'verified' => Colors.greenAccent,
      'estimated' => Colors.orangeAccent,
      _ => Colors.redAccent,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .7)),
      ),
      child: Text(value.toUpperCase(), style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11)),
      );
}


class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _dates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dates = await FoodDatabase.instance.getUniqueDates();
    if (mounted) {
      setState(() {
        _dates = dates;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _dates.isEmpty
              ? const Center(child: Text('No history yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _dates.length,
                  itemBuilder: (context, i) {
                    final dateStr = _dates[i]['date'] as String;
                    final date = DateTime.parse(dateStr);
                    final now = DateTime.now();
                    String label = '${date.day}/${date.month}/${date.year}';
                    if (date.year == now.year && date.month == now.month && date.day == now.day) label = 'Today';
                    final yesterday = now.subtract(const Duration(days: 1));
                    if (date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day) label = 'Yesterday';
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.calendar_month),
                        title: Text(label),
                        subtitle: Text(dateStr),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HistoryDetailScreen(date: date),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

class HistoryDetailScreen extends StatefulWidget {
  final DateTime date;
  const HistoryDetailScreen({super.key, required this.date});

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  List<FoodLog> _foods = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await FoodDatabase.instance.allForDate(widget.date);
    if (mounted) {
      setState(() {
        _foods = rows;
        _loading = false;
      });
    }
  }

  double get _kcal => _foods.fold(0, (sum, f) => sum + f.kcal);
  double get _protein => _foods.fold(0, (sum, f) => sum + f.protein);
  double get _carbs => _foods.fold(0, (sum, f) => sum + f.carbs);
  double get _fat => _foods.fold(0, (sum, f) => sum + f.fat);

  Future<void> _editGrams(FoodLog food) async {
    final gramsController = TextEditingController(text: food.grams.toStringAsFixed(0));
    String selectedMeal = food.mealType;
    final value = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('Edit ${food.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: gramsController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Weight in grams'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedMeal,
                decoration: const InputDecoration(labelText: 'Meal type'),
                items: const ['Breakfast', 'Lunch', 'Dinner', 'Snack', 'Other']
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setStateDialog(() => selectedMeal = v ?? 'Other'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final g = double.tryParse(gramsController.text.trim());
                if (g != null && g > 0 && g <= 3000) {
                  Navigator.pop(context, {'grams': g, 'mealType': selectedMeal});
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    gramsController.dispose();
    if (value == null) return;
    await FoodDatabase.instance.update(FoodLog(
      id: food.id,
      name: food.name,
      category: food.category,
      mealType: value['mealType'] ?? food.mealType,
      grams: value['grams'],
      kcal100: food.kcal100,
      protein100: food.protein100,
      carbs100: food.carbs100,
      fat100: food.fat100,
      fiber100: food.fiber100,
      sugar100: food.sugar100,
      sodium100: food.sodium100,
      confidence: food.confidence,
      note: food.note,
      createdAt: food.createdAt,
      sources: food.sources,
    ));
    await _load();
  }

  Future<void> _delete(FoodLog food) async {
    if (food.id != null) await FoodDatabase.instance.delete(food.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = '${widget.date.day}/${widget.date.month}/${widget.date.year}';
    return Scaffold(
      appBar: AppBar(
        title: Text(dateStr),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF124F47), Color(0xFF1B2D29)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TOTAL', style: TextStyle(letterSpacing: 2, color: Colors.white70)),
                      const SizedBox(height: 4),
                      Text('${_kcal.round()} kcal', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Protein', style: TextStyle(color: Colors.white70, fontSize: 12)), Text('${_protein.toStringAsFixed(1)}g', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))])),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Carbs', style: TextStyle(color: Colors.white70, fontSize: 12)), Text('${_carbs.toStringAsFixed(1)}g', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))])),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Fat', style: TextStyle(color: Colors.white70, fontSize: 12)), Text('${_fat.toStringAsFixed(1)}g', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))])),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('${_foods.length} items', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (_foods.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: Text('No meals logged.')),
                  ),
                for (final food in _foods)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                backgroundColor: const Color(0xFF24433C),
                                child: Icon(
                                  food.mealType == 'Breakfast'
                                      ? Icons.free_breakfast
                                      : food.mealType == 'Lunch'
                                          ? Icons.lunch_dining
                                          : food.mealType == 'Dinner'
                                              ? Icons.dinner_dining
                                              : food.mealType == 'Snack'
                                                  ? Icons.cookie
                                                  : Icons.restaurant,
                                  color: const Color(0xFF77E3CB),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(food.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    Text('${food.mealType} • ${food.category} • ${food.grams.toStringAsFixed(0)} g', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${food.kcal.round()} kcal', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'edit') _editGrams(food);
                                      if (v == 'delete') _delete(food);
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .05), borderRadius: BorderRadius.circular(8)), child: Text('P ${food.protein.toStringAsFixed(1)}g', style: const TextStyle(fontSize: 11))),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .05), borderRadius: BorderRadius.circular(8)), child: Text('C ${food.carbs.toStringAsFixed(1)}g', style: const TextStyle(fontSize: 11))),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .05), borderRadius: BorderRadius.circular(8)), child: Text('F ${food.fat.toStringAsFixed(1)}g', style: const TextStyle(fontSize: 11))),
                            ],
                          ),
                        ],
                      ),
                    ),
              ],
            ),
    );
  }
}
