import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'app_background.dart';
import 'esp_status_badge.dart';
import 'services/ble_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  // ── Firebase data ────────────────────────────────────────────────────────
  Map<String, int> _itemFrequency = {};
  Map<String, String> _displayNames = {};
  bool _loading = true;

  // ── Alert thresholds dismissed ───────────────────────────────────────────
  Set<int> _dismissedThresholds = {};

  // ── Tooltip state ────────────────────────────────────────────────────────
  String? _selectedBar;
  String? _selectedBarType;

  // ── Collapsible tips state ───────────────────────────────────────────────
  final List<bool> _expanded = [false, false, false, false, false];

  // ── Bar tap animation ────────────────────────────────────────────────────
  late AnimationController _tooltipController;

  int get _currentCap {
    if (_dismissedThresholds.isEmpty) return 5;
    final maxDismissed = _dismissedThresholds.reduce((a, b) => a > b ? a : b);
    return (maxDismissed + 5).clamp(5, 25);
  }

  @override
  void initState() {
    super.initState();
    _tooltipController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _loadData();
  }

  @override
  void dispose() {
    _tooltipController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final snap = await FirebaseDatabase.instance
          .ref('users/${user.uid}/history')
          .get();
      final Map<String, int> freq = {};
      final Map<String, String> displayNames = {};
      if (snap.exists) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        for (final v in data.values) {
          final m = Map<String, dynamic>.from(v as Map);
          final rawName = (m['itemName'] as String? ?? '').trim();
          final normName = rawName.toLowerCase();
          if (normName.isNotEmpty) {
            freq[normName] = (freq[normName] ?? 0) + 1;
            if (!displayNames.containsKey(normName)) {
              displayNames[normName] = rawName;
            }
          }
        }
      }
      setState(() {
        _itemFrequency = freq;
        _displayNames = displayNames;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Dashboard] load error: $e');
      setState(() => _loading = false);
    }
  }

  // ── Derived stats ─────────────────────────────────────────────────────────
  int get _totalTracked =>
      _itemFrequency.values.fold(0, (a, b) => a + b);

  double get _avgPerItem => _itemFrequency.isEmpty
      ? 0
      : _totalTracked / _itemFrequency.length;

  List<String> get _itemsAtRisk =>
      _itemFrequency.entries.where((e) => e.value >= 5).map((e) => e.key).toList();

  int get _safeItems =>
      _itemFrequency.values.where((v) => v < 5).length;

  // ── Active alert threshold ────────────────────────────────────────────────
  int? get _activeAlertThreshold {
    const thresholds = [5, 10, 15, 20];
    final maxFreq = _itemFrequency.isEmpty
        ? 0
        : _itemFrequency.values.reduce((a, b) => a > b ? a : b);
    for (final t in thresholds) {
      if (maxFreq >= t && !_dismissedThresholds.contains(t)) return t;
    }
    return null;
  }

  List<String> _itemsExceedingThreshold(int threshold) =>
      _itemFrequency.entries
          .where((e) => e.value >= threshold)
          .map((e) => e.key)
          .toList();

  Future<void> _resetTrackingData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseDatabase.instance
            .ref('users/${user.uid}/history')
            .remove();
      } catch (e) {
        debugPrint('[Dashboard] reset error: $e');
      }
    }
    setState(() {
      _itemFrequency       = {};
      _displayNames        = {};
      _dismissedThresholds = {};
      _selectedBar         = null;
      _selectedBarType     = null;
    });
  }

  void _showResetConfirmDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Do you sure to delete the current tracking data?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                    ),
                    child: Text('No',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 14)),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _resetTrackingData();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                    ),
                    child: const Text('Yes',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportToPdf() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generating PDF report...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

      final pdf = pw.Document();

      final sortedItems = _itemFrequency.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('1976D2'),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'BluePixels SmartLocator',
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Dashboard Report   ${now.day}-${now.month}-${now.year}',
                        style: pw.TextStyle(
                          fontSize: 12,
                          color: PdfColor.fromHex('BBDEFB'),
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 24),
                pw.Text(
                  'PERSONAL ITEM TRACKING ANALYSIS',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('9E9E9E'),
                    letterSpacing: 1.2,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Row(
                  children: [
                    _pdfSummaryCard('Total tracked', '$_totalTracked', '1976D2'),
                    pw.SizedBox(width: 8),
                    _pdfSummaryCard('Items at risk', '${_itemsAtRisk.length}', 'D32F2F'),
                    pw.SizedBox(width: 8),
                    _pdfSummaryCard('Avg. per item', _avgPerItem.toStringAsFixed(1), '424242'),
                    pw.SizedBox(width: 8),
                    _pdfSummaryCard('Safe items', '$_safeItems', '388E3C'),
                  ],
                ),
                pw.SizedBox(height: 24),
                pw.Text(
                  'ITEM FREQUENCY',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('9E9E9E'),
                    letterSpacing: 1.2,
                  ),
                ),
                pw.SizedBox(height: 12),
                if (sortedItems.isEmpty)
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(20),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('F5F5F5'),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Center(
                      child: pw.Text('No tracking data yet',
                          style: pw.TextStyle(color: PdfColors.grey)),
                    ),
                  )
                else
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColor.fromHex('E0E0E0')),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: pw.BoxDecoration(
                            color: PdfColor.fromHex('3F3D8F'),
                            borderRadius: const pw.BorderRadius.only(
                              topLeft: pw.Radius.circular(8),
                              topRight: pw.Radius.circular(8),
                            ),
                          ),
                          child: pw.Row(
                            children: [
                              pw.Expanded(
                                flex: 3,
                                child: pw.Text('Item Name',
                                    style: pw.TextStyle(
                                        color: PdfColors.white,
                                        fontWeight: pw.FontWeight.bold,
                                        fontSize: 11)),
                              ),
                              pw.Expanded(
                                child: pw.Text('Times Tracked',
                                    textAlign: pw.TextAlign.center,
                                    style: pw.TextStyle(
                                        color: PdfColors.white,
                                        fontWeight: pw.FontWeight.bold,
                                        fontSize: 11)),
                              ),
                              pw.Expanded(
                                child: pw.Text('Status',
                                    textAlign: pw.TextAlign.center,
                                    style: pw.TextStyle(
                                        color: PdfColors.white,
                                        fontWeight: pw.FontWeight.bold,
                                        fontSize: 11)),
                              ),
                            ],
                          ),
                        ),
                        ...sortedItems.asMap().entries.map((e) {
                          final idx = e.key;
                          final isLast = idx == sortedItems.length - 1;
                          final entry = e.value;
                          final name = _displayNames[entry.key] ?? entry.key;
                          final count = entry.value;
                          final isRisk = count >= 5;
                          final bgColor = idx % 2 == 0
                              ? PdfColors.white
                              : PdfColor.fromHex('F8F8FF');
                          return pw.Container(
                            decoration: pw.BoxDecoration(
                              color: bgColor,
                              border: isLast
                                  ? null
                                  : pw.Border(
                                      bottom: pw.BorderSide(
                                        color: PdfColor.fromHex('E0E0E0'),
                                        width: 0.5,
                                      ),
                                    ),
                            ),
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: pw.Row(
                              children: [
                                pw.Expanded(
                                  flex: 3,
                                  child: pw.Text(name,
                                      style: const pw.TextStyle(fontSize: 11)),
                                ),
                                pw.Expanded(
                                  child: pw.Text('${count}x',
                                      textAlign: pw.TextAlign.center,
                                      style: pw.TextStyle(
                                          fontSize: 11,
                                          fontWeight: pw.FontWeight.bold,
                                          color: isRisk
                                              ? PdfColor.fromHex('D32F2F')
                                              : PdfColor.fromHex('388E3C'))),
                                ),
                                pw.Expanded(
                                  child: pw.Text(
                                      isRisk ? 'At Risk' : 'Safe',
                                      textAlign: pw.TextAlign.center,
                                      style: pw.TextStyle(
                                          fontSize: 11,
                                          color: isRisk
                                              ? PdfColor.fromHex('D32F2F')
                                              : PdfColor.fromHex('388E3C'))),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                pw.SizedBox(height: 24),
                pw.Divider(color: PdfColor.fromHex('E0E0E0')),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'BluePixels Smartlocator CT125',
                      style: pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'SmartLocator_Report_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'SmartLocator Report — $dateStr',
      );
    } catch (e) {
      debugPrint('[PDF] error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF export failed: $e')),
        );
      }
    }
  }

  // ── PDF helper ────────────────────────────────────────────────────────────
  pw.Widget _pdfSummaryCard(String label, String value, String hexColor) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: PdfColor.fromHex('E0E0E0')),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label,
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.SizedBox(height: 4),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex(hexColor))),
          ],
        ),
      ),
    );
  }

  // ── UPDATED _buildWeeklyCards — blue RESET, red warning, PDF REPORT ───────
  // ── Paste this to REPLACE _buildWeeklyCards() in dashboard_page.dart ────
  Widget _buildWeeklyCards() {
    return Column(
      children: [
        // ── RESET card — lavender/purple theme matching Image 1 ────────────
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEEEDFA),          // soft lavender background
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFB0ADDE), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Badge — purple pill like Image 1
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B78C8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('RESET',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.8)),
              ),
              const SizedBox(height: 10),
              const Text('Start fresh, track smarter',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 20, 13, 231))),
              const SizedBox(height: 6),
              const Text(
                'Do you want to wipe the slate clean and kick off a brand new tracking progress?',
                style: TextStyle(
                    fontSize: 13, color: Color.fromARGB(255, 35, 106, 212), height: 1.4),
              ),
              const SizedBox(height: 8),
              Divider(color: const Color(0xFFB0ADDE).withOpacity(0.6)),
              const SizedBox(height: 6),
              // Warning text — red italic
              const Text(
                'This will permanently clear all current tracking data. '
                "Make sure you've saved your report first!",
                style: TextStyle(
                    fontSize: 12,
                    color: Color.fromARGB(255, 61, 100, 216),
                    fontStyle: FontStyle.italic,
                    height: 1.4),
              ),
              const SizedBox(height: 14),
              Row(children: [
                OutlinedButton(
                  onPressed: _showResetConfirmDialog,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF3F3D8F)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                  ),
                  child: const Text('Yes, reset now',
                      style: TextStyle(
                          color: Color(0xFF3F3D8F),
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                  ),
                  child: Text('Not yet',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 13)),
                ),
              ]),
            ],
          ),
        ),

        // ── PDF REPORT card — green theme unchanged ───────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF81C784), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF81C784),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('PDF REPORT',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.8)),
              ),
              const SizedBox(height: 10),
              const Text('Save this item tracking analysis',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B5E20))),
              const SizedBox(height: 6),
              const Text(
                'Keep a record of your tracking habits! Save this current dashboard '
                'as a PDF. Keep it as an essential evidence to look back on.',
                style: TextStyle(
                    fontSize: 13, color: Color(0xFF2E7D32), height: 1.4),
              ),
              const SizedBox(height: 8),
              Divider(color: const Color(0xFF81C784).withOpacity(0.5)),
              const SizedBox(height: 6),
              const Text(
                'Includes bar chart, risk scores, streak data and alert history.',
                style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF388E3C),
                    fontStyle: FontStyle.italic,
                    height: 1.4),
              ),
              const SizedBox(height: 14),
              Row(children: [
                OutlinedButton(
                  onPressed: () => _exportToPdf(),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF388E3C)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                  ),
                  child: const Text('Yes, save as PDF',
                      style: TextStyle(
                          color: Color(0xFF388E3C),
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                  ),
                  child: Text('Maybe later',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 13)),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Stack(
            children: [    
          Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSummaryCards(),
                              const SizedBox(height: 20),
                              _buildChartSection(),
                              const SizedBox(height: 16),
                              if (_activeAlertThreshold != null)
                                _buildAlertBox(_activeAlertThreshold!),
                              const SizedBox(height: 16),
                              _buildWeeklyCards(),
                              const SizedBox(height: 24),
                              _buildTipsSection(),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
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

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.transparent,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                      spreadRadius: 1)
                ],
              ),
              child: const Icon(Icons.arrow_back,
                  color: Color(0xFF1565C0), size: 22),
            ),
          ),
          const SizedBox(width: 16),
          Builder(builder: (context) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Text('Dashboard',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF424242)));
          }),
          const Spacer(),
          ListenableBuilder(
            listenable: BleService(),
            builder: (_, __) => EspStatusBadge(status: bleToEspStatus(BleService())),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _loadData,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                      spreadRadius: 1)
                ],
              ),
              child: const Icon(Icons.refresh,
                  color: Color(0xFF1565C0), size: 22),
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary cards ─────────────────────────────────────────────────────────
  Widget _buildSummaryCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Builder(builder: (context) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Text('TRACKING ANALYSIS',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : const Color(0xFF9E9E9E),
                    letterSpacing: 1.2));
          }),
        const SizedBox(height: 12),
        Row(
          children: [
            _summaryCard('Total tracked', '$_totalTracked',
                color: Colors.black87),
            const SizedBox(width: 10),
            _summaryCard('Items at risk', '${_itemsAtRisk.length}',
                color: Colors.red.shade600),
            const SizedBox(width: 10),
            _summaryCard('Avg. per item', _avgPerItem.toStringAsFixed(1),
                color: Colors.black87),
            const SizedBox(width: 10),
            _summaryCard('Safe items', '$_safeItems',
                color: Colors.green.shade600),
          ],
        ),
      ],
    );
  }

  Widget _summaryCard(String label, String value, {required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1A2F4A)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 6,
                spreadRadius: 1)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white60 : Colors.grey.shade600,
                  fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color == Colors.black87
                    ? (Theme.of(context).brightness == Brightness.dark
                        ? Colors.white : Colors.black87)
                    : color)),
          ],
        ),
      ),
    );
  }

  // ── Chart section ─────────────────────────────────────────────────────────
  Widget _buildChartSection() {
    final items = _itemFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final yMax = _currentCap;
    final yStep = yMax <= 5 ? 1 : yMax <= 10 ? 2 : 5;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1A2F4A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              spreadRadius: 2)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _legendDot(const Color(0xFF3F3D8F), 'Tracked'),
              const SizedBox(width: 16),
              _legendDot(const Color(0xFFB0ADDE), 'Not tracked'),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEDFA),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Cap: $yMax',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF3F3D8F),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text('No tracking data yet',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
           Stack(
  clipBehavior: Clip.none,
  children: [
    SizedBox(
      height: 260,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildYAxis(yMax, yStep),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: items.length <= 4
                        ? null
                        : items.length * 72.0,
                    child: Stack(
                      children: [
                        _buildGridLines(yMax, yStep),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: items.map((entry) {
                            return _buildStackedBar(
                              entry.key,
                              entry.value,
                              items.length,
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),

    // ✅ Tooltip rendered at chart level — never covered
    if (_selectedBar != null && _selectedBarType != null)
      Positioned(
        top: 0,
        left: 40,
        child: _buildTooltip(
          _selectedBar!,
          _itemFrequency[_selectedBar!] ?? 0,
          (_currentCap - (_itemFrequency[_selectedBar!] ?? 0)).clamp(0, _currentCap),
          _selectedBarType!,
        ),
      ),
  ],
), 
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 14, height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
        style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white60 : Colors.grey.shade700)),
      ],
    );
  }

  Widget _buildYAxis(int yMax, int yStep) {
    final labels = <int>[];
    for (int i = 0; i <= yMax; i += yStep) {
      labels.add(i);
    }
    return SizedBox(
      width: 28,
      child: Column(
        children: [
          const SizedBox(height: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: labels.reversed.map((v) {
                return Text('$v',
                  style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white54 : Colors.grey.shade500));
              }).toList(),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildGridLines(int yMax, int yStep) {
    final lineCount = (yMax / yStep).floor() + 1;
    return Positioned.fill(
      child: Column(
        children: [
          const SizedBox(height: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(lineCount, (i) {
                return Container(height: 1, 
                  color: Colors.grey.shade200.withOpacity(
                    Theme.of(context).brightness == Brightness.dark ? 0.15 : 0.8));
              }),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildStackedBar(String itemName, int tracked, int itemCount) {
    final double barWidth = itemCount <= 4 ? 52.0 : 60.0;
    final cap = _currentCap;
    final notTracked = (cap - tracked).clamp(0, cap);

    const double barHeight = 200.0;
    final double trackedH = (tracked > 0 && cap > 0)
        ? (tracked / cap * barHeight).clamp(0.0, barHeight)
        : 0.0;
    final double notTrackedH = (barHeight - trackedH).clamp(0.0, barHeight);
    final double safeTrackedH = trackedH.isNaN ? 0.0 : trackedH;
    final double safeNotTracked =
        notTrackedH.isNaN ? barHeight : notTrackedH;

    final isSelected = _selectedBar == itemName;
    final selType = _selectedBarType;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                width: barWidth,
                height: barHeight,
                child: ClipRect(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (safeNotTracked > 0)
                        GestureDetector(
                          onTap: () => setState(() {
                            if (isSelected && selType == 'not_tracked') {
                              _selectedBar = null;
                              _selectedBarType = null;
                            } else {
                              _selectedBar = itemName;
                              _selectedBarType = 'not_tracked';
                            }
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: barWidth,
                            height: safeNotTracked,
                            decoration: BoxDecoration(
                              color: (isSelected && selType == 'not_tracked')
                                  ? const Color(0xFFB0ADDE)
                                  : const Color(0xFFD4D2ED),
                              borderRadius: safeTrackedH == 0
                                  ? BorderRadius.circular(6)
                                  : const BorderRadius.vertical(
                                      top: Radius.circular(6)),
                            ),
                          ),
                        ),
                      if (safeTrackedH > 0)
                        GestureDetector(
                          onTap: () => setState(() {
                            if (isSelected && selType == 'tracked') {
                              _selectedBar = null;
                              _selectedBarType = null;
                            } else {
                              _selectedBar = itemName;
                              _selectedBarType = 'tracked';
                            }
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: barWidth,
                            height: safeTrackedH,
                            decoration: BoxDecoration(
                              color: (isSelected && selType == 'tracked')
                                  ? const Color(0xFF2C2A7A)
                                  : const Color(0xFF3F3D8F),
                              borderRadius: safeNotTracked == 0
                                  ? BorderRadius.circular(6)
                                  : const BorderRadius.vertical(
                                      bottom: Radius.circular(6)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: barWidth,
                height: 32,
                child: Text(
                  _displayNames[itemName] ?? itemName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? const Color(0xFF3F3D8F)
                        : (Theme.of(context).brightness == Brightness.dark
                            ? Colors.white54 : Colors.grey.shade700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTooltip(
      String item, int tracked, int notTracked, String type) {
    final isTracked = type == 'tracked';
    final dotColor = isTracked
        ? const Color(0xFF3F3D8F)
        : const Color(0xFFB0ADDE);
    final label =
        isTracked ? 'Tracked: ${tracked}x' : 'Not tracked: ${notTracked}x';

    return Container(
      constraints: const BoxConstraints(maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1B3A),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_displayNames[item] ?? item,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                    color: dotColor,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Alert box ─────────────────────────────────────────────────────────────
  Widget _buildAlertBox(int threshold) {
    final itemNames = _itemsExceedingThreshold(threshold);
    final nameStr = itemNames.length == 1
        ? itemNames.first
        : itemNames.take(2).join(' and ') +
            (itemNames.length > 2 ? ' and others' : '');

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEF9A9A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFC62828), size: 18),
              const SizedBox(width: 8),
              const Text('High frequency alert',
                  style: TextStyle(
                      color: Color(0xFFC62828),
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$nameStr ${itemNames.length > 1 ? "have" : "has"} been tracked $threshold+ times. '
            'These items may be at higher risk of being misplaced — stay alert!',
            style: const TextStyle(
                color: Color(0xFFB71C1C), fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              setState(() => _dismissedThresholds.add(threshold));
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF9A9A)),
              ),
              child: const Text('Got it, will do',
                  style: TextStyle(
                      color: Color(0xFFC62828),
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tips section ──────────────────────────────────────────────────────────
  Widget _buildTipsSection() {
    final tips = [
      _TipData(
        title: '1. Daily hostel habits',
        points: [
          'Keep essential items (keys, wallet, ID card) in a fixed spot in your bag or room.',
          'Do a quick "3-item check" (phone, wallet, keys) before leaving your room.',
          'Avoid placing items on shared tables or common areas.',
        ],
        code: null,
        extraLabel: null,
      ),
      _TipData(
        title: '2. Room & dorm safety',
        points: [
          'Always store items in the same drawer, shelf, or pocket.',
          "Don't leave belongings near the door or window.",
          'Keep important items close when your roommate or others are around.',
        ],
        code: null,
        extraLabel: null,
      ),
      _TipData(
        title: '3. High-risk locations in hostel',
        points: ['Be careful in:'],
        bullets: ["Friends' room", 'Study room', 'Laundry area', 'Common lounge'],
        extraLabel: '👉 Suggested tip:',
        code: 'Always check your seat and table before leaving.',
      ),
      _TipData(
        title: '4. Movement between floors',
        points: [
          'Be extra alert when moving between floors.',
          'Items are easily forgotten when switching locations quickly.',
        ],
        extraLabel: '👉 Tip:',
        code: 'Double-check your belongings when moving between floors.',
        bullets: null,
      ),
      _TipData(
        title: '5. SmartLocator usage tips',
        points: [
          'Calibrate your SmartLocator on the correct floor for accurate detection.',
          'Keep the SmartLocator attached to your item at all times when tracking.',
          'Check the app regularly when you are moving to different floors.',
          'Charge the SmartLocator when the battery is low to avoid signal loss.',
        ],
        code: null,
        extraLabel: null,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Personal Items Care Recommendations',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF3F3D8F))),
        const SizedBox(height: 12),
        ...tips.asMap().entries.map((e) => _buildTipCard(e.key, e.value)),
      ],
    );
  }

  Widget _buildTipCard(int index, _TipData tip) {
    final isOpen = _expanded[index];
    return GestureDetector(
      onTap: () => setState(() => _expanded[index] = !isOpen),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1A2F4A) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOpen
                ? const Color(0xFF3F3D8F).withOpacity(0.6)
                : (Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.15)
                    : const Color(0xFFE0E0E0))),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                spreadRadius: 1)
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tip.title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isOpen
                            ? (Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF9FA8DA) : const Color(0xFF3F3D8F))
                            : (Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF9FA8DA) : const Color(0xFF424242))),
                    ),
                  ),
                  Icon(
                    isOpen ? Icons.remove : Icons.add,
                    color: const Color(0xFF3F3D8F),
                    size: 20,
                  ),
                ],
              ),
            ),
            if (isOpen)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        height: 1,
                        color: const Color(0xFFEEEDFA),
                        margin: const EdgeInsets.only(bottom: 12)),
                    ...tip.points.map((p) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!p.endsWith(':'))
                                const Text('• ',
                                    style: TextStyle(
                                        color: Color(0xFF3F3D8F),
                                        fontWeight: FontWeight.bold)),
                              Expanded(
                                child: Text(p,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Theme.of(context).brightness == Brightness.dark
                                          ? Colors.white70 : Colors.grey.shade800,
                                        height: 1.4,
                                        fontStyle: p.endsWith(':')
                                            ? FontStyle.italic
                                            : FontStyle.normal)),
                              ),
                            ],
                          ),
                        )),
                    if (tip.bullets != null)
                      ...tip.bullets!.map((b) => Padding(
                            padding:
                                const EdgeInsets.only(left: 12, bottom: 4),
                            child: Row(
                              children: [
                                const Text('* ',
                                    style: TextStyle(
                                        color: Color(0xFF3F3D8F),
                                        fontWeight: FontWeight.bold)),
                                Text(b,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Theme.of(context).brightness == Brightness.dark
                                            ? Colors.white70 : Colors.grey.shade800,)),
                              ],
                            ),
                          )),
                    if (tip.extraLabel != null) ...[
                      const SizedBox(height: 8),
                      Text(tip.extraLabel!,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF3F3D8F))),
                      const SizedBox(height: 6),
                    ],
                    if (tip.code != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0EFF8),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: const Color(0xFFD4D2ED)),
                        ),
                        child: Text(
                          tip.code!,
                          style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF3F3D8F),
                              fontStyle: FontStyle.italic,
                              height: 1.4),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Data class for tips ───────────────────────────────────────────────────────
class _TipData {
  final String title;
  final List<String> points;
  final List<String>? bullets;
  final String? extraLabel;
  final String? code;

  const _TipData({
    required this.title,
    required this.points,
    this.bullets,
    this.extraLabel,
    this.code,
  });
}

EspStatus bleToEspStatus(BleService ble) {
  if (ble.isConnected) return EspStatus.connected;
  if (ble.isScanning) return EspStatus.connecting;
  return EspStatus.disconnected;
}