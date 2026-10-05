import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'loading_upload_page.dart';
import 'services/ble_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';   // ← NEW
import 'app_background.dart';
import 'esp_status_badge.dart';

class ItemInformationPage extends StatefulWidget {
  const ItemInformationPage({super.key});

  @override
  State<ItemInformationPage> createState() => _ItemInformationPageState();
}
class _ItemInformationPageState extends State<ItemInformationPage> {
  final _nameController = TextEditingController();
  String? _selectedFloor;
  File? _selectedPhoto;
  bool _uploadingPhoto = false;   // ← NEW: shows progress while uploading

  final List<String> _floors = [
    'Ground floor',
    'Floor 1',
    'Floor 2',
    'Floor 3',
    'Floor 4',
  ];

  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ── Photo picker bottom sheet ────────────────────────────────────────────
  Future<void> _showPhotoOptions() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF3A4A5C),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Upload Photo',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _pickImage(ImageSource.gallery);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A5A6C),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFF6A7A8C), width: 2),
                      ),
                      child: const Column(children: [
                        Icon(Icons.photo_library_outlined,
                            color: Colors.white70, size: 36),
                        SizedBox(height: 8),
                        Text('Gallery',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 14)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _pickImage(ImageSource.camera);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A5A6C),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFF6A7A8C), width: 2),
                      ),
                      child: const Column(children: [
                        Icon(Icons.camera_alt_outlined,
                            color: Colors.white70, size: 36),
                        SizedBox(height: 8),
                        Text('Camera',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 14)),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1080,
      );
      if (picked != null) {
        setState(() => _selectedPhoto = File(picked.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick image: $e')),
        );
      }
    }
  }

  // ── NEW: Upload photo to Firebase Storage → return download URL ──────────
  Future<String?> _uploadPhotoToStorage(File photo, String itemName) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      // Path: items/{uid}/{timestamp}_{itemName}.jpg
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${timestamp}_$itemName.jpg';
      final ref = FirebaseStorage.instance
          .ref()
          .child('items')
          .child(user.uid)
          .child(fileName);

      // Upload with metadata
      final uploadTask = ref.putFile(
        photo,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('[Storage] upload error: $e');
      return null;
    }
  }

  // ── UPDATED: upload photo first, then save URL to DB ────────────────────
  Future<void> _onChoose() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an item name')),
      );
      return;
    }
    if (_selectedFloor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a floor level')),
      );
      return;
    }

    final int floorIndex = _floors.indexOf(_selectedFloor!);
    final ble = BleService();

    // Check BLE connection first
    if (!ble.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SmartLocator disconnected — please reconnect first'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // ── Upload photo to Firebase Storage if one was selected ─────────────
    String? photoUrl;
    if (_selectedPhoto != null) {
      setState(() => _uploadingPhoto = true);
      photoUrl = await _uploadPhotoToStorage(_selectedPhoto!, name);
      if (mounted) setState(() => _uploadingPhoto = false);

      if (photoUrl == null && mounted) {
        // Show warning but don't block — continue without photo
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo upload failed — saving without photo'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    // Send item name to ESP32
    if (ble.isConnected) ble.setItemName(name);

    // Save to Firebase Realtime DB history (with photoUrl if uploaded)
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final db   = FirebaseDatabase.instance.ref();
        final snap = await db
            .child('users/${user.uid}/username')
            .get()
            .timeout(const Duration(seconds: 4),
                onTimeout: () => throw 'timeout');
        final uname = snap.value as String? ?? 'User';
        final now   = DateTime.now();
        final timeStr =
            '${now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour)}'
            ':${now.minute.toString().padLeft(2, '0')} '
            '${now.hour < 12 ? "A.M." : "P.M."}';
        final dateStr = '${now.day}/${now.month}/${now.year}';

        // ── Save history entry including photoUrl ──────────────────────
        final historyData = {
          'username':  uname,
          'itemName':  name,
          'floor':     _selectedFloor,
          'time':      timeStr,
          'date':      dateStr,
          'timestamp': now.millisecondsSinceEpoch,
          'status':    'active',
          'photoUrl': ?photoUrl,  // ← only if uploaded
        };

        db
            .child('users/${user.uid}/history')
            .push()
            .set(historyData)
            .timeout(const Duration(seconds: 8))
            .catchError((e) {
          debugPrint('[DB] history write error/timeout: $e');
        });

        // ── Also update currentItem with latest photoUrl ───────────────
        db.child('users/${user.uid}/currentItem').update({
          'name':      name,
          'floorIndex': floorIndex,
          'floorLevel': _selectedFloor,
          'updatedAt':  now.millisecondsSinceEpoch,
          'photoUrl': ?photoUrl,
        }).catchError((e) {
          debugPrint('[DB] currentItem update error: $e');
        });

      } catch (e) {
        debugPrint('[DB] history save error: $e');
      }
    }

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoadingUploadPage(
          itemName:   name,
          floorLevel: _selectedFloor!,
          floorIndex: floorIndex,
          photo:      _selectedPhoto,
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: const InputDecorationTheme(filled: false),
        ),
        child: AppBackground(
          child: SafeArea(
            child: Stack(
              children: [
              SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top,
                ),
                child: Column(
                  children: [
                    // Back button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10, spreadRadius: 2)],
                              ),
                              child: const Icon(Icons.arrow_back,
                                  color: Color(0xFF1565C0), size: 24),
                            ),
                          ),
                          const Spacer(),
                          ListenableBuilder(
                            listenable: BleService(),
                            builder: (_, __) => EspStatusBadge(
                                status: bleToEspStatus(BleService())),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Card
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A4A5C),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 15,
                            spreadRadius: 3,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Center(
                            child: Text('Item Information',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 20),

                          // ── Photo upload area ──────────────────────────
                          GestureDetector(
                            onTap: _uploadingPhoto ? null : _showPhotoOptions,
                            child: Container(
                              width: double.infinity,
                              height: 160,
                              decoration: BoxDecoration(
                                color: const Color(0xFF4A5A6C),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: const Color(0xFF6A7A8C), width: 2),
                              ),
                              child: _uploadingPhoto
                                  // ── Uploading spinner ────────────────
                                  ? const Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        CircularProgressIndicator(
                                            color: Colors.white70),
                                        SizedBox(height: 12),
                                        Text('Uploading photo...',
                                            style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13)),
                                      ],
                                    )
                                  : _selectedPhoto != null
                                      // ── Photo preview ────────────────
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              Image.file(_selectedPhoto!,
                                                  fit: BoxFit.cover),
                                              Positioned(
                                                bottom: 0,
                                                left: 0,
                                                right: 0,
                                                child: Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 6),
                                                  color: Colors.black54,
                                                  child: const Text(
                                                    'Tap to change',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 12),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      // ── Empty placeholder ────────────
                                      : Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.image_outlined,
                                                size: 40,
                                                color: Colors.grey[400]),
                                            const SizedBox(height: 8),
                                            Text('Upload photo',
                                                style: TextStyle(
                                                    color: Colors.grey[400],
                                                    fontSize: 14)),
                                            const SizedBox(height: 4),
                                            Text('Gallery or Camera',
                                                style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 11)),
                                          ],
                                        ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Item name input
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4A5A6C),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: const Color(0xFF6A7A8C), width: 2),
                            ),
                            child: TextField(
                              controller: _nameController,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Item name',
                                hintStyle: TextStyle(color: Colors.white70),
                                border: InputBorder.none,
                                filled: false,
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          const Text(
                            'Select floor level you stayed at in the current moment!',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),

                          const SizedBox(height: 8),

                          // Floor dropdown
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4A5A6C),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: const Color(0xFF6A7A8C), width: 2),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedFloor,
                                hint: const Text('Floor level Selection',
                                    style:
                                        TextStyle(color: Colors.white70)),
                                dropdownColor: const Color(0xFF3A4A5C),
                                icon: const Icon(Icons.arrow_drop_down,
                                    color: Colors.white70),
                                isExpanded: true,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 15),
                                onChanged: (String? newValue) {
                                  setState(() => _selectedFloor = newValue);
                                },
                                items: _floors
                                    .map<DropdownMenuItem<String>>(
                                        (String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Choose button
                          Align(
                            alignment: Alignment.centerRight,
                            child: GestureDetector(
                              onTap: _uploadingPhoto ? null : _onChoose,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 28, vertical: 12),
                                decoration: BoxDecoration(
                                  color: _uploadingPhoto
                                      ? Colors.grey
                                      : const Color(0xFF5C6BC0),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: _uploadingPhoto
                                      ? []
                                      : [
                                          BoxShadow(
                                            color: const Color(0xFF5C6BC0)
                                                .withOpacity(0.4),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                ),
                                child: const Text('Choose',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
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