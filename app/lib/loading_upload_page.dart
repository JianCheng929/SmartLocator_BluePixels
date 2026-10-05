import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tracking_page.dart';
// ── ADD: import BleService ──────────────────────────────────
import 'services/ble_service.dart';
import 'app_background.dart';
import 'esp_status_badge.dart';

class LoadingUploadPage extends StatefulWidget {
  final String itemName;
  final String floorLevel;
  final int    floorIndex;   // ← NEW: integer index 0-4 for firmware
  final File?  photo;

  const LoadingUploadPage({
    super.key,
    required this.itemName,
    required this.floorLevel,
    required this.floorIndex,   // ← NEW
    this.photo,
  });

  @override
  State<LoadingUploadPage> createState() => _LoadingUploadPageState();
}

class _LoadingUploadPageState extends State<LoadingUploadPage> {
  // Single bar: 0.0 → 0.5 (upload), 0.5 → 1.0 (calibration)
  double _totalProgress = 0.0;
  int    _phasePercent  = 0;
  int    _phase         = 0;   // 0 = uploading, 1 = calibrating
  double _textOpacity   = 1.0;
  String _uploadedPhotoUrl = '';
  // ── CHANGED: use streams instead of fixed timer ──────────────────────────
  StreamSubscription? _calibSub;
  StreamSubscription? _ackSub;
  Timer?              _fallbackTimer; // only used if BLE not connected

  final _ble = BleService();
  StreamSubscription? _connSub;
  bool _bleDisconnectedDuringCalib = false;

  @override
  void initState() {
    super.initState();
    _startSequence();
  }

  @override
  void dispose() {
    _calibSub?.cancel();
    _ackSub?.cancel();
    _fallbackTimer?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  Future<void> _startSequence() async {
    // ── PHASE 0: Firebase upload ─────────────────────────────────────────
    await _runUpload();

    // ── Smooth text fade transition ──────────────────────────────────────
    setState(() => _textOpacity = 0.0);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() {
      _phase       = 1;
      _phasePercent = 0;
      _textOpacity = 1.0;
    });

    // ── PHASE 1: Send FLOOR command + listen to calibStream ──────────────
    if (_ble.isConnected) {

  // ✅ Monitor BLE connection — pause/resume progress on hardware switch
  _connSub = _ble.connStream.listen((connected) {
    if (!mounted) return;
    if (!connected) {
      // ── Hardware switch OFF → pause ───────────────────────────────
      _fallbackTimer?.cancel();
      _fallbackTimer = null;
      setState(() => _bleDisconnectedDuringCalib = true);
    } else {
      // ── Hardware switch ON again → restart calibration ────────────
      if (_bleDisconnectedDuringCalib && mounted) {
        setState(() {
          _bleDisconnectedDuringCalib = false;
          _phasePercent  = 0;
          _totalProgress = 0.5;
        });

        _fallbackTimer?.cancel();
        _fallbackTimer = null;

        // Wait for characteristics setup, then resend FLOOR
        Future.delayed(const Duration(milliseconds: 3000), () async {
          if (!mounted || !_ble.isConnected) return;
          await _ble.setFloor(widget.floorIndex);
          debugPrint('[Loading] Re-sent FLOOR after reconnect');
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted && _ble.isConnected) {
            await _ble.setFloor(widget.floorIndex);
            debugPrint('[Loading] Re-sent FLOOR (2nd time)');
          }

          // Restart fallback timer from 0
          int ticks = 0;
          const int maxTicks = 45;
          _fallbackTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
            ticks++;
            if (!mounted) { timer.cancel(); return; }
            if (_bleDisconnectedDuringCalib) return;
            final timerPct = (ticks * 2).clamp(0, 99);
            if (_phasePercent < timerPct) {
              setState(() {
                _phasePercent  = timerPct;
                _totalProgress = 0.5 + (timerPct / 100.0) * 0.5;
              });
            }
            if (ticks >= maxTicks) {
              timer.cancel();
              _onComplete();
            }
          });
        });
      }
    }
  });

  _calibSub = _ble.calibStream.listen((c) {
    if (!mounted) return;
    setState(() {
      _phasePercent  = c.progress;
      _totalProgress = 0.5 + (c.progress / 100.0) * 0.5;
    });
  });

  _ackSub = _ble.ackStream.listen((cmd) {
    if (!mounted) return;
    if (cmd == 'AUTO_CONFIRM' || cmd == 'CONFIRM') {
      _calibSub?.cancel();
      _ackSub?.cancel();
      _fallbackTimer?.cancel();
      setState(() {
        _phasePercent  = 100;
        _totalProgress = 1.0;
      });
      _onComplete();
    }
  });

  // Small delay then send FLOOR command
  await Future.delayed(const Duration(milliseconds: 300));
  await _ble.setFloor(widget.floorIndex);

  // ── Fallback timer runs alongside stream ─────────────────────────
  // If ESP32 stream is slow, timer shows minimum progress
  // Stream data always takes priority over timer
  int ticks = 0;
  const int maxTicks = 45; // 45 × 2s = 90 seconds max
  _fallbackTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
    ticks++;
    if (!mounted) { timer.cancel(); return; }
    if (_bleDisconnectedDuringCalib) return; // ✅ 断开时不增加 percent
    final timerPct = (ticks * 2).clamp(0, 99);
    // Only use timer progress if stream hasn't given higher value
    if (_phasePercent < timerPct) {
      setState(() {
        _phasePercent  = timerPct;
        _totalProgress = 0.5 + (timerPct / 100.0) * 0.5;
      });
    }
    if (ticks >= maxTicks) {
      timer.cancel();
      _onComplete();
    }
  });
    }
  }

  Future<void> _runUpload() async {
    final uid       = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    String photoUrl = '';

    try {
      if (widget.photo != null) {
        // ── No Firebase Storage (free Spark plan) — local file path ─────
        // Smooth animated progress 0 → 99% over ~2 seconds
        for (int i = 1; i <= 99; i++) {
          await Future.delayed(const Duration(milliseconds: 20));
          if (!mounted) return;
          setState(() {
            _phasePercent  = i;
            _totalProgress = i / 100 * 0.45;
          });
        }
        // Store local Android file path — valid for this session
        photoUrl = widget.photo!.path;
        _uploadedPhotoUrl = photoUrl;
        // Cache in BleService so MainPage → tracking page always has it
        _ble.cacheItemPhoto(photoUrl, widget.itemName);

      } else {
        // No photo — animate to 99% same as photo branch
        for (int i = 1; i <= 99; i++) {
          await Future.delayed(const Duration(milliseconds: 20));
          if (!mounted) return;
          setState(() {
            _totalProgress = i / 100 * 0.45;
            _phasePercent  = i;
          });
        }
        _ble.cacheItemPhoto('', widget.itemName);
      }

      // Write to Realtime Database
      // Write to Realtime Database — fire-and-forget with timeout
      // Don't await these — they should not block UI progression
      FirebaseDatabase.instance
          .ref()
          .child('users/$uid/items/$timestamp')
          .set({
        'itemName':   widget.itemName,
        'floorLevel': widget.floorLevel,
        'floorIndex': widget.floorIndex,
        'photoUrl':   photoUrl,
        'timestamp':  timestamp,
        'createdAt':  DateTime.now().toIso8601String(),
      }).timeout(const Duration(seconds: 8)).catchError((e) {
        debugPrint('[DB] items write error/timeout: $e');
      });

      FirebaseDatabase.instance
          .ref()
          .child('users/$uid/currentItem')
          .set({
        'name':       widget.itemName,
        'floorLevel': widget.floorLevel,
        'floorIndex': widget.floorIndex,
        'photoUrl':   photoUrl,
        'updatedAt':  ServerValue.timestamp,
      }).timeout(const Duration(seconds: 8)).catchError((e) {
        debugPrint('[DB] currentItem write error/timeout: $e');
      });

      // Don't wait for DB — animate bar to 100% and proceed immediately
      if (mounted) {
        setState(() {
          _totalProgress = 0.5;
          _phasePercent  = 100;
        });
        await Future.delayed(const Duration(milliseconds: 400));
      }
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) {
        setState(() {
          _totalProgress = 0.5;
          _phasePercent  = 100;
        });
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  void _onComplete() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      // ── CHANGED: go to DeviceTrackingPage instead of MainPage ────────
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => DeviceTrackingPage(
          deviceName: widget.itemName,
          photoUrl: _uploadedPhotoUrl,
        )),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Phase label
    final String label = _phase == 0
        ? 'SAVING ITEM INFO... ($_phasePercent%)'
        : 'CALIBRATING FLOOR DETECTION... KEEP STILL ($_phasePercent%)';

    return Scaffold(
          body: AppBackground(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ListenableBuilder(
                listenable: _ble,
                builder: (_, __) => EspStatusBadge(status: bleToEspStatus(_ble)),
              ),
            ),
            const Spacer(),
            // ✅ Show warning when BLE disconnected during calibration
            if (_bleDisconnectedDuringCalib) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.red.shade600, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'SmartLocator went Offline!\nProgress paused — turn ON the hardware switch to continue.',
                        style: TextStyle(fontSize: 12, height: 1.4, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            AnimatedOpacity(
              opacity: _textOpacity,
              duration: const Duration(milliseconds: 300),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5C6BC0),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: _totalProgress),
                duration: const Duration(milliseconds: 400),
                builder: (context, animValue, _) {
                  return LinearProgressIndicator(
                    value: animValue,
                    minHeight: 12,
                    backgroundColor: const Color(0xFFD1D5F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF7986CB),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            if (_phase == 1) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.blue.shade600, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Keep SmartLocator completely still on the floor. Keep the switch ON.\n'
                        'This takes 60–90 seconds.',
                        style: TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Spacer(),
          ],
        ),
      ),
    ),
  ),
);
}
}

// ── Helper: compute EspStatus from BleService ─────────────────────────────
EspStatus bleToEspStatus(BleService ble) {
  if (ble.isConnected) return EspStatus.connected;
  if (ble.isScanning) return EspStatus.connecting;
  return EspStatus.disconnected;
}