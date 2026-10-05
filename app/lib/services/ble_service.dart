import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── TrackerStatus ────────────────────────────────────────────────────────────
class TrackerStatus {
  final String item;
  final int    floor;
  final String floorName;
  final String proximity;
  final int    rssi;
  final int    battery;
  final bool   buzzerOn;
  final int    volume;
  final int    beep;
  final bool   calDone;
  final String time;
  final String date;
  final bool   power;

  const TrackerStatus({
    this.item      = '',
    this.floor     = 0,
    this.floorName = '',
    this.proximity = 'SIGNAL LOST',
    this.rssi      = -100,
    this.battery   = 100,
    this.buzzerOn  = true,
    this.volume    = -1,
    this.beep      = -1,
    this.calDone   = false,
    this.time      = '',
    this.date      = '',
    this.power     = false,
  });

  factory TrackerStatus.fromJson(Map<String, dynamic> j) => TrackerStatus(
    item      : j['item']      as String? ?? '',
    floor     : j['floor']     as int?    ?? 0,
    floorName : j['floorName'] as String? ?? '',
    proximity : j['proximity'] as String? ?? 'SIGNAL LOST',
    rssi      : j['rssi']      as int?    ?? -100,
    battery   : j['battery']   as int?    ?? 100,
    buzzerOn  : j['buzzerOn']  as bool?   ?? true,
    volume    : j['volume']    as int?    ?? -1,
    beep      : j['beep']      as int?    ?? -1,
    calDone   : j['calDone']   as bool?   ?? false,
    time      : j['time']      as String? ?? '',
    date      : j['date']      as String? ?? '',
    power     : j['power']     as bool?   ?? true,
  );
}

// ── CalibStatus — from ESP32 calib JSON ──────────────────────────────────────
class CalibStatus {
  final int    progress;
  final bool   stable;
  final double pressure;
  final double stdDev;
  final int    samples;

  const CalibStatus({
    this.progress = 0,
    this.stable   = false,
    this.pressure = 0,
    this.stdDev   = 0,
    this.samples  = 0,
  });

  factory CalibStatus.fromJson(Map<String, dynamic> j) => CalibStatus(
    progress : j['progress'] as int?    ?? 0,
    stable   : j['stable']   as bool?   ?? false,
    pressure : (j['pressure'] as num?)?.toDouble() ?? 0,
    stdDev   : (j['stdDev']   as num?)?.toDouble() ?? 0,
    samples  : j['samples']  as int?    ?? 0,
  );
}

// ── BleService singleton ─────────────────────────────────────────────────────
class BleService extends ChangeNotifier {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  // ── UUIDs ─────────────────────────────────────────────────────────────────
  static const String _serviceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  static const String _rxUuid      = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
  static const String _txUuid      = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

  // ── Internal state ────────────────────────────────────────────────────────
  BluetoothDevice?         _device;
  BluetoothCharacteristic? _rxChar;
  BluetoothCharacteristic? _txChar;
  StreamSubscription?      _txSub;
  StreamSubscription?      _connSub;
  StreamSubscription?      _scanSub;
  String _rxBuffer = '';

  TrackerStatus _status    = const TrackerStatus();
  bool          _connected = false;
  // ── In-memory photo cache — survives navigation within same app session ──
  String _cachedPhotoUrl  = '';
  String _cachedItemName  = '';

  String get cachedPhotoUrl => _cachedPhotoUrl;
  String get cachedItemName => _cachedItemName;

  void cacheItemPhoto(String photoUrl, String itemName) {
    _cachedPhotoUrl = photoUrl;
    _cachedItemName = itemName;
  }
  bool          _scanning  = false;
  List<ScanResult> _scanResults = [];

  // ── Public streams ────────────────────────────────────────────────────────
  final _statusController = StreamController<TrackerStatus>.broadcast();
  final _connController   = StreamController<bool>.broadcast();
  final _calibController  = StreamController<CalibStatus>.broadcast();
  final _ackController    = StreamController<String>.broadcast();

  Stream<TrackerStatus> get statusStream => _statusController.stream;
  Stream<bool>          get connStream   => _connController.stream;
  Stream<CalibStatus>   get calibStream  => _calibController.stream;
  Stream<String>        get ackStream    => _ackController.stream;

  TrackerStatus    get status      => _status;
  bool             get isConnected => _connected;
  bool             get isScanning  => _scanning;
  List<ScanResult> get scanResults => _scanResults;

  // ── BLE SCAN ──────────────────────────────────────────────────────────────
  Future<void> startScan({int timeoutSec = 15}) async {
    _scanResults = [];
    notifyListeners();

    await FlutterBluePlus.stopScan();
    await Future.delayed(const Duration(milliseconds: 200));

    _scanning = true;
    notifyListeners();

    _scanSub?.cancel();
   // Include already-bonded devices so paired SmartLocator always appears
    final bonded = await FlutterBluePlus.bondedDevices;
    final bondedResults = bonded.map((d) => ScanResult(
      device: d,
      advertisementData: AdvertisementData(
        advName: d.platformName,
        connectable: true,
        manufacturerData: {},
        serviceData: {},
        serviceUuids: [],
        txPowerLevel: null,
        appearance: null,
      ),
      rssi: -60,
      timeStamp: DateTime.now(),
    )).toList();
    // Filter bonded list to only show named devices (hides random MAC-only devices)
    final namedBonded = bondedResults.where(
      (r) => r.device.platformName.isNotEmpty,
    ).toList();
    _scanResults = namedBonded;
    notifyListeners();

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      // Merge scan results with bonded — avoid duplicates
      final ids = results.map((r) => r.device.remoteId).toSet();
      final merged = [
        ...results,
        ...namedBonded.where((b) => !ids.contains(b.device.remoteId)),
      ];
      _scanResults = merged;
      notifyListeners();
    });

    await FlutterBluePlus.startScan(
      timeout: Duration(seconds: timeoutSec),
    );

    // Mark scanning done after timeout
    Future.delayed(Duration(seconds: timeoutSec), () {
      _scanning = false;
      notifyListeners();
    });
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _scanning = false;
    notifyListeners();
  }

  // ── CONNECT — returns bool so ConnectingDevicePage can check result ───────
  Future<bool> connect(BluetoothDevice device) async {
    _device = device;
    await _connSub?.cancel();

    final completer = Completer<bool>();

    _connSub = device.connectionState.listen((state) async {
      final isNowConnected = state == BluetoothConnectionState.connected;

      if (isNowConnected && !_connected) {
        _connected = true;
        _connController.add(true);
        notifyListeners();
        debugPrint('[BLE] Connected/Reconnected');
        await _setupCharacteristics();
        // Complete future on first successful connect
        if (!completer.isCompleted) completer.complete(true);

      } else if (!isNowConnected && _connected) {
        _connected = false;
        _rssiTimer?.cancel();
        // Emit SIGNAL LOST before disconnect so UI shows it first
        _status = TrackerStatus(
          item: _status.item, floor: _status.floor,
          floorName: _status.floorName, proximity: 'SIGNAL LOST',
          rssi: -100, battery: _status.battery, buzzerOn: _status.buzzerOn,
          volume: _status.volume, beep: _status.beep, calDone: _status.calDone,
          time: _status.time, date: _status.date, power: _status.power,
        );
        _statusController.add(_status);
        notifyListeners();
        await _txSub?.cancel();
        _txSub = null;
        _connController.add(false);
        notifyListeners();
        debugPrint('[BLE] Disconnected — will auto-reconnect in 3s');
        // Auto-reconnect so user doesn't need to manually reconnect
        _scheduleReconnect();
      }
    });

    try {
      // If Android OS already has this device connected (bonded + active),
      // skip connect() entirely and go straight to characteristic setup
      if (device.isConnected) {
        debugPrint('[BLE] Device already connected at OS level — skipping connect()');
        _connected = true;
        _connController.add(true);
        notifyListeners();
        await _setupCharacteristics();
        if (!completer.isCompleted) completer.complete(true);
      } else {
        await device.connect(
          autoConnect: false,
          timeout: const Duration(seconds: 15),
        );
      }
    } catch (e) {
      debugPrint('[BLE] connect() error: $e');
      // "Already connected" is not a real failure — handle it gracefully
      final msg = e.toString().toLowerCase();
      if (msg.contains('already') || msg.contains('connected')) {
        debugPrint('[BLE] Already connected exception — treating as success');
        if (!_connected) {
          _connected = true;
          _connController.add(true);
          notifyListeners();
          await _setupCharacteristics();
        }
        if (!completer.isCompleted) completer.complete(true);
      } else {
        if (!completer.isCompleted) completer.complete(false);
      }
    }

    // Timeout after 15s
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        debugPrint('[BLE] connect() timeout');
        return false;
      },
    );
  }

  // ── Setup characteristics ─────────────────────────────────────────────────
  Future<void> _setupCharacteristics() async {
    try {
      await _txSub?.cancel();
      _txSub  = null;
      _rxChar = null;
      _txChar = null;
      _rxBuffer = '';

      final services = await _device!.discoverServices();
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() == _serviceUuid) {
          for (final c in svc.characteristics) {
            final uuid = c.uuid.toString().toLowerCase();
            if (uuid == _rxUuid) _rxChar = c;
            if (uuid == _txUuid) _txChar = c;
          }
        }
      }

      if (_txChar == null || _rxChar == null) {
        debugPrint('[BLE] Characteristics not found!');
        return;
      }

      await _txChar!.setNotifyValue(true);

      _txSub = _txChar!.onValueReceived.listen((bytes) {
        final chunk = utf8.decode(bytes, allowMalformed: true);
        _rxBuffer += chunk;
        while (_rxBuffer.contains('\n')) {
          final idx  = _rxBuffer.indexOf('\n');
          final line = _rxBuffer.substring(0, idx).trim();
          _rxBuffer  = _rxBuffer.substring(idx + 1);
          if (line.isNotEmpty) _handleLine(line);
        }
      });

      debugPrint('[BLE] Characteristics ready');
      await _syncDateTime();
      _startRssiPolling();

      final prefs = await SharedPreferences.getInstance();
      final needsReset = prefs.getBool('needsBattReset') ?? false;
      if (needsReset) {
        await prefs.setBool('needsBattReset', false);
        await Future.delayed(const Duration(milliseconds: 500));
        await sendCommand('BATT:RESET');
        debugPrint('[BLE] Auto-sent BATT:RESET — red LED will turn OFF');
      }

    } catch (e) {
      debugPrint('[BLE] _setupCharacteristics error: $e');
    }
  }

  // ── Sync time/date — no intl package needed ───────────────────────────────
  Future<void> _syncDateTime() async {
    final now = DateTime.now();
    // Format manually — no intl dependency needed
    final h   = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final sec = now.second.toString().padLeft(2, '0');
    final y   = now.year.toString();
    final mo  = now.month.toString().padLeft(2, '0');
    final d   = now.day.toString().padLeft(2, '0');

    await sendCommand('TIME:$h:$min:$sec');
    await Future.delayed(const Duration(milliseconds: 200));
    await sendCommand('DATE:$y-$mo-$d');
    debugPrint('[BLE] Synced TIME:$h:$min:$sec DATE:$y-$mo-$d');
  }

  Timer? _rssiTimer;

  void _startRssiPolling() {
    _rssiTimer?.cancel();
    _rssiTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_connected || _device == null) return;
      try {
        final rssi = await _device!.readRssi();
        // Override proximity with Flutter-measured RSSI
        _status = TrackerStatus(
          item:      _status.item,
          floor:     _status.floor,
          floorName: _status.floorName,
          proximity: _rssiToProximity(rssi),
          rssi:      rssi,
          battery:   _status.battery,
          buzzerOn:  _status.buzzerOn,
          volume:    _status.volume,
          beep:      _status.beep,
          calDone:   _status.calDone,
          time:      _status.time,
          date:      _status.date,
          power:     _status.power,
        );
        _statusController.add(_status);
        notifyListeners();
      } catch (_) {}
    });
  }

  String _rssiToProximity(int rssi) {
    if (rssi >= -55) return 'CLOSED BY';
    if (rssi >= -70) return 'NEARBY';
    if (rssi >= -80) return 'FAR';
    if (rssi >= -95) return 'TOO FAR';
    return 'SIGNAL LOST';
  }

  // ── Parse incoming JSON ───────────────────────────────────────────────────
  void _handleLine(String line) {
    try {
      final j    = jsonDecode(line) as Map<String, dynamic>;
      final type = j['type'] as String? ?? '';

      if (type == 'status') {
        final incoming = TrackerStatus.fromJson(j);
        // Keep Flutter-measured RSSI proximity — don't let ESP32 overwrite it
        // ESP32 proximity is always SIGNAL LOST (it can't scan the phone)
        _status = TrackerStatus(
          item:      incoming.item,
          floor:     incoming.floor,
          floorName: incoming.floorName,
          proximity: _status.rssi > -100
              ? _rssiToProximity(_status.rssi)   // use Flutter RSSI
              : incoming.proximity,               // fallback only if no RSSI yet
          rssi:      _status.rssi > -100 ? _status.rssi : incoming.rssi,
          battery:   incoming.battery,
          buzzerOn:  incoming.buzzerOn,
          volume:    incoming.volume,
          beep:      incoming.beep,
          calDone:   incoming.calDone,
          time:      incoming.time,
          date:      incoming.date,
          power:     incoming.power,
        );
        _statusController.add(_status);
        notifyListeners();

      } else if (type == 'calib') {
        // Forward to calibStream for LoadingUploadPage
        _calibController.add(CalibStatus.fromJson(j));
        // Also update status fields that calib JSON has
        notifyListeners();

      } else if (type == 'ack') {
        final cmd = j['cmd'] as String? ?? '';
        _ackController.add(cmd);
        // Sync power state from ack
        if (cmd == 'POWER:ON') {
            _status = TrackerStatus(
              item: _status.item, floor: _status.floor,
              floorName: _status.floorName, proximity: _status.proximity,
              rssi: _status.rssi, battery: _status.battery,
              buzzerOn: _status.buzzerOn, volume: _status.volume,
              beep: _status.beep, calDone: _status.calDone,
              time: _status.time, date: _status.date, power: true,
            );
            notifyListeners();
          }
          if (cmd == 'POWER:OFF') {
            _status = TrackerStatus(
              item: _status.item, floor: _status.floor,
              floorName: _status.floorName, proximity: _status.proximity,
              rssi: _status.rssi, battery: _status.battery,
              buzzerOn: _status.buzzerOn, volume: _status.volume,
              beep: _status.beep, calDone: _status.calDone,
              time: _status.time, date: _status.date, power: false,
            );
            notifyListeners();
          }
      }
    } catch (e) {
      debugPrint('[BLE] JSON parse error: $e — line: $line');
    }
  }

  // ── Send command ──────────────────────────────────────────────────────────
  Future<void> sendCommand(String cmd) async {
    if (_rxChar == null || !_connected) {
      debugPrint('[BLE] Cannot send — not connected');
      return;
    }
    try {
      await _rxChar!.write(utf8.encode(cmd), withoutResponse: true);
      debugPrint('[BLE] Sent: $cmd');
    } catch (e) {
      debugPrint('[BLE] sendCommand error: $e');
    }
  }

  // ── Convenience methods — ALL methods other pages use ────────────────────
  Future<void> setItem(String name)     => sendCommand('ITEM:$name');
  Future<void> setItemName(String name) => sendCommand('ITEM:$name'); // alias
  Future<void> setFloor(int floor)      => sendCommand('FLOOR:$floor');
  Future<void> setBuzzer(bool on)       => sendCommand(on ? 'BUZZER:ON' : 'BUZZER:OFF');
  Future<void> setVolume(int vol)       => sendCommand('VOL:$vol');
  Future<void> setBeep(int beep)        => sendCommand('BEEP:$beep');
  Future<void> setPower(bool on)        => sendCommand(on ? 'POWER:ON' : 'POWER:OFF');
  Future<void> resetDevice()            => sendCommand('RESET');
  Future<void> resetBatteryTimer() => sendCommand('BATT:RESET'); 
    Future<void> saveLastSeen(String uid) async {
    if (_status.item.isEmpty) return;
    try {
      final db = FirebaseDatabase.instance.ref();
      await db.child('users/$uid/lastSeen').set({
        'itemName':  _status.item,
        'floor':     _status.floorName,
        'proximity': _status.proximity,
        'battery':   _status.battery,
        'time':      _status.time,
        'date':      _status.date,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[DB] saveLastSeen error: $e');
    }
  }

  // ── Disconnect ────────────────────────────────────────────────────────────
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();   // ← ADD
    _reconnectTimer = null;
    _rssiTimer?.cancel();    // ← ADD THIS
    _rssiTimer = null;
    await _txSub?.cancel();
    await _connSub?.cancel();
    await _device?.disconnect();
    _connected = false;
    _rxChar    = null;
    _txChar    = null;
    _connController.add(false);
    notifyListeners();
  }

  Timer? _reconnectTimer;

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_connected) {
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        return;
      }
      if (_device == null) {
        _reconnectTimer?.cancel();
        return;
      }
      debugPrint('[BLE] Retry reconnect...');
      // Check if OS already connected (e.g. after manual Bluetooth pairing)
      if (_device!.isConnected) {
        debugPrint('[BLE] OS already connected — setting up characteristics');
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _connected = true;
        _connController.add(true);
        notifyListeners();
        await _setupCharacteristics();
        return;
      }
      try {
        await _device!.connect(
          autoConnect: false,
          timeout: const Duration(seconds: 8),
        );
      } catch (_) {
        // Will retry next tick
      }
    });
  }
}

