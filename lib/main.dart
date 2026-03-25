import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Career Fair Checklist',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const AuthGate(),
    );
  }
}

/// Shows either the sign-in screen or the checklist depending on auth state.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final session = snapshot.data?.session;
        if (session == null) {
          return const EmailCodeSignInScreen();
        }
        return const ChecklistScreen();
      },
    );
  }
}

/// Email-only sign-in: enter email → we send a code → they enter code → signed in.
class EmailCodeSignInScreen extends StatefulWidget {
  const EmailCodeSignInScreen({super.key});

  @override
  State<EmailCodeSignInScreen> createState() => _EmailCodeSignInScreenState();
}

const String _savedLoginEmailKey = 'saved_login_email';

class _EmailCodeSignInScreenState extends State<EmailCodeSignInScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String? _pendingEmail;
  bool _codeSent = false;
  DateTime? _resendAvailableAfter;
  Timer? _resendCooldownTimer;
  static const int _resendCooldownSeconds = 90;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  @override
  void dispose() {
    _resendCooldownTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _clearVerificationState() {
    _resendCooldownTimer?.cancel();
    _resendCooldownTimer = null;
    setState(() {
      _pendingEmail = null;
      _codeSent = false;
      _resendAvailableAfter = null;
      _codeController.clear();
      _error = null;
    });
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_savedLoginEmailKey);
    if (saved != null && saved.isNotEmpty && mounted) {
      setState(() => _emailController.text = saved);
    }
  }

  Future<void> _saveEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedLoginEmailKey, email);
  }

  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  Future<void> _sendVerificationCode() async {
    final email = (_pendingEmail ?? _emailController.text.trim()).trim().toLowerCase();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email');
      return;
    }
    if (!_emailRegex.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithOtp(email: email);
      if (mounted) {
        _resendCooldownTimer?.cancel();
        _resendAvailableAfter = DateTime.now().add(const Duration(seconds: _resendCooldownSeconds));
        _resendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          if (DateTime.now().isAfter(_resendAvailableAfter!)) {
            _resendCooldownTimer?.cancel();
            _resendCooldownTimer = null;
            setState(() => _resendAvailableAfter = null);
            return;
          }
          setState(() {});
        });
        setState(() {
          _pendingEmail = email;
          _codeSent = true;
          _isLoading = false;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        final msg = e.message;
        final isRateLimit = msg.toLowerCase().contains('limit') ||
            msg.toLowerCase().contains('rate') ||
            msg.toLowerCase().contains('too many');
        setState(() {
          _error = isRateLimit
              ? 'Email limit reached. Supabase limits how often codes can be sent. Please try again in 30–60 minutes.'
              : msg;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        final isDecodeError = msg.toLowerCase().contains('decode') || msg.contains('decode error');
        setState(() {
          _error = isDecodeError
              ? 'Supabase returned an invalid response. Check that supabase_config.dart has your real Project URL and anon key (no placeholders), and that your project is not paused in the Supabase dashboard.'
              : 'Failed to send code: $msg';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifyCodeAndSignIn() async {
    final email = _pendingEmail;
    final code = _codeController.text.trim();
    if (email == null || code.isEmpty) {
      setState(() => _error = 'Enter the verification code');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.email,
        email: email,
        token: code,
      );
      await _saveEmail(email);
      _clearVerificationState();
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Invalid or expired code. Request a new one.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showCodeStep = _codeSent;

    return Scaffold(
      appBar: AppBar(
        title: Text(showCodeStep ? 'Verify email' : 'Sign in'),
        leading: showCodeStep
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _isLoading ? null : _clearVerificationState,
              )
            : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!showCodeStep) ...[
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _isLoading ? null : _sendVerificationCode,
                child: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send verification code'),
              ),
            ] else ...[
              Text(
                'Enter the verification code we sent to $_pendingEmail',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Emails can take 1–2 minutes. Check spam. Resend is available after the countdown.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'Verification code',
                  hintText: '00000000',
                ),
                keyboardType: TextInputType.number,
                maxLength: 8,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _isLoading ? null : _verifyCodeAndSignIn,
                child: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Verify and sign in'),
              ),
              const SizedBox(height: 16),
              Text(
                "Didn't get the email? Check spam or resend the code.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _isLoading || (_resendAvailableAfter != null && DateTime.now().isBefore(_resendAvailableAfter!))
                    ? null
                    : _sendVerificationCode,
                child: Text(
                  _resendAvailableAfter != null && DateTime.now().isBefore(_resendAvailableAfter!)
                      ? 'Resend code (in ${_resendAvailableAfter!.difference(DateTime.now()).inSeconds}s)'
                      : 'Resend code',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- Data models: fair → programs (typed) → questions; answers per user/program/question ---

class Fair {
  Fair({required this.id, required this.name, required this.fairDate});
  final String id;
  final String name;
  final DateTime fairDate;
  static Fair fromMap(Map<String, dynamic> m) {
    final d = m['fair_date'];
    return Fair(
      id: m['id'] as String,
      name: m['name'] as String? ?? '',
      fairDate: d is String ? DateTime.tryParse(d) ?? DateTime.now() : DateTime.now(),
    );
  }
}

class Program {
  Program({
    required this.id,
    required this.fairId,
    required this.programTypeId,
    required this.name,
    this.programTypeName,
    this.website,
    this.description,
    this.contactName,
    this.email,
    this.sortOrder = 0,
  });
  final String id;
  final String fairId;
  final String programTypeId;
  final String name;
  final String? programTypeName;
  final String? website;
  final String? description;
  final String? contactName;
  final String? email;
  final int sortOrder;

  static Program fromMap(Map<String, dynamic> m) {
    String? typeName;
    final pt = m['program_types'];
    if (pt is Map<String, dynamic>) {
      typeName = pt['name'] as String?;
    }
    return Program(
      id: m['id'] as String,
      fairId: m['fair_id'] as String,
      programTypeId: m['program_type_id'] as String,
      name: m['name'] as String? ?? '',
      programTypeName: typeName,
      website: m['website'] as String?,
      description: m['description'] as String?,
      contactName: m['contact_name'] as String?,
      email: m['email'] as String?,
      sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Matches `questions.type` in Supabase: text | number | boolean
enum QuestionInputType {
  text,
  number,
  boolean,
}

QuestionInputType _questionInputTypeFromDb(String? raw) {
  switch (raw?.toLowerCase()) {
    case 'number':
      return QuestionInputType.number;
    case 'boolean':
      return QuestionInputType.boolean;
    default:
      return QuestionInputType.text;
  }
}

class Question {
  Question({
    required this.id,
    required this.programTypeId,
    required this.label,
    this.sortOrder = 0,
    this.inputType = QuestionInputType.text,
    this.sectionId,
    this.sectionTitle,
    this.sectionGroupOrder = -1,
  });
  final String id;
  final String programTypeId;
  final String label;
  final int sortOrder;
  final QuestionInputType inputType;
  /// Null = no section (no header in the UI).
  final String? sectionId;
  /// From `question_sections.title` when [sectionId] is set.
  final String? sectionTitle;
  /// `question_sections.sort_order`, or `-1` when [sectionId] is null (ungrouped questions sort first).
  final int sectionGroupOrder;

  static Question fromMap(Map<String, dynamic> m) {
    final sectionId = m['section_id'] as String?;
    String? sectionTitle;
    var sectionGroupOrder = -1;
    final sec = m['question_sections'];
    if (sec is Map<String, dynamic>) {
      sectionTitle = sec['title'] as String?;
      sectionGroupOrder = (sec['sort_order'] as num?)?.toInt() ?? 0;
    } else if (sectionId != null) {
      sectionGroupOrder = 999999;
    }
    return Question(
      id: m['id'] as String,
      programTypeId: m['program_type_id'] as String,
      label: m['label'] as String? ?? '',
      sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
      inputType: _questionInputTypeFromDb(m['type'] as String?),
      sectionId: sectionId,
      sectionTitle: sectionTitle,
      sectionGroupOrder: sectionGroupOrder,
    );
  }
}

/// Main screen: fair dropdown, search programs, then dynamic questions for the program type.
class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  List<Fair> _fairs = [];
  String? _selectedFairId;
  List<Program> _programs = [];
  Program? _selectedProgram;
  List<Question> _questions = [];
  Map<String, String> _answers = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _loading = true;
  bool _dataLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFairs();
    _searchController.addListener(() => setState(() => _searchQuery = _searchController.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Program> get _filteredPrograms {
    if (_searchQuery.isEmpty) return _programs;
    return _programs.where((p) {
      final n = p.name.toLowerCase().contains(_searchQuery);
      final t = (p.programTypeName ?? '').toLowerCase().contains(_searchQuery);
      return n || t;
    }).toList();
  }

  Future<void> _loadFairs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return;
    try {
      final res = await client.from('fairs').select().order('fair_date', ascending: false);
      final list = List<Map<String, dynamic>>.from(res as List);
      final fairs = list.map(Fair.fromMap).toList();
      String? selected = _selectedFairId;
      if (selected == null && fairs.isNotEmpty) selected = fairs.first.id;
      if (mounted) {
        setState(() {
          _fairs = fairs;
          _selectedFairId = selected;
          _loading = false;
        });
        if (selected != null) _loadProgramsForFair(selected);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadProgramsForFair(String fairId) async {
    try {
      final res = await Supabase.instance.client
          .from('programs')
          .select('id, fair_id, program_type_id, name, website, description, contact_name, email, sort_order, program_types(name)')
          .eq('fair_id', fairId)
          .order('sort_order');
      final list = List<Map<String, dynamic>>.from(res as List);
      final programs = list.map(Program.fromMap).toList();
      if (mounted) {
        setState(() {
          _programs = programs;
          _selectedProgram = null;
          _questions = [];
          _answers = {};
          _searchController.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _selectProgram(Program program) async {
    setState(() {
      _selectedProgram = program;
      _searchController.text = program.name;
      _searchQuery = program.name.toLowerCase();
    });
    await _loadQuestionsAndAnswersForProgram();
  }

  void _clearProgram() {
    setState(() {
      _selectedProgram = null;
      _questions = [];
      _answers = {};
      _searchController.clear();
      _searchQuery = '';
    });
  }

  Future<void> _loadQuestionsAndAnswersForProgram({bool showLoading = true}) async {
    final program = _selectedProgram;
    if (program == null) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    if (showLoading) {
      setState(() => _dataLoading = true);
    }
    try {
      final qRes = await Supabase.instance.client
          .from('questions')
          .select('id, program_type_id, label, sort_order, type, section_id, question_sections(title, sort_order)')
          .eq('program_type_id', program.programTypeId);
      final qList = List<Map<String, dynamic>>.from(qRes as List);
      final questions = qList.map(Question.fromMap).toList()
        ..sort((a, b) {
          final g = a.sectionGroupOrder.compareTo(b.sectionGroupOrder);
          if (g != 0) return g;
          return a.sortOrder.compareTo(b.sortOrder);
        });

      final aRes = await Supabase.instance.client
          .from('user_program_answers')
          .select('question_id, answer_text')
          .eq('user_id', user.id)
          .eq('program_id', program.id);
      final aList = List<Map<String, dynamic>>.from(aRes as List);
      final answers = <String, String>{};
      for (final row in aList) {
        final qid = row['question_id'] as String?;
        final text = row['answer_text'] as String?;
        if (qid != null) answers[qid] = text ?? '';
      }

      if (mounted) {
        setState(() {
          _questions = questions;
          _answers = answers;
          _dataLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _dataLoading = false;
        });
      }
    }
  }

  Future<void> _saveAnswer(String questionId, String? value) async {
    final user = Supabase.instance.client.auth.currentUser;
    final program = _selectedProgram;
    if (user == null || program == null) return;
    final trimmed = value?.trim();
    final stored = trimmed == null || trimmed.isEmpty ? '' : trimmed;
    // Keep local state in sync immediately so parent rebuilds don't clobber the TextField
    // mid-keystroke (reload-after-save caused iOS "every other character" glitches).
    if (mounted) {
      setState(() => _answers[questionId] = stored);
    }
    final payload = <String, dynamic>{
      'user_id': user.id,
      'program_id': program.id,
      'question_id': questionId,
      'answer_text': trimmed == null || trimmed.isEmpty ? null : trimmed,
      'updated_at': DateTime.now().toIso8601String(),
    };
    try {
      await Supabase.instance.client.from('user_program_answers').upsert(payload, onConflict: 'user_id,program_id,question_id');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  static Future<void> _openUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    final urlWithScheme = trimmed.contains(RegExp(r'^https?://', caseSensitive: false)) ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(urlWithScheme);
    if (uri == null || !uri.hasScheme) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  static String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// One row in the program details block; shows "Not provided" when [value] is null or blank.
  Widget _programDetailRow(
    BuildContext context,
    String label,
    String? value, {
    bool isEmail = false,
    bool isWebsite = false,
  }) {
    final trimmed = value?.trim();
    final has = trimmed != null && trimmed.isNotEmpty;
    final muted = Theme.of(context).hintColor;

    if (isWebsite && has) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 92, child: Text('$label:', style: Theme.of(context).textTheme.bodyMedium)),
            Expanded(
              child: InkWell(
                onTap: () => _openUrl(trimmed),
                child: Text(trimmed, style: const TextStyle(decoration: TextDecoration.underline, color: Colors.blue)),
              ),
            ),
          ],
        ),
      );
    }
    if (isEmail && has) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 92, child: Text('$label:', style: Theme.of(context).textTheme.bodyMedium)),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final uri = Uri.tryParse('mailto:$trimmed');
                  if (uri != null) {
                    try {
                      await launchUrl(uri);
                    } catch (_) {}
                  }
                },
                child: Text(trimmed, style: const TextStyle(decoration: TextDecoration.underline, color: Colors.blue)),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92, child: Text('$label:', style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(
            child: Text(
              has ? trimmed! : 'Not provided',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: has ? null : muted),
            ),
          ),
        ],
      ),
    );
  }

  /// Renders questions in order; emits a header only when entering a block that has a [Question.sectionTitle].
  List<Widget> _questionWidgetsWithSectionHeaders(BuildContext context, Program p) {
    final List<Widget> children = [];
    String? prevSectionId;
    for (final q in _questions) {
      final sid = q.sectionId;
      if (sid != prevSectionId) {
        prevSectionId = sid;
        final title = q.sectionTitle;
        if (title != null && title.trim().isNotEmpty) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(
                title.trim(),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
          );
        }
      }
      children.add(
        _QuestionAnswerField(
          key: ValueKey('${p.id}_${q.id}'),
          question: q,
          value: _answers[q.id] ?? '',
          onSave: (v) => _saveAnswer(q.id, v),
        ),
      );
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _fairs.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null && _fairs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Career Fair Checklist')),
        body: Center(child: Text('Error: $_error')),
      );
    }
    final p = _selectedProgram;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Career Fair Checklist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _selectedFairId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Fair',
                border: OutlineInputBorder(),
              ),
              selectedItemBuilder: (context) => _fairs
                  .map((f) => Text(
                        '${f.name} — ${_formatDate(f.fairDate)}',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ))
                  .toList(),
              items: _fairs
                  .map((f) => DropdownMenuItem<String>(
                        value: f.id,
                        child: Text(
                          '${f.name} — ${_formatDate(f.fairDate)}',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ))
                  .toList(),
              onChanged: (id) {
                if (id != null) {
                  setState(() => _selectedFairId = id);
                  _loadProgramsForFair(id);
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search programs...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: p != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearProgram,
                        tooltip: 'Change program',
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (_error != null && _fairs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _fairs.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No fairs yet. Add rows to fairs and programs in Supabase.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _programs.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No programs for this fair. Add program_types, questions, and programs in Supabase.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : p == null
                        ? ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _filteredPrograms.length,
                            itemBuilder: (context, index) {
                              final program = _filteredPrograms[index];
                              return ListTile(
                                title: Text(program.name),
                                subtitle: program.programTypeName != null && program.programTypeName!.isNotEmpty
                                    ? Text(program.programTypeName!)
                                    : null,
                                onTap: () => _selectProgram(program),
                              );
                            },
                          )
                        : _dataLoading
                            ? const Center(child: CircularProgressIndicator())
                            : SingleChildScrollView(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Program details',
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 8),
                                          _programDetailRow(context, 'Type', p.programTypeName),
                                          _programDetailRow(context, 'Contact', p.contactName),
                                          _programDetailRow(context, 'Email', p.email, isEmail: true),
                                          _programDetailRow(context, 'Website', p.website, isWebsite: true),
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4, bottom: 4),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('Description', style: Theme.of(context).textTheme.labelLarge),
                                                const SizedBox(height: 4),
                                                Text(
                                                  (p.description != null && p.description!.trim().isNotEmpty)
                                                      ? p.description!.trim()
                                                      : 'Not provided',
                                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                        color: (p.description != null && p.description!.trim().isNotEmpty)
                                                            ? null
                                                            : Theme.of(context).hintColor,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Divider(),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                                      child: Text('Questions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                    ),
                                    if (_questions.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 16),
                                        child: Text(
                                          'No questions for this program type yet. Add rows to questions in Supabase.',
                                          style: Theme.of(context).textTheme.bodyMedium,
                                        ),
                                      )
                                    else
                                      ..._questionWidgetsWithSectionHeaders(context, p),
                                  ],
                                ),
                              ),
          ),
        ],
      ),
    );
  }
}

class _QuestionAnswerField extends StatefulWidget {
  const _QuestionAnswerField({super.key, required this.question, required this.value, required this.onSave});
  final Question question;
  final String value;
  final void Function(String value) onSave;

  @override
  State<_QuestionAnswerField> createState() => _QuestionAnswerFieldState();
}

class _QuestionAnswerFieldState extends State<_QuestionAnswerField> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_QuestionAnswerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.question.inputType == QuestionInputType.boolean) return;
    // While typing, ignore parent value sync (avoids race with async saves / rebuilds).
    if (_focusNode.hasFocus) return;
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _normalizeYesNo(String v) {
    final s = v.trim().toLowerCase();
    if (s == 'yes' || s == 'no') return s;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final label = q.label;

    switch (q.inputType) {
      case QuestionInputType.boolean:
        final yn = _normalizeYesNo(widget.value);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment<String>(value: 'no', label: Text('No')),
                  ButtonSegment<String>(value: 'yes', label: Text('Yes')),
                ],
                selected: yn.isEmpty ? <String>{} : {yn},
                onSelectionChanged: (Set<String> next) {
                  final v = next.isEmpty ? '' : next.first;
                  widget.onSave(v);
                },
              ),
            ],
          ),
        );
      case QuestionInputType.number:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
                inputFormatters: [_DecimalTextInputFormatter()],
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                onChanged: (v) => widget.onSave(v),
              ),
            ],
          ),
        );
      case QuestionInputType.text:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                onChanged: (v) => widget.onSave(v),
              ),
            ],
          ),
        );
    }
  }
}

/// Digits and at most one decimal point (e.g. `3`, `12.5`).
class _DecimalTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final t = newValue.text;
    if (t.isEmpty) return newValue;
    if (RegExp(r'^\d*\.?\d*$').hasMatch(t)) return newValue;
    return oldValue;
  }
}
