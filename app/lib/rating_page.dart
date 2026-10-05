import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'esp_status_badge.dart';
import 'services/ble_service.dart';

class RatingPage extends StatefulWidget {
  const RatingPage({super.key});
  @override
  State<RatingPage> createState() => _RatingPageState();
}

class _RatingPageState extends State<RatingPage> with TickerProviderStateMixin {

  final List<Map<String, dynamic>> _questions = [
    {'question': 'How easy was it to set up and connect your item tracker?', 'options': ['Difficult', 'Normal', 'Easy']},
    {'question': 'Does the real-time tracking information help you keep alert with your items?', 'options': ['No', 'Normal', 'Yes']},
    {'question': 'Was the buzzer alert helpful when your item was moving away?', 'options': ['Bad', 'Normal', 'Good']},
    {'question': 'Do you think using this bluetooth smartlocator help you take care of your personal items?', 'options': ['Bad', 'Normal', 'Good']},
    {'question': 'What feature would you most like to see improved?', 'options': ['Bad', 'Normal', 'Good'], 'isLast': true},
  ];

  int _currentIndex = 0;
  double _sliderValue = 1.0;
  final _commentController = TextEditingController();
  bool _submitted = false;
  bool _isLoading = false;
  final List<double> _savedSliderValues = [1.0, 1.0, 1.0, 1.0, 1.0];
  final List<String> _answers = ['Normal', 'Normal', 'Normal', 'Normal', 'Normal'];
  final _commentFocusNode = FocusNode();
  bool _commentFocused = false;

  int get _emotion => _sliderValue.round();

  Color get _bgColor {
    if (_sliderValue <= 1.0) {
      return Color.lerp(const Color(0xFFFFE0E0), const Color(0xFFFFF8E1), _sliderValue)!;
    } else {
      return Color.lerp(const Color(0xFFFFF8E1), const Color(0xFFE8F5D0), _sliderValue - 1.0)!;
    }
  }

  Color get _faceColor {
    if (_sliderValue <= 1.0) {
      return Color.lerp(const Color(0xFFC0392B), const Color(0xFF8B7355), _sliderValue)!;
    } else {
      return Color.lerp(const Color(0xFF8B7355), const Color(0xFF4A7C2F), _sliderValue - 1.0)!;
    }
  }

  Color get _accentColor => _faceColor;

  String get _selectedOption {
    final opts = _questions[_currentIndex]['options'] as List<String>;
    return opts[_emotion];
  }

  @override
  void initState() {
    super.initState();
    _commentFocusNode.addListener(() {
      setState(() => _commentFocused = _commentFocusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  void _nextQuestion() {
    _answers[_currentIndex] = _selectedOption;
    _savedSliderValues[_currentIndex] = _sliderValue;
    setState(() {
      _currentIndex++;
      _sliderValue = _savedSliderValues[_currentIndex];
    });
  }

  void _prevQuestion() {
    if (_currentIndex == 0) return;
    _answers[_currentIndex] = _selectedOption;
    _savedSliderValues[_currentIndex] = _sliderValue;
    setState(() {
      _currentIndex--;
      _sliderValue = _savedSliderValues[_currentIndex];
    });
  }

  Future<void> _submitFeedback() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
      final user = FirebaseAuth.instance.currentUser;
      final username = user?.displayName ?? user?.email ?? 'anonymous';
      await FirebaseDatabase.instance.ref('feedback/$uid').set({
        'username': username,
        'email': user?.email ?? '',
        'setup_ease': _answers[0],
        'realtime_helpful': _answers[1],
        'buzzer_helpful': _answers[2],
        'overall_helpful': _answers[3],
        'improvement': _answers[4],
        'comment': _commentController.text.trim(),
        'submittedAt': ServerValue.timestamp,
      });
      setState(() { _submitted = true; _isLoading = false; });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) return _buildThankYouPage();

    final isLastQuestion = _questions[_currentIndex]['isLast'] == true;
    final opts = _questions[_currentIndex]['options'] as List<String>;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        color: _bgColor,
        child: SafeArea(
          child: Stack(
            children:[
            Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 16),

                // Top bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: _faceColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _faceColor.withOpacity(0.3), width: 1),
                        ),
                        child: Icon(Icons.close, color: _faceColor, size: 20),
                      ),
                    ),
                    Row(
                      children: List.generate(_questions.length, (i) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _currentIndex ? 20 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _currentIndex ? _faceColor : _faceColor.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    EspStatusBadge(           // ← 换成这个
                      status: BleService().isConnected && BleService().status.item.isNotEmpty
                          ? EspStatus.connected
                          : BleService().isScanning
                              ? EspStatus.connecting
                              : EspStatus.disconnected,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Question
                Text(
                  _questions[_currentIndex]['question'],
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: _faceColor),
                ),

                const SizedBox(height: 32),

                // Face — hidden on last question to give room for comment box
                if (!isLastQuestion)
                  SizedBox(
                    width: 200, height: 160,
                    child: CustomPaint(
                      painter: _SmoothFacePainter(sliderValue: _sliderValue, color: _faceColor),
                    ),
                  ),

                if (!isLastQuestion)
                  const SizedBox(height: 24),

                if (!isLastQuestion) ...[
                  SizedBox(
                    height: 48,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, animation) {
                        final slideIn = Tween<Offset>(
                          begin: Offset(_sliderValue >= 1.0 ? 0.5 : -0.5, 0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
                        return SlideTransition(
                          position: slideIn,
                          child: FadeTransition(opacity: animation, child: child),
                        );
                      },
                      child: Text(
                        _selectedOption.toUpperCase(),
                        key: ValueKey(_selectedOption),
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold,
                            color: _faceColor.withOpacity(0.4), letterSpacing: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: _accentColor.withOpacity(0.5),
                      inactiveTrackColor: _faceColor.withOpacity(0.15),
                      thumbColor: _accentColor,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
                      overlayColor: _accentColor.withOpacity(0.1),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: _sliderValue, min: 0, max: 2,
                      onChanged: (val) => setState(() => _sliderValue = val),
                      onChangeEnd: (val) => setState(() => _sliderValue = val.roundToDouble()),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: opts.map((opt) {
                        final isSelected = _emotion == opts.indexOf(opt);
                        return Text(opt,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? _faceColor : _faceColor.withOpacity(0.4),
                          ));
                      }).toList(),
                    ),
                  ),
                  const Spacer(),
                  _buildNavButtons(isSubmit: false),
                  const SizedBox(height: 32),

                ] else ...[
                  const SizedBox(height: 16),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: _bgColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _commentFocused
                                      ? _faceColor.withOpacity(0.85)
                                      : _faceColor.withOpacity(0.35),
                                  width: _commentFocused ? 2.0 : 1.5,
                                ),
                                boxShadow: _commentFocused
                                    ? [BoxShadow(color: _faceColor.withOpacity(0.15), blurRadius: 8, spreadRadius: 2)]
                                    : [],
                              ),
                              child: TextField(
                                controller: _commentController,
                                focusNode: _commentFocusNode,
                                maxLines: 5,
                                style: TextStyle(color: _faceColor),
                                decoration: InputDecoration(
                                  hintText: 'Write your comment here...',
                                  hintStyle: TextStyle(color: _faceColor.withOpacity(0.4)),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.all(16),
                                  filled: true,
                                  fillColor: Colors.transparent,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildNavButtons(isSubmit: true),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shared nav buttons ────────────────────────────────────────────────────
  Widget _buildNavButtons({required bool isSubmit}) {
    return Row(
      children: [
        if (_currentIndex > 0) ...[
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _prevQuestion,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _accentColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_back, size: 18, color: _accentColor),
                    const SizedBox(width: 8),
                    Text('Back', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _accentColor)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: isSubmit
                  ? (_isLoading ? null : () { _answers[_currentIndex] = _selectedOption; _submitFeedback(); })
                  : _nextQuestion,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: _bgColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                elevation: 0,
              ),
              child: _isLoading && isSubmit
                  ? SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: _bgColor, strokeWidth: 2))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(isSubmit ? 'Submit' : 'Next',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThankYouPage() {
    return Scaffold(
      body: Container(
        color: const Color(0xFFE8F5D0),
        child: SafeArea(
          child: Stack(
          children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 16),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A7C2F).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF4A7C2F).withOpacity(0.3), width: 1),
                        ),
                        child: const Icon(Icons.close, color: Color(0xFF4A7C2F), size: 20),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: 200, height: 160,
                  child: CustomPaint(
                    painter: _SmoothFacePainter(sliderValue: 2.0, color: const Color(0xFF4A7C2F)),
                  ),
                ),
                const SizedBox(height: 40),
                const Text('Thank you for your\nfeedback!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF4A7C2F))),
                const SizedBox(height: 12),
                const Text('We are doing our best to give\nyou the best experience!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Color(0xFF4A7C2F))),
                const Spacer(),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A7C2F),
                      foregroundColor: const Color(0xFFE8F5D0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Go back to the main page',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
            ],  //
        ),
      ),
      ),
    );
  }
}

class _SmoothFacePainter extends CustomPainter {
  final double sliderValue;
  final Color color;
  _SmoothFacePainter({required this.sliderValue, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final cx = size.width / 2;
    final cy = size.height / 2 - 10;
    final t = sliderValue.clamp(0.0, 2.0);

    if (t <= 1.0) {
      final blend = t;
      final eyeW = 52.0 + (58.0 - 52.0) * blend;
      final eyeH = 28.0 + (22.0 - 28.0) * blend;
      final eyeX = 40.0 + (38.0 - 40.0) * blend;
      canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx - eyeX, cy - 10), width: eyeW, height: eyeH),
          Radius.circular(eyeH / 2)), paint);
      canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx + eyeX, cy - 10), width: eyeW, height: eyeH),
          Radius.circular(eyeH / 2)), paint);
      final mouthPaint = Paint()..color = color..strokeWidth = 8..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
      final path = Path();
      path.moveTo(cx - 30, cy + 55.0 + (48.0 - 55.0) * blend - 10);
      path.quadraticBezierTo(cx, cy + 35.0 + (48.0 - 35.0) * blend, cx + 30, cy + 55.0 + (48.0 - 55.0) * blend - 10);
      canvas.drawPath(path, mouthPaint);
    } else {
      final blend = t - 1.0;
      final eyeW = 58.0 + (76.0 - 58.0) * blend;
      final eyeH = 22.0 + (76.0 - 22.0) * blend;
      final eyeX = 38.0 + (45.0 - 38.0) * blend;
      final eyeY = 10.0 + 10.0 * blend;
      canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx - eyeX, cy - eyeY), width: eyeW, height: eyeH),
          Radius.circular(eyeH / 2)), paint);
      canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx + eyeX, cy - eyeY), width: eyeW, height: eyeH),
          Radius.circular(eyeH / 2)), paint);
      final mouthPaint = Paint()..color = color..strokeWidth = 8..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
      final path = Path();
      path.moveTo(cx - 30, cy + 48.0 + (45.0 - 48.0) * blend);
      path.quadraticBezierTo(cx, cy + 48.0 + (70.0 - 48.0) * blend, cx + 30, cy + 48.0 + (45.0 - 48.0) * blend);
      canvas.drawPath(path, mouthPaint);
    }
  }

  @override
  bool shouldRepaint(_SmoothFacePainter old) => old.sliderValue != sliderValue || old.color != color;
}