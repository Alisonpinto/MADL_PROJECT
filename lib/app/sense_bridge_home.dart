import 'package:flutter/material.dart';

import 'screens/landing_page_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/results_screen.dart';
import 'screens/sign_language_screen.dart';

class HandTalkHome extends StatefulWidget {
  const HandTalkHome({super.key});

  @override
  State<HandTalkHome> createState() => _HandTalkHomeState();
}

class _HandTalkHomeState extends State<HandTalkHome> {
  int _currentIndex = 0;

  static const double _footerHeight = 64.0;

  void _onTabSelected(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
  }

  void _openScanTab() {
    _onTabSelected(1);
  }

  void _openResultsTab() {
    _onTabSelected(2);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final totalFooterHeight = _footerHeight + bottomInset;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Active Screen Viewport
          Positioned.fill(
            bottom: _currentIndex == 1 ? 0 : totalFooterHeight,
            child: _buildBody(totalFooterHeight),
          ),

          // Sticky Footer Navigation Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildStickyFooter(bottomInset),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(double totalFooterHeight) {
    switch (_currentIndex) {
      case 0:
        return LandingPageScreen(
          onOpenScan: _openScanTab,
          onOpenResults: _openResultsTab,
        );
      case 1:
        return SignLanguageScreen(
          bottomPadding: totalFooterHeight,
        );
      case 2:
        return ResultsScreen(
          onOpenScan: _openScanTab,
        );
      case 3:
        return ProfileScreen(
          onOpenScan: _openScanTab,
        );
      default:
        return LandingPageScreen(
          onOpenScan: _openScanTab,
          onOpenResults: _openResultsTab,
        );
    }
  }

  Widget _buildStickyFooter(double bottomInset) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(
          top: BorderSide(
            color: Color(0xFF334155),
            width: 1.0,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _footerHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                index: 0,
                label: 'Home',
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
              ),
              _buildScanNavItem(),
              _buildNavItem(
                index: 2,
                label: 'Results',
                icon: Icons.history_rounded,
                activeIcon: Icons.history_rounded,
              ),
              _buildNavItem(
                index: 3,
                label: 'Profile',
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required String label,
    required IconData icon,
    required IconData activeIcon,
  }) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => _onTabSelected(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
              size: 24,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF64748B),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanNavItem() {
    final isSelected = _currentIndex == 1;
    return Expanded(
      child: InkWell(
        onTap: () => _onTabSelected(1),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF1E293B),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFF60A5FA) : const Color(0xFF475569),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.camera_alt_rounded,
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                size: 20,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Scan',
              style: TextStyle(
                color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
