import 'package:flutter/material.dart';
import 'services/ble_service.dart';

enum EspStatus { connected, connecting, disconnected }

class EspStatusBadge extends StatefulWidget {
  final EspStatus status;
  const EspStatusBadge({super.key, required this.status});

  @override
  State<EspStatusBadge> createState() => _EspStatusBadgeState();
}

class _EspStatusBadgeState extends State<EspStatusBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _config(widget.status);
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: cfg.color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cfg.color.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cfg.color.withOpacity(
                  widget.status == EspStatus.connecting ? _anim.value : 1.0,
                ),
                boxShadow: [BoxShadow(
                  color: cfg.color.withOpacity(0.4),
                  blurRadius: 4, spreadRadius: 1,
                )],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              cfg.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cfg.color,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  _StatusConfig _config(EspStatus s) {
    switch (s) {
      case EspStatus.connected:
        return _StatusConfig(const Color(0xFF00C897), 'Online');
      case EspStatus.connecting:
        return _StatusConfig(const Color(0xFFFFB020), 'Connecting...');
      case EspStatus.disconnected:
        return _StatusConfig(const Color(0xFFFF4E6A), 'Offline');
    }
  }
}

class _StatusConfig {
  final Color color;
  final String label;
  _StatusConfig(this.color, this.label);
}

// ── Helper: compute EspStatus from BleService singleton ───────────────────
EspStatus bleToEspStatus(BleService ble) {
  if (ble.isConnected) return EspStatus.connected;
  if (ble.isScanning) return EspStatus.connecting;
  return EspStatus.disconnected;
}