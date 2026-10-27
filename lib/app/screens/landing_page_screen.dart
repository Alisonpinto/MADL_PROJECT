import 'dart:async';

import 'package:flutter/material.dart';
import '../services/auslan_network_service.dart';

class LandingPageScreen extends StatefulWidget {
  const LandingPageScreen({
    super.key,
    required this.onOpenScan,
    this.onOpenResults,
  });

  final VoidCallback onOpenScan;
  final VoidCallback? onOpenResults;

  @override
  State<LandingPageScreen> createState() => _LandingPageScreenState();
}

class _LandingPageScreenState extends State<LandingPageScreen> {
  final AuslanNetworkService _networkService = AuslanNetworkService();
  bool _isServerHealthy = false;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    unawaited(_checkServer());
  }

  Future<void> _checkServer() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);
    try {
      final health = await _networkService.checkServerHealth();
      if (!mounted) return;
      setState(() {
        _isServerHealthy = health.isReachable;
        _isChecking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isServerHealthy = false;
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.sign_language_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'HandTalk',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          // Subtle server indicator
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isServerHealthy
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isServerHealthy ? 'Online' : 'Local',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeroCard(),
              const SizedBox(height: 24),
              _buildSectionTitle('How It Works'),
              const SizedBox(height: 12),
              _buildHowItWorksSteps(),
              const SizedBox(height: 24),
              _buildSectionTitle('Tips for Best Results'),
              const SizedBox(height: 12),
              _buildSimpleTipsCard(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Auslan Sign to Speech',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Translate fingerspelled hand signs into text and spoken voice in real time using your camera.',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: widget.onOpenScan,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.camera_alt_rounded, size: 20),
              label: const Text(
                'Open Camera',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksSteps() {
    final steps = [
      {
        'step': '1',
        'title': 'Show Sign',
        'desc': 'Hold your hand steadily in front of the camera.',
        'icon': Icons.pan_tool_rounded,
      },
      {
        'step': '2',
        'title': 'Recognize',
        'desc': 'The AI model detects letters (A-Z) in real time.',
        'icon': Icons.center_focus_strong_rounded,
      },
      {
        'step': '3',
        'title': 'Speak',
        'desc': 'Signs are turned into words and read out loud.',
        'icon': Icons.volume_up_rounded,
      },
    ];

    return Column(
      children: steps.map((s) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  s['icon'] as IconData,
                  color: const Color(0xFF38BDF8),
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s['title'] as String,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s['desc'] as String,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSimpleTipsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: const [
          _TipItem(text: 'Make sure your hand has good lighting.'),
          SizedBox(height: 10),
          _TipItem(text: 'Keep your hand centered within the camera frame.'),
          SizedBox(height: 10),
          _TipItem(text: 'Pause briefly between letters for smooth recognition.'),
        ],
      ),
    );
  }
}

class _TipItem extends StatelessWidget {
  const _TipItem({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.check_circle_outline_rounded,
              color: Color(0xFF10B981), size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
