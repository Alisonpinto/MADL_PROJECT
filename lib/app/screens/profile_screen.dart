import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_announcer.dart';
import '../services/auslan_network_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.onOpenScan,
  });

  final VoidCallback onOpenScan;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuslanNetworkService _networkService = AuslanNetworkService();
  bool _isCheckingServer = false;
  bool _isServerHealthy = false;
  String? _serverUrl;
  bool _autoSpeak = true;
  double _speechRate = 0.5;

  // Auth / Profile State
  bool _isLoggedIn = true;
  bool _isSignUpMode = false;
  bool _obscurePassword = true;

  String _userName = 'Alex Turner';
  String _userEmail = 'alex.turner@example.com';
  String _preferredDialect = 'Auslan (Australian Sign)';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  static const String _prefKeyLoggedIn = 'ht_user_logged_in';
  static const String _prefKeyName = 'ht_user_name';
  static const String _prefKeyEmail = 'ht_user_email';
  static const String _prefKeyDialect = 'ht_user_dialect';

  @override
  void initState() {
    super.initState();
    unawaited(_loadUserProfile());
    unawaited(_checkServer());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = prefs.getBool(_prefKeyLoggedIn) ?? true;
      _userName = prefs.getString(_prefKeyName) ?? 'Alex Turner';
      _userEmail = prefs.getString(_prefKeyEmail) ?? 'alex.turner@example.com';
      _preferredDialect =
          prefs.getString(_prefKeyDialect) ?? 'Auslan (Australian Sign)';
    });
  }

  Future<void> _saveUserProfile({
    required String name,
    required String email,
    required String dialect,
    required bool isLoggedIn,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyLoggedIn, isLoggedIn);
    await prefs.setString(_prefKeyName, name);
    await prefs.setString(_prefKeyEmail, email);
    await prefs.setString(_prefKeyDialect, dialect);

    if (!mounted) return;
    setState(() {
      _userName = name;
      _userEmail = email;
      _preferredDialect = dialect;
      _isLoggedIn = isLoggedIn;
    });
  }

  Future<void> _checkServer() async {
    if (_isCheckingServer) return;
    setState(() => _isCheckingServer = true);

    try {
      final health = await _networkService.checkServerHealth();
      if (!mounted) return;
      setState(() {
        _isServerHealthy = health.isReachable;
        _serverUrl = health.url;
        _isCheckingServer = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isServerHealthy = false;
        _isCheckingServer = false;
      });
    }
  }

  void _handleAuthSubmit() {
    final email = _emailController.text.trim();
    final name = _isSignUpMode ? _nameController.text.trim() : _userName;

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an email address')),
      );
      return;
    }

    if (_isSignUpMode && name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your full name')),
      );
      return;
    }

    _saveUserProfile(
      name: name.isNotEmpty ? name : 'Alex Turner',
      email: email,
      dialect: _preferredDialect,
      isLoggedIn: true,
    );

    _emailController.clear();
    _passwordController.clear();
    _nameController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isSignUpMode ? 'Account created successfully!' : 'Signed in as $name'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _handleLogOut() {
    _saveUserProfile(
      name: _userName,
      email: _userEmail,
      dialect: _preferredDialect,
      isLoggedIn: false,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Signed out'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showEditProfileSheet() {
    final nameEdit = TextEditingController(text: _userName);
    final emailEdit = TextEditingController(text: _userEmail);
    String selectedDialect = _preferredDialect;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomPadding = MediaQuery.of(ctx).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Edit Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextInput(
                    controller: nameEdit,
                    label: 'Full Name',
                    icon: Icons.person_outline_rounded,
                  ),
                  const SizedBox(height: 12),
                  _buildTextInput(
                    controller: emailEdit,
                    label: 'Email Address',
                    icon: Icons.email_outlined,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Preferred Dialect',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedDialect,
                        dropdownColor: const Color(0xFF1E293B),
                        isExpanded: true,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        items: const [
                          DropdownMenuItem(
                            value: 'Auslan (Australian Sign)',
                            child: Text('Auslan (Australian Sign)'),
                          ),
                          DropdownMenuItem(
                            value: 'ASL (American Sign)',
                            child: Text('ASL (American Sign)'),
                          ),
                          DropdownMenuItem(
                            value: 'BSL (British Sign)',
                            child: Text('BSL (British Sign)'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => selectedDialect = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      final n = nameEdit.text.trim();
                      final e = emailEdit.text.trim();
                      if (n.isNotEmpty && e.isNotEmpty) {
                        _saveUserProfile(
                          name: n,
                          email: e,
                          dialect: selectedDialect,
                          isLoggedIn: true,
                        );
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Profile updated successfully')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Save Profile', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _testSpeech() {
    AppAnnouncer.instance.speak('Testing speech output.');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Playing voice sample...'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final openAiKeyPresent = dotenv.isInitialized &&
        (dotenv.maybeGet('OPENAI_API_KEY')?.isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Profile & Settings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          physics: const BouncingScrollPhysics(),
          children: [
            _buildSectionHeader('User Account'),
            const SizedBox(height: 8),
            _isLoggedIn ? _buildUserProfileCard() : _buildAuthCard(),
            const SizedBox(height: 20),
            _buildSectionHeader('Speech & Voice'),
            const SizedBox(height: 8),
            _buildSpeechCard(),
            const SizedBox(height: 20),
            _buildSectionHeader('Inference Engine'),
            const SizedBox(height: 8),
            _buildEngineCard(openAiKeyPresent),
            const SizedBox(height: 20),
            _buildSectionHeader('About HandTalk'),
            const SizedBox(height: 8),
            _buildAboutCard(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  // -------------------------------------------------------------
  // Logged-In User Profile Card
  // -------------------------------------------------------------
  Widget _buildUserProfileCard() {
    final initials = _userName.isNotEmpty
        ? _userName
            .split(' ')
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w[0].toUpperCase())
            .join()
        : 'U';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Color(0xFF2563EB),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _userEmail,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _preferredDialect,
                        style: const TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFF334155)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showEditProfileSheet,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF475569)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit Profile'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _handleLogOut,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF87171),
                  side: const BorderSide(color: Color(0xFF475569)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text('Sign Out'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Auth Form Card (Sign In / Sign Up)
  // -------------------------------------------------------------
  Widget _buildAuthCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Segmented Toggle
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isSignUpMode = false),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: !_isSignUpMode ? const Color(0xFF2563EB) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Sign In',
                        style: TextStyle(
                          color: !_isSignUpMode ? Colors.white : const Color(0xFF94A3B8),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isSignUpMode = true),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _isSignUpMode ? const Color(0xFF2563EB) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Create Account',
                        style: TextStyle(
                          color: _isSignUpMode ? Colors.white : const Color(0xFF94A3B8),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Fields
          if (_isSignUpMode) ...[
            _buildTextInput(
              controller: _nameController,
              label: 'Full Name',
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: 10),
          ],
          _buildTextInput(
            controller: _emailController,
            label: 'Email Address',
            icon: Icons.email_outlined,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Password',
              labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF94A3B8), size: 18),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: const Color(0xFF94A3B8),
                  size: 18,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF2563EB)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Submit Button
          ElevatedButton(
            onPressed: _handleAuthSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              _isSignUpMode ? 'Register & Set Profile' : 'Sign In',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          const SizedBox(height: 8),

          // Guest / Demo shortcut
          TextButton(
            onPressed: () {
              _saveUserProfile(
                name: 'Guest User',
                email: 'guest@sensebridge.local',
                dialect: _preferredDialect,
                isLoggedIn: true,
              );
            },
            child: const Text(
              'Continue as Guest',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildTextInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        prefixIcon: Icon(icon, color: const Color(0xFF94A3B8), size: 18),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2563EB)),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Speech & Voice Settings
  // -------------------------------------------------------------
  Widget _buildSpeechCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Auto-Speak Translations',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              Switch.adaptive(
                value: _autoSpeak,
                activeTrackColor: const Color(0xFF2563EB),
                onChanged: (val) => setState(() => _autoSpeak = val),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Speed', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
              Expanded(
                child: Slider(
                  value: _speechRate,
                  min: 0.2,
                  max: 1.0,
                  activeColor: const Color(0xFF2563EB),
                  inactiveColor: const Color(0xFF0F172A),
                  onChanged: (val) => setState(() => _speechRate = val),
                ),
              ),
              Text(
                '${(_speechRate * 2).toStringAsFixed(1)}x',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _testSpeech,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Test Voice Output'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF38BDF8),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Inference Engine Card
  // -------------------------------------------------------------
  Widget _buildEngineCard(bool openAiConfigured) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: const Text('Local TFLite Model', style: TextStyle(color: Colors.white, fontSize: 13.5)),
            subtitle: const Text('auslan.tflite', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
            trailing: const Text('Ready', style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1, color: Color(0xFF334155)),
          ListTile(
            dense: true,
            title: const Text('Inference Server', style: TextStyle(color: Colors.white, fontSize: 13.5)),
            subtitle: Text(
              _serverUrl != null && _isServerHealthy ? _serverUrl! : 'Checking / Local mode',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
            ),
            trailing: IconButton(
              icon: _isCheckingServer
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, color: Colors.white70, size: 18),
              onPressed: _checkServer,
            ),
          ),
          const Divider(height: 1, color: Color(0xFF334155)),
          ListTile(
            dense: true,
            title: const Text('Word Guessing (OpenAI)', style: TextStyle(color: Colors.white, fontSize: 13.5)),
            subtitle: Text(
              openAiConfigured ? 'Enabled' : 'Optional (set in .env)',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
            ),
            trailing: Text(
              openAiConfigured ? 'Active' : 'Off',
              style: TextStyle(
                color: openAiConfigured ? const Color(0xFF10B981) : const Color(0xFF64748B),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'HandTalk (SenseBridge)',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 4),
          Text(
            'Version 1.0.0 • Real-time Auslan sign language recognition and speech synthesizer.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.35),
          ),
        ],
      ),
    );
  }
}
