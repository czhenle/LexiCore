import 'package:flutter/material.dart';

class LexiNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const LexiNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  // Updated to the Sky Blue Theme
  static const Color _buttonBlue = Color(0xFF1E88E5);
  static const Color _navyText   = Color(0xFF003C8F);

  static const List<_NavItem> _items = [
    _NavItem(Icons.home_rounded,           'Home'),
    _NavItem(Icons.calendar_month_rounded, 'Schedule'),
    _NavItem(Icons.grid_view_rounded,      'Modules'),
    _NavItem(Icons.smart_toy_rounded,      'AI Tutor'),
    _NavItem(Icons.person_rounded,         'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: 64,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: _navyText.withValues(alpha: 0.08), // Softer, theme-matching shadow
              blurRadius: 24,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: List.generate(_items.length, (i) {
            final selected = i == selectedIndex;
            
            // Soft blue-grey for unselected icons
            final unselectedColor = _navyText.withValues(alpha: 0.4); 

            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      width:  selected ? 44 : 36,
                      height: selected ? 34 : 30,
                      decoration: BoxDecoration(
                        color: selected
                            ? _buttonBlue
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _items[i].icon,
                        size: 20,
                        color: selected ? Colors.white : unselectedColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _items[i].label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: selected ? _buttonBlue : unselectedColor,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}