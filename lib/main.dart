import 'dart:async';

import 'package:flutter/material.dart';
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
      title: 'College Fair Checklist',
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
        final msg = e.message ?? 'Failed to send code';
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
    } catch (e, st) {
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

// --- Data models (fair → colleges → user_college_data) ---

class CollegeFair {
  CollegeFair({required this.id, required this.name, required this.fairDate});
  final String id;
  final String name;
  final DateTime fairDate;
  static CollegeFair fromMap(Map<String, dynamic> m) {
    final d = m['fair_date'];
    return CollegeFair(
      id: m['id'] as String,
      name: m['name'] as String? ?? '',
      fairDate: d is String ? DateTime.tryParse(d) ?? DateTime.now() : DateTime.now(),
    );
  }
}

class College {
  College({
    required this.id,
    required this.collegeFairId,
    required this.name,
    this.website,
    this.description,
    this.contactName,
    this.email,
    this.sortOrder = 0,
  });
  final String id;
  final String collegeFairId;
  final String name;
  final String? website;
  final String? description;
  final String? contactName;
  final String? email;
  final int sortOrder;
  static College fromMap(Map<String, dynamic> m) {
    return College(
      id: m['id'] as String,
      collegeFairId: m['college_fair_id'] as String,
      name: m['name'] as String? ?? '',
      website: m['website'] as String?,
      description: m['description'] as String?,
      contactName: m['contact_name'] as String?,
      email: m['email'] as String?,
      sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class UserCollegeData {
  UserCollegeData({
    required this.collegeId,
    this.gpa,
    this.sat,
    this.act,
    this.apScoresAccepted,
    this.majors,
    this.housing,
    this.scholarships,
  });
  final String collegeId;
  final String? gpa;
  final String? sat;
  final String? act;
  final String? apScoresAccepted;
  final String? majors;
  final String? housing;
  final String? scholarships;
  static UserCollegeData fromMap(Map<String, dynamic> m) {
    return UserCollegeData(
      collegeId: m['college_id'] as String,
      gpa: m['gpa'] as String?,
      sat: m['sat'] as String?,
      act: m['act'] as String?,
      apScoresAccepted: m['ap_scores_accepted'] as String?,
      majors: m['majors'] as String?,
      housing: m['housing'] as String?,
      scholarships: m['scholarships'] as String?,
    );
  }
}

/// Main screen: fair dropdown, then open search box for colleges; when selected, fields appear below.
class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  List<CollegeFair> _fairs = [];
  String? _selectedFairId;
  List<College> _colleges = [];
  College? _selectedCollege;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  UserCollegeData? _collegeData;
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

  List<College> get _filteredColleges {
    if (_searchQuery.isEmpty) return _colleges;
    return _colleges.where((c) => c.name.toLowerCase().contains(_searchQuery)).toList();
  }

  Future<void> _loadFairs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return;
    try {
      final res = await client.from('college_fairs').select().order('fair_date', ascending: false);
      final list = List<Map<String, dynamic>>.from(res as List);
      final fairs = list.map(CollegeFair.fromMap).toList();
      String? selected = _selectedFairId;
      if (selected == null && fairs.isNotEmpty) selected = fairs.first.id;
      if (mounted) {
        setState(() {
          _fairs = fairs;
          _selectedFairId = selected;
          _loading = false;
        });
        if (selected != null) _loadCollegesForFair(selected);
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

  Future<void> _loadCollegesForFair(String collegeFairId) async {
    final client = Supabase.instance.client;
    try {
      final res = await client
          .from('colleges')
          .select()
          .eq('college_fair_id', collegeFairId)
          .order('sort_order');
      final list = List<Map<String, dynamic>>.from(res as List);
      final colleges = list.map(College.fromMap).toList();
      if (mounted) {
        setState(() {
          _colleges = colleges;
          _selectedCollege = null;
          _collegeData = null;
          _searchController.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _selectCollege(College college) async {
    setState(() {
      _selectedCollege = college;
      _searchController.text = college.name;
      _searchQuery = college.name.toLowerCase();
    });
    await _loadCollegeData();
  }

  void _clearCollege() {
    setState(() {
      _selectedCollege = null;
      _collegeData = null;
      _searchController.clear();
      _searchQuery = '';
    });
  }

  Future<void> _loadCollegeData() async {
    final college = _selectedCollege;
    if (college == null) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _dataLoading = true);
    try {
      final res = await Supabase.instance.client
          .from('user_college_data')
          .select()
          .eq('user_id', user.id)
          .eq('college_id', college.id)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _collegeData = res == null ? UserCollegeData(collegeId: college.id) : UserCollegeData.fromMap(res as Map<String, dynamic>);
          _dataLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _dataLoading = false;
      });
    }
  }

  Future<void> _saveField(String field, String? value) async {
    final user = Supabase.instance.client.auth.currentUser;
    final college = _selectedCollege;
    if (user == null || college == null) return;
    final payload = <String, dynamic>{
      'user_id': user.id,
      'college_id': college.id,
      'updated_at': DateTime.now().toIso8601String(),
    };
    payload[field] = value?.trim().isEmpty ?? true ? null : value?.trim();
    if (_collegeData != null) {
      payload['gpa'] = payload['gpa'] ?? _collegeData!.gpa;
      payload['sat'] = payload['sat'] ?? _collegeData!.sat;
      payload['act'] = payload['act'] ?? _collegeData!.act;
      payload['ap_scores_accepted'] = payload['ap_scores_accepted'] ?? _collegeData!.apScoresAccepted;
      payload['majors'] = payload['majors'] ?? _collegeData!.majors;
      payload['housing'] = payload['housing'] ?? _collegeData!.housing;
      payload['scholarships'] = payload['scholarships'] ?? _collegeData!.scholarships;
    }
    await Supabase.instance.client.from('user_college_data').upsert(payload, onConflict: 'user_id,college_id');
    if (mounted) _loadCollegeData();
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

  @override
  Widget build(BuildContext context) {
    if (_loading && _fairs.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null && _fairs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('College Fair Checklist')),
        body: Center(child: Text('Error: $_error')),
      );
    }
    final c = _selectedCollege;
    final d = _collegeData;

    return Scaffold(
      appBar: AppBar(
        title: const Text('College Fair Checklist'),
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
              value: _selectedFairId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'College fair',
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
                  _loadCollegesForFair(id);
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search colleges...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: c != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearCollege,
                        tooltip: 'Change college',
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
                        'No college fairs yet. Add college_fairs and colleges in Supabase.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _colleges.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No colleges for this fair. Add colleges in Supabase.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : c == null
                        ? ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _filteredColleges.length,
                            itemBuilder: (context, index) {
                              final college = _filteredColleges[index];
                              return ListTile(
                                title: Text(college.name),
                                onTap: () => _selectCollege(college),
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
                                    // Read-only: website, description, contact, email
                                    if (c.website != null && c.website!.trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: InkWell(
                                          onTap: () => _openUrl(c.website!),
                                          child: Text('Website: ${c.website}', style: const TextStyle(decoration: TextDecoration.underline, color: Colors.blue)),
                                        ),
                                      ),
                                    if (c.description != null && c.description!.trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: Text(c.description!, style: Theme.of(context).textTheme.bodyMedium),
                                      ),
                                    if (c.contactName != null && c.contactName!.trim().isNotEmpty)
                                      Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('Contact: ${c.contactName!}', style: Theme.of(context).textTheme.bodyMedium)),
                                    if (c.email != null && c.email!.trim().isNotEmpty)
                                      Padding(padding: const EdgeInsets.only(bottom: 16), child: Text('Email: ${c.email!}', style: Theme.of(context).textTheme.bodyMedium)),
                                    const Divider(),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                                      child: Text('Academic Requirements', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                    ),
                                    _EditableField(label: 'GPA', value: d?.gpa ?? '', onSave: (v) => _saveField('gpa', v)),
                                    _EditableField(label: 'SAT', value: d?.sat ?? '', onSave: (v) => _saveField('sat', v)),
                                    _EditableField(label: 'ACT', value: d?.act ?? '', onSave: (v) => _saveField('act', v)),
                                    _EditableField(label: 'AP scores accepted', value: d?.apScoresAccepted ?? '', onSave: (v) => _saveField('ap_scores_accepted', v)),
                                    const Divider(),
                                    _EditableField(label: 'Majors', value: d?.majors ?? '', onSave: (v) => _saveField('majors', v)),
                                    _EditableField(label: 'Housing', value: d?.housing ?? '', onSave: (v) => _saveField('housing', v)),
                                    _EditableField(label: 'Scholarships', value: d?.scholarships ?? '', onSave: (v) => _saveField('scholarships', v)),
                                  ],
                                ),
                              ),
          ),
        ],
      ),
    );
  }
}

class _EditableField extends StatefulWidget {
  const _EditableField({required this.label, required this.value, required this.onSave});
  final String label;
  final String value;
  final void Function(String value) onSave;

  @override
  State<_EditableField> createState() => _EditableFieldState();
}

class _EditableFieldState extends State<_EditableField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_EditableField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            onChanged: (v) => widget.onSave(v),
          ),
        ],
      ),
    );
  }
}
