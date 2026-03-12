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

// --- College fair & checklist data (new Supabase schema) ---

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

class ChecklistGroup {
  ChecklistGroup({required this.id, required this.collegeFairId, required this.title, required this.sortOrder});
  final String id;
  final String collegeFairId;
  final String title;
  final int sortOrder;
  static ChecklistGroup fromMap(Map<String, dynamic> m) {
    return ChecklistGroup(
      id: m['id'] as String,
      collegeFairId: m['college_fair_id'] as String,
      title: m['title'] as String? ?? '',
      sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChecklistItem {
  ChecklistItem({
    required this.id,
    required this.groupId,
    required this.label,
    required this.itemType,
    required this.sortOrder,
    this.url,
  });
  final String id;
  final String groupId;
  final String label;
  final String itemType; // 'checkbox' | 'text'
  final int sortOrder;
  final String? url;
  bool get isCheckbox => itemType == 'checkbox';
  static ChecklistItem fromMap(Map<String, dynamic> m) {
    return ChecklistItem(
      id: m['id'] as String,
      groupId: m['group_id'] as String,
      label: m['label'] as String? ?? '',
      itemType: m['item_type'] as String? ?? 'checkbox',
      sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
      url: m['url'] as String?,
    );
  }
}

/// Shows college fair dropdown and two-level checklist (groups → items; checkbox or text).
class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  List<CollegeFair> _fairs = [];
  String? _selectedFairId;
  List<ChecklistGroup> _groups = [];
  List<ChecklistItem> _items = [];
  Map<String, bool> _completionMap = {};
  Map<String, String> _textValueMap = {};
  final Set<String> _expandedGroupIds = {};
  bool _loading = true;
  String? _error;

  static const List<Color> _groupBarColors = [
    Color(0xFF1976D2), // blue
    Color(0xFF00897B), // teal
    Color(0xFF5E35B1), // deep purple
    Color(0xFFE65100), // deep orange
    Color(0xFF00695C), // teal dark
  ];

  @override
  void initState() {
    super.initState();
    _loadFairs();
  }

  Future<void> _loadFairs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

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
        if (selected != null) _loadChecklistForFair(selected);
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

  Future<void> _loadChecklistForFair(String collegeFairId) async {
    setState(() {
      _groups = [];
      _items = [];
      _completionMap = {};
      _textValueMap = {};
      _expandedGroupIds.clear();
    });
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    try {
      final groupsRes = await client
          .from('checklist_groups')
          .select()
          .eq('college_fair_id', collegeFairId)
          .order('sort_order');
      final groupsList = List<Map<String, dynamic>>.from(groupsRes as List);
      final groups = groupsList.map(ChecklistGroup.fromMap).toList();
      if (groups.isEmpty) {
        if (mounted) setState(() {});
        return;
      }
      final groupIds = groups.map((g) => g.id).toList();
      final itemsRes = await client
          .from('checklist_items')
          .select()
          .inFilter('group_id', groupIds)
          .order('sort_order');
      final itemsList = List<Map<String, dynamic>>.from(itemsRes as List);
      final items = itemsList.map(ChecklistItem.fromMap).toList();
      final itemIds = items.map((e) => e.id).toList();
      final ucRes = await client
          .from('user_checklist')
          .select('item_id, is_complete, text_value')
          .eq('user_id', user.id)
          .inFilter('item_id', itemIds);
      final completionMap = <String, bool>{};
      final textValueMap = <String, String>{};
      for (final row in ucRes as List) {
        final map = row as Map<String, dynamic>;
        final itemId = map['item_id'] as String?;
        if (itemId == null) continue;
        if (map['is_complete'] != null) completionMap[itemId] = map['is_complete'] == true;
        final tv = map['text_value'] as String?;
        if (tv != null) textValueMap[itemId] = tv;
      }
      if (mounted) {
        setState(() {
          _groups = groups;
          _items = items;
          _completionMap = completionMap;
          _textValueMap = textValueMap;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _updateCheckbox(String itemId, bool isComplete) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _completionMap[itemId] = isComplete);
    await Supabase.instance.client.from('user_checklist').upsert({
      'user_id': user.id,
      'item_id': itemId,
      'is_complete': isComplete,
      'text_value': null,
      'completed_at': isComplete ? DateTime.now().toIso8601String() : null,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,item_id');
  }

  Future<void> _updateTextValue(String itemId, String textValue) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _textValueMap[itemId] = textValue);
    await Supabase.instance.client.from('user_checklist').upsert({
      'user_id': user.id,
      'item_id': itemId,
      'is_complete': null,
      'text_value': textValue.isEmpty ? null : textValue,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,item_id');
  }

  static Future<void> _openUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    final urlWithScheme = trimmed.contains(RegExp(r'^https?://', caseSensitive: false))
        ? trimmed
        : 'https://$trimmed';
    final uri = Uri.tryParse(urlWithScheme);
    if (uri == null || !uri.hasScheme) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _fairs.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _fairs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('College Fair Checklist')),
        body: Center(child: Text('Error: $_error')),
      );
    }
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
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String>(
              value: _selectedFairId,
              decoration: const InputDecoration(
                labelText: 'College fair',
                border: OutlineInputBorder(),
              ),
              items: _fairs
                  .map((f) => DropdownMenuItem<String>(
                        value: f.id,
                        child: Text('${f.name} — ${_formatDate(f.fairDate)}'),
                      ))
                  .toList(),
              onChanged: (id) {
                if (id != null) {
                  setState(() => _selectedFairId = id);
                  _loadChecklistForFair(id);
                }
              },
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
                        'No college fairs yet. Add rows to college_fairs in your Supabase project.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _groups.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No checklist groups for this fair. Add groups and items in Supabase.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: _groups.length,
                        itemBuilder: (context, index) {
                          final group = _groups[index];
                          final groupItems = _items.where((i) => i.groupId == group.id).toList()
                            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
                          final isExpanded = _expandedGroupIds.contains(group.id);
                          final barColor = _groupBarColors[index % _groupBarColors.length];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      if (isExpanded) {
                                        _expandedGroupIds.remove(group.id);
                                      } else {
                                        _expandedGroupIds.add(group.id);
                                      }
                                    });
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: barColor.withOpacity(0.15),
                                      border: Border.all(color: barColor, width: 3),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            group.title,
                                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: barColor,
                                                ),
                                          ),
                                        ),
                                        Icon(
                                          isExpanded ? Icons.expand_less : Icons.expand_more,
                                          color: barColor,
                                          size: 28,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (isExpanded)
                                ...groupItems.map((item) => _buildItem(context, item)),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, ChecklistItem item) {
    if (item.isCheckbox) {
      final isComplete = _completionMap[item.id] ?? false;
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ListTile(
          leading: Checkbox(
            value: isComplete,
            onChanged: (value) {
              if (value != null) _updateCheckbox(item.id, value);
            },
          ),
          title: item.url != null && item.url!.trim().isNotEmpty
              ? InkWell(
                  onTap: () => _openUrl(item.url!),
                  child: Text(
                    item.label,
                    style: const TextStyle(
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.blue,
                    ),
                  ),
                )
              : Text(item.label),
        ),
      );
    }
    final textValue = _textValueMap[item.id] ?? '';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: _TextItemField(
        itemId: item.id,
        label: item.label,
        initialValue: textValue,
        onSaved: _updateTextValue,
      ),
    );
  }

  static String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

/// Text field checklist item with stable controller.
class _TextItemField extends StatefulWidget {
  const _TextItemField({
    required this.itemId,
    required this.label,
    required this.initialValue,
    required this.onSaved,
  });
  final String itemId;
  final String label;
  final String initialValue;
  final void Function(String itemId, String value) onSaved;

  @override
  State<_TextItemField> createState() => _TextItemFieldState();
}

class _TextItemFieldState extends State<_TextItemField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(_TextItemField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemId != widget.itemId || oldWidget.initialValue != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Enter text...',
              isDense: true,
            ),
            onChanged: (value) => widget.onSaved(widget.itemId, value),
          ),
        ],
      ),
    );
  }
}
