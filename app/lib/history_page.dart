import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'app_background.dart';
import 'dart:io';
import 'esp_status_badge.dart';
import 'services/ble_service.dart';
import 'tracking_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _historyItems = [];
  bool _loading = true;

  // ── Long-press selection state ────────────────────────────────────────────
  final Set<String> _selectedKeys = {};   // Firebase keys of selected items
  bool get _isSelecting => _selectedKeys.isNotEmpty;

  @override
  void initState() { super.initState(); _loadHistory(); }

  Future<void> _loadHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { setState(() => _loading = false); return; }
    try {
      final snap = await FirebaseDatabase.instance
          .ref('users/${user.uid}/history')
          .get()
          .timeout(const Duration(seconds: 8));

      if (snap.exists && snap.value != null) {
        final data  = snap.value as Map;
        final items = <Map<String, dynamic>>[];
        for (final entry in data.entries) {
          try {
            final m        = Map<String, dynamic>.from(entry.value as Map);
            final itemName = m['itemName'] as String? ?? '';
            final username = m['username'] as String? ?? 'User';
            if (itemName.isEmpty) continue;
            final ts       = m['timestamp'] as int? ?? 0;
            final age      = DateTime.now().millisecondsSinceEpoch - ts;
            final isRecent = age < 24 * 60 * 60 * 1000;
            final status   = m['status'] as String? ?? (isRecent ? 'active' : 'closed');
            items.add({
              'key':      entry.key,   // ← Firebase push key for deletion
              'title':    '$username tracked $itemName',
              'itemName': itemName,
              'time':     m['time']     as String? ?? '',
              'date':     m['date']     as String? ?? '',
              'status':   status,
              'timestamp': ts,
              'photoUrl': m['photoUrl'] as String? ?? '',
            });
          } catch (_) { continue; }
        }
        items.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
        setState(() { _historyItems = items; _loading = false; });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('[History] load error: $e');
      setState(() => _loading = false);
    }
  }

  // ── Delete selected items from Firebase ───────────────────────────────────
  Future<void> _deleteSelected() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final count = _selectedKeys.length;

    // Confirm dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete entries?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Delete $count selected ${count == 1 ? 'entry' : 'entries'}? '
          'This cannot be undone.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Delete each selected key from Firebase
    final db = FirebaseDatabase.instance.ref();
    for (final key in _selectedKeys) {
      await db.child('users/${user.uid}/history/$key').remove()
          .catchError((e) => debugPrint('[History] delete error: $e'));
    }

    // Remove from local list + clear selection
    setState(() {
      _historyItems.removeWhere((i) => _selectedKeys.contains(i['key']));
      _selectedKeys.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count ${count == 1 ? 'entry' : 'entries'} deleted'),
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ── Clear ALL history ─────────────────────────────────────────────────────
  Future<void> _clearAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear all history?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('This will delete ALL tracking history permanently.',
            style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseDatabase.instance
          .ref('users/${user.uid}/history')
          .remove()
          .catchError((e) => debugPrint('[History] clear error: $e'));
    }

    setState(() {
      _historyItems.clear();
      _selectedKeys.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('History cleared'),
            duration: Duration(seconds: 2)));
    }
  }

  @override
  void dispose() { _searchController.dispose(); super.dispose(); }

  // ── Filtering ─────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _applySearch(List<Map<String, dynamic>> list) {
    if (_searchController.text.isEmpty) return list;
    return list.where((item) =>
        (item['title'] as String).toLowerCase()
            .contains(_searchController.text.toLowerCase())).toList();
  }

  // ── Now Tracking: 只取最新的1条 ──────────────────────
List<Map<String, dynamic>> get _filteredNow {
  final sorted = _applySearch(_historyItems);
  if (sorted.isEmpty) return [];
  final first = sorted.first;
  final ts = first['timestamp'] as int? ?? 0;
  final age = DateTime.now().millisecondsSinceEpoch - ts;
  // ✅ 只有在过去24小时内的最新记录才显示为 Now Tracking
  if (age < 24 * 60 * 60 * 1000) {
    return [first];
  }
  return []; // 超过24小时 → 不显示 Now Tracking
}

// ── Recent: 过去7天内，排除最新1条 ──────────────────
List<Map<String, dynamic>> get _filteredThisWeek {
  final all = _applySearch(_historyItems);
  if (all.isEmpty) return [];
  final now = DateTime.now().millisecondsSinceEpoch;
  // ✅ 如果第一条在24小时内（属于Now Tracking），skip(1)
  // 如果第一条超过24小时（不属于Now Tracking），skip(0) = 全部进 Recent
  final first = all.first;
  final firstAge = now - (first['timestamp'] as int? ?? 0);
  final skipCount = firstAge < 24 * 60 * 60 * 1000 ? 1 : 0;

  return all.skip(skipCount).where((i) {
    final age = now - (i['timestamp'] as int? ?? 0);
    return age < 7 * 24 * 60 * 60 * 1000;
  }).toList();
}

// ── Earlier: 7天前的所有 ────────────────────────────
List<Map<String, dynamic>> get _filteredEarlier {
  final all = _applySearch(_historyItems);
  if (all.isEmpty) return [];
  final now = DateTime.now().millisecondsSinceEpoch;
  return all.skip(1).where((i) {
    final age = now - (i['timestamp'] as int? ?? 0);
    return age >= 7 * 24 * 60 * 60 * 1000;
  }).toList();
}

  @override
  Widget build(BuildContext context) {
    final isDark       = Theme.of(context).brightness == Brightness.dark;
    final headerBg     = isDark ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.7);
    final cardBg       = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final titleColor   = isDark ? Colors.white : const Color(0xFF424242);
    final sectionColor = isDark ? Colors.grey.shade400 : const Color(0xFF616161);
    final searchBg     = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final hintColor    = Colors.grey.shade500;
    final subColor     = isDark ? Colors.grey.shade400 : Colors.grey.shade500;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Stack(
            children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ───────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: headerBg,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(children: [
                  // Back button OR cancel selection
                 GestureDetector(
                    onTap: () {
                      if (_isSelecting) {
                        setState(() => _selectedKeys.clear());
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12), // ← curved square
                        boxShadow: [BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10, spreadRadius: 2)],
                      ),
                      child: Icon(
                        _isSelecting ? Icons.close : Icons.arrow_back,
                        color: const Color(0xFF1565C0), size: 24),
                    ),
                  ), 
                  const SizedBox(width: 16),

                  // Title OR selection count
                  Expanded(child: Text(
                    _isSelecting
                        ? '${_selectedKeys.length} selected'
                        : 'History',
                    style: TextStyle(fontSize: 20,
                        fontWeight: FontWeight.w600, color: titleColor))),
                  
                  EspStatusBadge(status: bleToEspStatus(BleService())),
                  const SizedBox(width: 8),

                  // Delete selected OR clear all bin
                  if (_isSelecting)
                    GestureDetector(
                      onTap: _deleteSelected,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(
                              color: Colors.red.withOpacity(0.15), blurRadius: 4)],
                        ),
                        child: Icon(Icons.delete_rounded,
                            color: Colors.red.shade600, size: 20),
                      ),
                    )
                  else
                    GestureDetector(
                    onTap: _isSelecting ? _deleteSelected : _clearAllHistory,
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12), // ← curved square
                        boxShadow: [BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10, spreadRadius: 2)],
                      ),
                      child: Icon(
                        _isSelecting ? Icons.delete_rounded : Icons.delete_outline,
                        color: _isSelecting ? Colors.red.shade600 : const Color(0xFF1565C0),
                        size: 24),
                    ),
                  ),
                ]),
              ),

              // ── Search ────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: searchBg,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08),
                        blurRadius: 8, spreadRadius: 2, offset: const Offset(0, 2))],
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      hintStyle: TextStyle(color: hintColor, fontSize: 16),
                      prefixIcon: Icon(Icons.search, color: hintColor, size: 22),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),

              // ── List ─────────────────────────────────────────────────────
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          if (_filteredNow.isNotEmpty) ...[
                            _sectionHeader('🔵 Now Tracking', sectionColor),
                            const SizedBox(height: 12),
                            ..._filteredNow.map((i) => _buildItem(i,
                                isActive: true, cardBg: cardBg,
                                subColor: subColor, titleColor: titleColor,
                                isDark: isDark)),
                            const SizedBox(height: 24),
                          ],
                          if (_filteredThisWeek.isNotEmpty) ...[
                            _sectionHeader('📅 Recent  (${_filteredThisWeek.length})', sectionColor),
                            const SizedBox(height: 12),
                            ..._filteredThisWeek.map((i) => _buildItem(i,
                                isActive: true, cardBg: cardBg,
                                subColor: subColor, titleColor: titleColor,
                                isDark: isDark)),
                            const SizedBox(height: 24),
                          ],
                          if (_filteredEarlier.isNotEmpty) ...[
                            _sectionHeader('🗂️ Earlier  (${_filteredEarlier.length})', sectionColor),
                            const SizedBox(height: 12),
                            ..._filteredEarlier.map((i) => _buildItem(i,
                                isActive: false, cardBg: cardBg,
                                subColor: subColor, titleColor: titleColor,
                                isDark: isDark)),
                          ],
                          if (_filteredNow.isEmpty &&
                              _filteredThisWeek.isEmpty &&
                              _filteredEarlier.isEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(40),
                                child: Column(children: [
                                  Icon(Icons.history, size: 64,
                                      color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                                  const SizedBox(height: 16),
                                  Text('No history found',
                                      style: TextStyle(
                                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                          fontSize: 16)),
                                ]),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
         ],
        ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, Color color) => Text(title,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color));

  Widget _buildItem(Map<String, dynamic> item, {
    required bool isActive,
    required Color cardBg,
    required Color subColor,
    required Color titleColor,
    required bool isDark,
  }) {
    final photoUrl  = item['photoUrl'] as String? ?? '';
    final key       = item['key'] as String? ?? '';
    final isSelected = _selectedKeys.contains(key);

    return GestureDetector(
      // ── Long press → enter selection mode ─────────────────────────────
      onLongPress: () {
        HapticFeedback.mediumImpact();   // vibrate on long press
        setState(() {
          if (isSelected) {
            _selectedKeys.remove(key);
          } else {
            _selectedKeys.add(key);
          }
        });
      },
      // ── Normal tap → toggle if selecting, else open ───────────────────
      onTap: () {
        if (_isSelecting) {
          setState(() {
            if (isSelected) {
              _selectedKeys.remove(key);
            } else {
              _selectedKeys.add(key);
            }
          });
        } else {
          _onItemTap(item, isActive);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          // ── Selected: red tint highlight ──────────────────────────────
          color: isSelected
              ? (isDark ? Colors.red.shade900.withOpacity(0.4) : Colors.red.shade50)
              : cardBg,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: Colors.red.shade400, width: 1.5)
              : Border.all(color: Colors.transparent),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
              blurRadius: 6, spreadRadius: 1, offset: const Offset(0, 2))],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),

          // ── Leading: checkbox when selecting, bluetooth icon otherwise ──
          leading: isSelected
              ? Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 20),
                )
              : Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFFE3F2FD) : Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.bluetooth,
                      color: isActive ? const Color(0xFF1976D2) : Colors.grey.shade500,
                      size: 22),
                ),

          title: Text(item['title'] as String,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500,
                  color: isSelected
                      ? Colors.red.shade700
                      : (isActive ? titleColor : subColor))),

          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Text(item['time'] as String,
                  style: TextStyle(fontSize: 13, color: subColor)),
              const SizedBox(width: 8),
              Container(width: 4, height: 4,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: subColor)),
              const SizedBox(width: 8),
              Text(item['date'] as String,
                  style: TextStyle(fontSize: 13, color: subColor)),
            ]),
          ),

          // ── Trailing: delete icon when selected, photo otherwise ───────
          trailing: isSelected
              ? Icon(Icons.delete_rounded, color: Colors.red.shade400, size: 22)
              : _buildPhoto(photoUrl),
        ),
      ),
    );
  }

  // ── Handle item tap based on section ─────────────────────────────────────
void _onItemTap(Map<String, dynamic> item, bool isActive) {
  final ble = BleService();

  // ── Now Tracking (最新1条) → 直接进 live tracking ────────────────────
  if (_filteredNow.isNotEmpty && item['key'] == _filteredNow.first['key']) {
    if (ble.isConnected) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DeviceTrackingPage(
          deviceName: ble.cachedItemName.isNotEmpty
              ? ble.cachedItemName
              : (item['itemName'] as String? ?? ''),
          photoUrl: ble.cachedPhotoUrl,
        ),
      ));
    } else {
      _showReconnectDialog();
    }
    return;
  }

  // ── Recent + Earlier → 都显示 last recorded data dialog ──────────────
  _showLastSeenDialog(item);
}

void _showReconnectDialog() {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bluetooth_disabled, color: Colors.orange, size: 44),
            const SizedBox(height: 12),
            const Text('SmartLocator Not Connected',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
                'Please reconnect via Find Device first before resuming tracking.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              ),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    ),
  );
}

void _showWeekConfirmDialog(Map<String, dynamic> item) {
  final ble = BleService();
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Track "${item['itemName']}" again?',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Do you want to continue tracking this item?',
                style: TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: const Text('No'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (ble.isConnected) {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => DeviceTrackingPage(
                          deviceName: item['itemName'] as String? ?? '',
                          photoUrl: ble.cachedPhotoUrl,
                        ),
                      ));
                    } else {
                      _showReconnectDialog();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: const Text('Yes', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void _showLastSeenDialog(Map<String, dynamic> item) {
  showDialog(
    context: context,
    builder: (ctx) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100, shape: BoxShape.circle),
                    child: Icon(Icons.history,
                        color: Colors.grey.shade600, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['itemName'] as String? ?? '—',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                        const Text('Last recorded data',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  // ✅ Item photo on the right
                  const SizedBox(width: 10),
                  _buildDialogPhoto(item['photoUrl'] as String? ?? ''),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              _lastSeenRow(Icons.calendar_today_outlined, 'Date',
                  item['date'] as String? ?? '—', isDark),
              const SizedBox(height: 8),
              _lastSeenRow(Icons.access_time_outlined, 'Time',
                  item['time'] as String? ?? '—', isDark),
              const SizedBox(height: 16),
              Builder(builder: (ctx) {
                final isDarkDialog = Theme.of(ctx).brightness == Brightness.dark;
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDarkDialog
                        ? const Color(0xFF3D3000)   // dark: deep amber background
                        : Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDarkDialog
                          ? Colors.amber.shade700
                          : Colors.amber.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.amber.shade400, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This is last recorded data only. Live tracking unavailable for older records.',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            // ✅ dark mode: bright amber; light mode: dark amber
                            color: isDarkDialog
                                ? Colors.amber.shade200
                                : Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade700,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Close',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _lastSeenRow(IconData icon, String label, String value, bool isDark) {
  return Row(
    children: [
      Icon(icon, size: 16,
          color: isDark ? Colors.white54 : Colors.grey.shade500),
      const SizedBox(width: 8),
      Text('$label: ',
          style: TextStyle(fontSize: 13,
              color: isDark ? Colors.white54 : Colors.grey.shade600)),
      Expanded(
        child: Text(value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87)),
      ),
    ],
  );
}

Widget _buildDialogPhoto(String photoUrl) {
  const double size = 56;
  const radius = BorderRadius.all(Radius.circular(10));
  final Widget fallback = Container(
    width: size, height: size,
    decoration: BoxDecoration(
        color: Colors.grey.shade100, borderRadius: radius),
    child: Icon(Icons.image_outlined,
        color: Colors.grey.shade400, size: 24),
  );

  if (photoUrl.isEmpty) return fallback;

  if (photoUrl.startsWith('http')) {
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(photoUrl,
          width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback),
    );
  }

  final file = File(photoUrl);
  if (!file.existsSync()) return fallback;
  return ClipRRect(
    borderRadius: radius,
    child: Image.file(file,
        width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback),
  );
}

  // ── Photo trailing ────────────────────────────────────────────────────────
  Widget _buildPhoto(String photoUrl) {
    const double size = 48;
    const radius = BorderRadius.all(Radius.circular(10));
    final Widget fallback = Container(
      width: size, height: size,
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: radius),
      child: Icon(Icons.image_outlined, color: Colors.grey.shade500, size: 24),
    );

    if (photoUrl.isEmpty) return fallback;

    if (photoUrl.startsWith('http')) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(photoUrl,
            width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return Container(
                width: size, height: size,
                decoration: BoxDecoration(
                    color: Colors.grey.shade100, borderRadius: radius),
                child: const Center(child: SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
              );
            }),
      );
    }

    final file = File(photoUrl);
    if (!file.existsSync()) return fallback;
    return ClipRRect(
      borderRadius: radius,
      child: Image.file(file, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback),
    );
  }
}

// ── Helper: compute EspStatus from BleService ─────────────────────────────
EspStatus bleToEspStatus(BleService ble) {
  if (ble.isConnected) return EspStatus.connected;
  if (ble.isScanning) return EspStatus.connecting;
  return EspStatus.disconnected;
}