import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

// --- AUDIO MANAGER ---

class AudioManager {

  AudioPlayer? _completionPlayer;
  AudioPlayer? _timerEndPlayer;
  bool _isCompletionPreloaded = false;
  bool _isTimerEndPreloaded = false;

  // Audio configuration
  bool _completionEnabled = true;
  String _completionAsset = 'audio/pomodoro.mp3';
  String _timerEndAsset = 'audio/timer_end.mp3';
  double _completionVolume = 0.8;
  double _timerEndVolume = 0.8;

  Future<void> initialize() async {
    try {
      // Initialize completion player
      if (_completionPlayer == null) {
        _completionPlayer = AudioPlayer();
        await _completionPlayer!.setPlayerMode(PlayerMode.lowLatency);
        await _completionPlayer!.setReleaseMode(ReleaseMode.release);
        await _completionPlayer!.setVolume(_completionVolume);
      }

      // Initialize timer end player
      if (_timerEndPlayer == null) {
        _timerEndPlayer = AudioPlayer();
        await _timerEndPlayer!.setPlayerMode(PlayerMode.lowLatency);
        await _timerEndPlayer!.setReleaseMode(ReleaseMode.release);
        await _timerEndPlayer!.setVolume(_timerEndVolume);
      }

      // Preload completion and timer end sounds for instant playback
      await preloadCompletionSound();
      await preloadTimerEndSound();

      debugPrint('AudioManager initialized successfully');
    } catch (e) {
      debugPrint('AudioManager initialization error: $e');
    }
  }

  Future<void> loadAudioConfig() async {
    try {
      final raw = await rootBundle.loadString('assets/audio/audio_config.json');
      final json = jsonDecode(raw);
      debugPrint('Loaded raw audio config: $raw');

      if (json is Map<String, dynamic>) {
        _completionEnabled = (json['completionEnabled'] as bool?) ?? true;
        _completionAsset = (json['completionAsset'] as String?) ?? 'audio/pomodoro.mp3';
        final completionVol = (json['completionVolume'] as num?)?.toDouble() ?? 0.8;
        _completionVolume = completionVol.clamp(0.0, 1.0);

        debugPrint('Audio config loaded - completion: $_completionEnabled ($_completionAsset)');
      }
    } catch (e) {
      debugPrint('Audio config load error: $e');
      // Use defaults
    }
  }

  Future<void> preloadCompletionSound() async {
    if (_completionPlayer == null || _isCompletionPreloaded || !_completionEnabled) return;

    try {
      await _completionPlayer!.setSource(AssetSource(_completionAsset));
      _isCompletionPreloaded = true;
      debugPrint('Completion sound preloaded successfully');
    } catch (e) {
      debugPrint('Completion sound preload error: $e');
      _isCompletionPreloaded = false;
    }
  }

  Future<void> preloadTimerEndSound() async {
    if (_timerEndPlayer == null || _isTimerEndPreloaded) return;

    try {
      await _timerEndPlayer!.setSource(AssetSource(_timerEndAsset));
      _isTimerEndPreloaded = true;
      debugPrint('Timer end sound preloaded successfully');
    } catch (e) {
      debugPrint('Timer end sound preload error: $e');
      _isTimerEndPreloaded = false;
    }
  }

  Future<void> playCompletionSound() async {
    if (!_completionEnabled || _completionPlayer == null) return;

    try {
      await _completionPlayer!.play(AssetSource(_completionAsset));
      debugPrint('Completion sound played');
    } catch (e) {
      debugPrint('Completion sound play error: $e');
    }
  }

  Future<void> stopCompletionSound() async {
    if (_completionPlayer == null) return;

    try {
      await _completionPlayer!.stop();
      debugPrint('Completion sound stopped');
    } catch (e) {
      debugPrint('Completion sound stop error: $e');
    }
  }

  Future<void> playTimerEndSound() async {
    // Ensure player is initialized
    if (_timerEndPlayer == null) {
      debugPrint('Initializing timer end player...');
      try {
        _timerEndPlayer = AudioPlayer();
        await _timerEndPlayer!.setPlayerMode(PlayerMode.lowLatency);
        await _timerEndPlayer!.setReleaseMode(ReleaseMode.release);
        await _timerEndPlayer!.setVolume(_timerEndVolume);
        debugPrint('Timer end player initialized');
      } catch (e) {
        debugPrint('Timer end player init error: $e');
        return;
      }
    }

    try {
      debugPrint('Playing timer end sound from asset: $_timerEndAsset');
      // Play directly - audioplayers will handle loading if needed
      await _timerEndPlayer!.play(AssetSource(_timerEndAsset));
      debugPrint('Timer end sound played successfully');
    } catch (e) {
      debugPrint('Timer end sound play error: $e');
      // Try to preload and play again if first attempt failed
      try {
        debugPrint('Attempting to preload and play timer end sound...');
        await _timerEndPlayer!.setSource(AssetSource(_timerEndAsset));
        await _timerEndPlayer!.play(AssetSource(_timerEndAsset));
        debugPrint('Timer end sound played after preload');
      } catch (e2) {
        debugPrint('Timer end sound play retry error: $e2');
      }
    }
  }

  Future<void> stopTimerEndSound() async {
    if (_timerEndPlayer == null) return;

    try {
      await _timerEndPlayer!.stop();
      debugPrint('Timer end sound stopped');
    } catch (e) {
      debugPrint('Timer end sound stop error: $e');
    }
  }

  Future<void> setCompletionVolume(double volume) async {
    _completionVolume = volume.clamp(0.0, 1.0);
    if (_completionPlayer != null) {
      await _completionPlayer!.setVolume(_completionVolume);
    }
  }

  void setCompletionEnabled(bool enabled) {
    _completionEnabled = enabled;
  }

  Future<void> dispose() async {
    try {
      await _completionPlayer?.dispose();
      await _timerEndPlayer?.dispose();
      _completionPlayer = null;
      _timerEndPlayer = null;
      _isCompletionPreloaded = false;
      _isTimerEndPreloaded = false;
      debugPrint('AudioManager disposed');
    } catch (e) {
      debugPrint('AudioManager dispose error: $e');
    }
  }
}

// --- ANALOG CLOCK PAINTER ---

class AnalogClockPainter extends CustomPainter {
  final DateTime currentTime;
  final ThemeData theme;

  AnalogClockPainter({required this.currentTime, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Colors based on theme
    final bgColor = theme.colorScheme.surface;
    final textColor = theme.colorScheme.onSurface.withOpacity(0.7);
    final trackColor = theme.colorScheme.onSurface.withOpacity(0.2);
    final hourColor = theme.colorScheme.primary;
    final minuteColor = theme.colorScheme.secondary;
    final secondColor = Colors.greenAccent;

    // Draw concentric tracks (scaled based on Python radii: 60, 100, 140)
    final trackRadii = [60.0, 100.0, 140.0];
    final maxTrackRadius = trackRadii.last;
    final scale = (radius - 50) / maxTrackRadius; // Leave space for numbers outside

    for (final trackRadius in trackRadii) {
      final scaledRadius = trackRadius * scale;
      final paint = Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(center, scaledRadius, paint);
    }

    // Draw numbers 1-12 outside the largest track
    final numberRadius = maxTrackRadius * scale + 30; // Outside largest track
    for (int i = 1; i <= 12; i++) {
      final angle = (i * 30 - 90) * pi / 180; // Same logic as Python code
      final x = center.dx + numberRadius * cos(angle);
      final y = center.dy + numberRadius * sin(angle);

      final textSpan = TextSpan(
        text: i.toString(),
        style: TextStyle(
          color: textColor,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFamily: 'SpaceMono',
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: ui.TextDirection.ltr,
      );

      textPainter.layout();
      final textOffset = Offset(
        x - textPainter.width / 2,
        y - textPainter.height / 2,
      );

      textPainter.paint(canvas, textOffset);
    }

    // Calculate hand angles (same as Python logic)
    final secondAngle = (currentTime.second * 6 - 90) * pi / 180;
    final minuteAngle = (currentTime.minute * 6 - 90) * pi / 180;
    final hourAngle = ((currentTime.hour % 12) * 30 + (currentTime.minute / 2) - 90) * pi / 180;

    // Draw hands with bulbs at the end
    _drawHandWithBulb(canvas, center, hourAngle, trackRadii[0] * scale, hourColor, 6);
    _drawHandWithBulb(canvas, center, minuteAngle, trackRadii[1] * scale, minuteColor, 4);
    _drawHandWithBulb(canvas, center, secondAngle, trackRadii[2] * scale, secondColor, 2);

    // Draw center hub
    final hubPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 5, hubPaint);

    final hubStrokePaint = Paint()
      ..color = theme.colorScheme.onSurface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, 5, hubStrokePaint);
  }

  void _drawHandWithBulb(Canvas canvas, Offset center, double angle, double radius, Color color, double width) {
    final endPoint = Offset(
      center.dx + radius * cos(angle),
      center.dy + radius * sin(angle),
    );

    // Draw hand line
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, endPoint, linePaint);

    // Draw bulb at the end
    final bulbPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(endPoint, width / 2 + 3, bulbPaint);
  }

  @override
  bool shouldRepaint(AnalogClockPainter oldDelegate) {
    return oldDelegate.currentTime != currentTime ||
           oldDelegate.theme.brightness != theme.brightness;
  }
}

// --- ENUMS FOR STATE MANAGEMENT ---

enum AppMode { clock, customTimer, pomodoro, quickTimer }
enum ClockType { digital, analog }

// --- MAIN APPLICATION WIDGET ---

void main() {
  runApp(const KlokApp());
}

class KlokApp extends StatefulWidget {
  const KlokApp({super.key});

  @override
  State<KlokApp> createState() => _KlokAppState();
}

class _KlokAppState extends State<KlokApp> {
  bool _isLightMode = false;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isLightMode = prefs.getBool('isLightMode') ?? false;
    });
  }

  Future<void> _toggleTheme(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLightMode', value);
    setState(() {
      _isLightMode = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Klok',
      debugShowCheckedModeBanner: false,
      themeMode: _isLightMode ? ThemeMode.light : ThemeMode.dark,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Inter',
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: Colors.grey,
          secondary: Colors.grey,
          surface: Colors.white,
          background: Colors.white,
          onBackground: Colors.black,
          onSurface: Colors.black,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        fontFamily: 'Inter',
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: Colors.grey,
          secondary: Colors.grey,
          surface: Colors.black,
          background: Colors.black,
          onBackground: Colors.white,
          onSurface: Colors.white,
        ),
      ),
      home: KlokHomePage(
        onThemeChanged: _toggleTheme,
        isLightMode: _isLightMode,
      ),
    );
  }
}

class KlokHomePage extends StatefulWidget {
  final Function(bool) onThemeChanged;
  final bool isLightMode;

  const KlokHomePage({
    super.key,
    required this.onThemeChanged,
    required this.isLightMode,
  });

  @override
  State<KlokHomePage> createState() => _KlokHomePageState();
}

class _KlokHomePageState extends State<KlokHomePage> {
  // --- STATE VARIABLES ---
  AppMode _currentMode = AppMode.clock;
  ClockType _clockType = ClockType.digital;
  double _digitalClockScale = 1.0; // Default scale for digital clock
  double _analogClockScale = 1.0;

  // Fullscreen state
  bool _isFullscreen = false;
  bool _showFullscreenUI = false;
  Timer? _hideUITimer;

  // Clock variables
  Timer? _clockTimer;
  DateTime _currentTime = DateTime.now();
  bool _clockRunning = false;

  // Settings
  // Quick Timer
  Timer? _quickTimer;
  Duration _quickTimerDuration = Duration.zero;
  bool _quickTimerRunning = false;

  // Custom Timer variables
  Timer? _countdownTimer;
  Duration _remainingTime = const Duration(minutes: 120);
  final TextEditingController _timerInputController = TextEditingController();
  final TextEditingController _quickTimerInputController = TextEditingController();
  bool _isTimerRunning = false;

  // Pomodoro variables (Set to final as they are static settings)
  final Duration _workDuration = const Duration(minutes: 25);
  final Duration _breakDuration = const Duration(minutes: 5);
  bool _isVibrating = false;
  String _pomodoroPhase = 'Work';

  // Audio
  AudioManager? _audioManager;

  @override
  void initState() {
    super.initState();
    debugPrint('KlokHomePage initState called');

    // Initialize AudioManager
    _audioManager ??= AudioManager();
    _initializeAudio();

    _loadSettings();
    _ensureClockRunning();
    _timerInputController.text = '120';
    
    // Set preferred orientations to support both portrait and landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _ensureClockRunning() {
    // Check if clock timer is running, if not, start it
    if (!_clockRunning || _clockTimer == null || !_clockTimer!.isActive) {
      debugPrint('Clock timer not running, starting...');
      _startClock();
    } else {
      debugPrint('Clock timer already running');
    }
  }

  Future<void> _initializeAudio() async {
    try {
      if (_audioManager == null) return;
      await _audioManager!.initialize();
      await _audioManager!.loadAudioConfig();
      // Preload timer end sound for instant playback
      await _audioManager!.preloadTimerEndSound();
      debugPrint('Audio initialization completed');
    } catch (e) {
      debugPrint('Audio initialization error: $e');
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _clockRunning = false;
    _countdownTimer?.cancel();
    _quickTimer?.cancel();
    _timerInputController.dispose();
    _quickTimerInputController.dispose();
    _hideUITimer?.cancel();

    // Dispose AudioManager
    _audioManager?.dispose();

    // Make sure to cancel any ongoing vibration when widget is disposed
    if (_isVibrating) {
      Vibration.cancel();
      _isVibrating = false;
    }
    // Restore system UI when disposing
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  // --- CLOCK LOGIC ---

  void _startClock() {
    // Prevent multiple timers
    if (_clockRunning) {
      debugPrint('Clock already running, skipping start');
      return;
    }

    // Cancel any existing timer first
    _clockTimer?.cancel();
    _clockRunning = true;

    // Align updates to the system clock so ticks match the second hand precisely
    final now = DateTime.now();
    final millisecondsUntilNextSecond = 1000 - now.millisecond;
    int lastSecond = now.second;

    debugPrint('Starting clock timer, next second in ${millisecondsUntilNextSecond}ms');

    _clockTimer = Timer(
      Duration(milliseconds: millisecondsUntilNextSecond),
      () {
        if (!mounted) {
          debugPrint('Clock timer cancelled - widget not mounted');
          return;
        }

        // First update at exact second boundary
        final initialTime = DateTime.now();
        setState(() {
          _currentTime = initialTime;
          lastSecond = initialTime.second;
        });

        debugPrint('Clock started at: ${initialTime.toString()}');

        // Continue with periodic updates every 50ms for smooth animation
        _clockTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
          if (!mounted) {
            debugPrint('Periodic clock timer cancelled - widget not mounted');
            timer.cancel();
            _clockRunning = false;
            return;
          }

          final currentTime = DateTime.now();

          // Update UI continuously for smooth animation
          setState(() {
            _currentTime = currentTime;
          });
        });
      },
    );
  }


  Future<void> _playCompletionSound() async {
    debugPrint('Playing completion sound via AudioManager');
    // Ensure AudioManager is initialized
    if (_audioManager == null) {
      _audioManager = AudioManager();
      await _initializeAudio();
    }
    await _audioManager?.playCompletionSound();
  }

  // --- TIMER LOGIC ---

  void _startTimer(Duration initialDuration) {
    _remainingTime = initialDuration;
    _isTimerRunning = true;
    _countdownTimer?.cancel();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingTime.inSeconds > 0) {
        setState(() {
          _remainingTime = _remainingTime - const Duration(seconds: 1);
        });
      } else {
        _stopTimer();
        _onTimerFinished();
      }
    });
  }

  void _stopTimer() {
    _countdownTimer?.cancel();
    setState(() {
      _isTimerRunning = false;
    });
  }

  void _resetTimer(Duration initialDuration) {
    _stopTimer();
    setState(() {
      _remainingTime = initialDuration;
    });
  }

  // --- TIMER COMPLETION & NOTIFICATION ---

  Future<void> _onTimerFinished() async {
    debugPrint('Timer finished, playing completion sound');
    try {
      await _performVibration();
      
      if (_currentMode == AppMode.pomodoro) {
        // Use pomodoro completion sound for pomodoro mode
        await _playCompletionSound();
        _switchPomodoroPhase();
      } else {
        // Use timer end sound for custom timer mode
        // Ensure AudioManager is initialized
        if (_audioManager == null) {
          _audioManager = AudioManager();
          await _initializeAudio();
        }
        await _audioManager?.playTimerEndSound();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showCompletionDialog("Timer Done!", "Your timer has finished.");
        });
      }
    } catch (e) {
      debugPrint('Timer completion error: $e');
      // Continue with the normal flow even if audio/vibration fails
      if (_currentMode == AppMode.pomodoro) {
        _switchPomodoroPhase();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showCompletionDialog("Timer Done!", "Your timer has finished.");
        });
      }
    }
  }

  // --- POMODORO LOGIC ---

  void _switchPomodoroPhase() {
    setState(() {
      if (_pomodoroPhase == 'Work') {
        _pomodoroPhase = 'Break';
        _remainingTime = _breakDuration;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showCompletionDialog("Work Done!", "Time for a 5-minute break!");
        });
      } else {
        _pomodoroPhase = 'Work';
        _remainingTime = _workDuration;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showCompletionDialog("Break Done!", "Time to get back to work!");
        });
      }
    });
    _startTimer(_remainingTime);
  }

  void _startPomodoro() {
    setState(() {
      _pomodoroPhase = 'Work';
      _remainingTime = _workDuration;
    });
    _startTimer(_workDuration);
  }

  Widget _buildQuickTimer() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final w = constraints.maxWidth;
        final isLandscape = w > h;
        final timerFontSize = (isLandscape ? h * 0.12 : w * 0.15).clamp(32.0, 72.0);
        final padV = (isLandscape ? h * 0.03 : h * 0.04).clamp(16.0, 40.0);
        final padH = (w * 0.04).clamp(12.0, 24.0);
        final gap = (isLandscape ? h * 0.04 : h * 0.05).clamp(24.0, 48.0);
        final btnGap = (w * 0.03).clamp(12.0, 24.0);
        final textColor = Theme.of(context).colorScheme.onBackground;
        final isLightMode = Theme.of(context).brightness == Brightness.light;
        
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Timer Display - Large, centered text
            Container(
              padding: EdgeInsets.symmetric(vertical: padV, horizontal: padH),
              child: Text(
                _formatDuration(_quickTimerDuration),
                style: TextStyle(
                  fontSize: timerFontSize,
                  fontWeight: FontWeight.w200,
                  color: _quickTimerRunning
                      ? (isLightMode ? Colors.grey[600] : Colors.grey[400])
                      : Colors.redAccent,
                  letterSpacing: 2,
                  height: 1.1,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: gap),
            // Control Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildActionButton(
                  text: _quickTimerRunning ? 'Pause' : 'Resume',
                  color: _quickTimerRunning ? Colors.redAccent : Colors.greenAccent,
                  onPressed: _quickTimerRunning ? _stopQuickTimer : () => _startQuickTimer(_quickTimerDuration),
                ),
                SizedBox(width: btnGap),
                _buildActionButton(
                  text: 'Stop',
                  onPressed: () async {
                    _stopQuickTimer();
                    // Stop timer end sound when stopping
                    try {
                      await _audioManager?.stopTimerEndSound();
                    } catch (e) {
                      debugPrint('Error stopping timer end sound: $e');
                    }
                    setState(() {
                      _currentMode = AppMode.clock;
                    });
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _startQuickTimer(Duration duration) {
    // If already running, just update the duration for resume
    if (_quickTimerRunning && _quickTimer != null) {
      setState(() {
        _quickTimerDuration = duration;
      });
      return;
    }

    // Stop any existing quick timer
    _quickTimer?.cancel();

    setState(() {
      _quickTimerDuration = duration;
      _quickTimerRunning = true;
      _currentMode = AppMode.quickTimer; // Navigate to quick timer screen
    });

    _quickTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        setState(() {
          _quickTimerRunning = false;
        });
        return;
      }

      setState(() {
        _quickTimerDuration = _quickTimerDuration - const Duration(seconds: 1);
      });

      if (_quickTimerDuration.inSeconds <= 0) {
        timer.cancel();
        setState(() {
          _quickTimerRunning = false;
        });
        _onQuickTimerFinished();
      }
    });
  }

  void _stopQuickTimer() {
    _quickTimer?.cancel();
    setState(() {
      _quickTimerRunning = false;
    });
  }

  Future<void> _onQuickTimerFinished() async {
    debugPrint('Quick timer finished - triggering vibration and sound');
    try {
      // Ensure AudioManager is initialized
      if (_audioManager == null) {
        _audioManager = AudioManager();
        await _initializeAudio();
      }
      // Play vibration and timer end sound simultaneously
      await Future.wait([
        _triggerVibration(),
        _audioManager?.playTimerEndSound() ?? Future.value(),
      ]);
    } catch (e) {
      debugPrint('Quick timer completion error: $e');
    }

    // Navigate back to clock mode and show completion notification
    if (mounted) {
      setState(() {
        _currentMode = AppMode.clock;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showQuickTimerCompletionDialog();
      });
    }
  }

  void _showQuickTimerCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final mq = MediaQuery.of(context);
        final sw = mq.size.width;
        final titleFontSize = (sw * 0.055).clamp(18.0, 24.0);
        final contentFontSize = (sw * 0.04).clamp(14.0, 18.0);
        final contentPadding = EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0);
        final onBg = Theme.of(context).colorScheme.onBackground;

        return AlertDialog(
          title: Text(
            'Timer Complete!',
            style: TextStyle(
              color: onBg,
              fontSize: titleFontSize,
            ),
          ),
          titlePadding: contentPadding,
          content: Text(
            'Your quick timer has finished.',
            style: TextStyle(
              color: onBg.withOpacity(0.7),
              fontSize: contentFontSize,
            ),
          ),
          contentPadding: contentPadding,
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          actions: [
            TextButton(
              child: Text(
                'OK',
                style: TextStyle(
                  color: onBg,
                  fontSize: contentFontSize,
                ),
              ),
              onPressed: () async {
                try {
                  await _audioManager?.stopTimerEndSound();
                } catch (e) {
                  debugPrint('Error stopping timer end sound: $e');
                }
                if (mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
          actionsPadding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          insetPadding: EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 24.0,
          ),
        );
      },
    );
  }

  // --- UTILITY WIDGETS ---

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    final hours = twoDigits(duration.inHours);

    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _showCompletionDialog(String title, String content) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final mq = MediaQuery.of(context);
        final sw = mq.size.width;
        final titleFontSize = (sw * 0.055).clamp(18.0, 24.0);
        final contentFontSize = (sw * 0.04).clamp(14.0, 18.0);
        final contentPadding = EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0);
        final onBg = Theme.of(context).colorScheme.onBackground;

        return AlertDialog(
          title: Text(
            title,
            style: TextStyle(
              color: onBg,
              fontSize: titleFontSize,
            ),
          ),
          titlePadding: contentPadding,
          content: Text(
            content,
            style: TextStyle(
              color: onBg.withOpacity(0.7),
              fontSize: contentFontSize,
            ),
          ),
          contentPadding: contentPadding,
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          actions: <Widget>[
            TextButton(
              child: Text(
                'OK',
                style: TextStyle(
                  color: onBg,
                  fontSize: contentFontSize,
                ),
              ),
              onPressed: () async {
                try {
                  await _audioManager?.stopTimerEndSound();
                  await _audioManager?.stopCompletionSound();
                } catch (e) {
                  debugPrint('Error stopping audio: $e');
                }

                if (_isVibrating) {
                  try {
                    await Vibration.cancel();
                  } catch (e) {
                    debugPrint('Error stopping vibration: $e');
                  } finally {
                    _isVibrating = false;
                  }
                }
                if (mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
          actionsPadding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          insetPadding: EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 24.0,
          ),
        );
      },
    );
  }

  // Load settings from shared preferences
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // Settings loaded
  }

  // Save settings to shared preferences
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLightMode', widget.isLightMode);
  }

  // Toggle fullscreen mode
  Future<void> _toggleFullscreen() async {
    setState(() {
      _isFullscreen = !_isFullscreen;
      _showFullscreenUI = !_isFullscreen; // Show UI when exiting fullscreen
    });

    if (_isFullscreen) {
      // Enter fullscreen
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (_showFullscreenUI) {
        _startHideUITimer();
      }
    } else {
      // Exit fullscreen
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      _hideUITimer?.cancel();
    }
  }

  // Start timer to hide UI in fullscreen mode
  void _startHideUITimer() {
    _hideUITimer?.cancel();
    _hideUITimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showFullscreenUI = false;
          // Hide system UI when hiding our UI
          if (_isFullscreen) {
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          }
        });
      }
    });
  }

  // Handle tap in fullscreen mode
  void _handleFullscreenTap() {
    if (!_isFullscreen) return;
    
    setState(() {
      _showFullscreenUI = !_showFullscreenUI;
      if (_showFullscreenUI) {
        _startHideUITimer();
      } else {
        _hideUITimer?.cancel();
      }
    });
  }


  void _showQuickTimerDialog() {
    _quickTimerInputController.text = '5';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final mq = MediaQuery.of(context);
        final sh = mq.size.height;
        final sw = mq.size.width;
        final bottomInset = mq.viewInsets.bottom;
        final isLandscape = sw > sh;
        final availableHeight =
            (sh - mq.padding.top - mq.padding.bottom - bottomInset).clamp(0.0, sh);
        final inputFontSize =
            (isLandscape ? availableHeight * 0.18 : sw * 0.12).clamp(26.0, 56.0);
        final labelFontSize = (sw * 0.04).clamp(12.0, 16.0);
        final spacing =
            (isLandscape ? availableHeight * 0.06 : availableHeight * 0.04).clamp(10.0, 24.0);
        final titleFontSize = (sw * 0.055).clamp(18.0, 24.0);
        final onBg = Theme.of(context).colorScheme.onBackground;
        final contentPadding = EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0);
        final buttonSpacing = 12.0;

        return AlertDialog(
          title: Text(
            'Quick Timer',
            style: TextStyle(color: onBg, fontSize: titleFontSize),
          ),
          titlePadding: contentPadding,
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: sw * 0.85,
              maxHeight: availableHeight * 0.7,
            ),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: contentPadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Enter timer duration (minutes):',
                      style: TextStyle(
                        color: onBg.withOpacity(0.7),
                        fontSize: labelFontSize,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: spacing),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: sw * 0.5),
                      child: TextField(
                        controller: _quickTimerInputController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: inputFontSize,
                          color: onBg,
                          fontWeight: FontWeight.w300,
                        ),
                        decoration: InputDecoration(
                          hintText: '5',
                          hintStyle: TextStyle(
                            color: onBg.withOpacity(0.3),
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    SizedBox(height: spacing),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            Navigator.of(context).pop();
                            _quickTimerInputController.clear();
                          },
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: onBg.withOpacity(0.7),
                              fontSize: labelFontSize,
                            ),
                          ),
                        ),
                        SizedBox(width: buttonSpacing),
                        ElevatedButton(
                          onPressed: () async {
                            final minutes =
                                int.tryParse(_quickTimerInputController.text) ?? 0;
                            if (minutes > 0) {
                              FocusManager.instance.primaryFocus?.unfocus();
                              Navigator.of(context).pop();
                              _quickTimerInputController.clear();
                              await Future.delayed(const Duration(milliseconds: 100));
                              _startQuickTimer(Duration(minutes: minutes));
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                          ),
                          child: const Text('Start Timer'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: const [],
          actionsPadding: EdgeInsets.zero,
          insetPadding: EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 24.0,
          ),
        );
      },
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final mq = MediaQuery.of(context);
            final sh = mq.size.height;
            final sw = mq.size.width;
            final isLandscape = sw > sh;
            final spacing = (isLandscape ? sh * 0.015 : sh * 0.012).clamp(6.0, 16.0);
            final titleStyle = TextStyle(
              color: Theme.of(context).colorScheme.onBackground,
              fontSize: (sw * 0.04).clamp(14.0, 18.0),
            );
            final contentPadding = EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0);

            return AlertDialog(
              title: Text(
                'Settings',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onBackground,
                  fontSize: (sw * 0.055).clamp(18.0, 24.0),
                ),
              ),
              titlePadding: contentPadding,
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: sw * 0.85,
                  maxHeight: sh * 0.6,
                ),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Padding(
                    padding: contentPadding,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          title: Text('Light Mode', style: titleStyle),
                          contentPadding: EdgeInsets.zero,
                          value: widget.isLightMode,
                          onChanged: (value) {
                            widget.onThemeChanged(value);
                            _saveSettings();
                          },
                          activeColor: Colors.blue,
                        ),
                        SizedBox(height: spacing),
                        SwitchListTile(
                          title: Text('Fullscreen Mode', style: titleStyle),
                          contentPadding: EdgeInsets.zero,
                          value: _isFullscreen,
                          onChanged: (value) {
                            Navigator.of(context).pop();
                            _toggleFullscreen();
                          },
                          activeColor: Colors.blue,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Close',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onBackground,
                      fontSize: (sw * 0.04).clamp(14.0, 16.0),
                    ),
                  ),
                ),
              ],
              actionsPadding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              insetPadding: EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 24.0,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildClockView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Get available space accounting for padding and safe areas
        final screenSize = MediaQuery.of(context).size;
        final padding = MediaQuery.of(context).padding;
        final safeHeight = screenSize.height - padding.top - padding.bottom;
        final safeWidth = screenSize.width - padding.left - padding.right;

        final isLandscape = safeWidth > safeHeight;
        final availableWidth = min(constraints.maxWidth, safeWidth);
        final availableHeight = min(constraints.maxHeight, safeHeight);

        final theme = Theme.of(context);
        final iconColor = _isFullscreen ? theme.colorScheme.onBackground : theme.colorScheme.onBackground;

        // Responsive digital clock font sizes based on screen size
        final baseFontSize = availableWidth * 0.06; // 6% of available width for more conservative sizing
        final digitalFontSize = baseFontSize.clamp(20.0, isLandscape ? 36.0 : 32.0);
        final digitalFontWeight = isLandscape ? FontWeight.w200 : FontWeight.w300;

        final TextStyle digitalTextStyle = TextStyle(
          fontSize: digitalFontSize,
          fontWeight: digitalFontWeight,
          color: theme.colorScheme.onBackground,
          letterSpacing: 1.5,
          height: 1.0,
          fontFamily: 'SpaceMono',
        );

        // Responsive padding
        final digitalPadding = EdgeInsets.symmetric(
          horizontal: availableWidth * 0.04, // 4% of width
          vertical: availableHeight * 0.02, // 2% of height
        );

        // Calculate responsive analog clock size
        // Use smaller percentage on very small screens to prevent overflow
        final clockSizeRatio = availableWidth < 360 ? 0.5 : (availableWidth < 600 ? 0.6 : 0.7);
        final maxClockSize = min(availableWidth * clockSizeRatio, availableHeight * 0.6);
        final clockSize = _isFullscreen ? maxClockSize : maxClockSize * 0.8;

        final clockAreaHeight = min(availableHeight * 0.75, availableWidth * 0.85);
        final clockAreaWidth = min(availableWidth * 0.85, clockAreaHeight);

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: clockAreaWidth,
                maxHeight: clockAreaHeight,
              ),
              child: _clockType == ClockType.digital
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: digitalPadding,
                        child: Text(
                          DateFormat('h:mm:ss a').format(_currentTime),
                          style: digitalTextStyle,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : AspectRatio(
                      aspectRatio: 1.0,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: clockSize,
                          height: clockSize,
                          child: CustomPaint(
                            painter: AnalogClockPainter(
                              currentTime: _currentTime,
                              theme: theme,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            if (!_isFullscreen || _showFullscreenUI) ...[
              SizedBox(height: availableHeight * (isLandscape ? 0.01 : 0.03)),
              Padding(
                padding: EdgeInsets.only(top: availableHeight * (isLandscape ? 0 : 0.015)),
                child: IconButton(
              icon: Text(
                _clockType == ClockType.digital ? '◯' : '◉',
                style: TextStyle(
                  fontSize: availableWidth * (isLandscape ? 0.035 : 0.05), // Responsive font size
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                ),
              ),
              tooltip: _clockType == ClockType.digital ? 'Switch to Analog' : 'Switch to Digital',
              onPressed: () {
                final newType = _clockType == ClockType.digital ? ClockType.analog : ClockType.digital;
                debugPrint('Switching clock type from $_clockType to $newType');
                setState(() {
                  _clockType = newType;
                });
                
                // If in fullscreen, hide UI after a delay
                if (_isFullscreen) {
                  _startHideUITimer();
                }
              },
            ),
          ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCustomTimerSetup() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textColor = Theme.of(context).colorScheme.onBackground;
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;

        // Responsive font sizes
        final titleFontSize = (availableWidth * 0.04).clamp(12.0, 20.0);
        final inputFontSize = (availableWidth * 0.1).clamp(32.0, 56.0);

        // Responsive spacing
        final titleSpacing = availableHeight * 0.015;
        final buttonSpacing = availableHeight * 0.03;

        // Responsive TextField width
        final textFieldWidth = (availableWidth * 0.35).clamp(100.0, 180.0);

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'SET TIMER (Minutes)',
              style: TextStyle(fontSize: titleFontSize, color: textColor.withOpacity(0.7)),
            ),
            SizedBox(height: titleSpacing),
            SizedBox(
              width: textFieldWidth,
              child: TextField(
                controller: _timerInputController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: inputFontSize,
                  color: textColor,
                  fontWeight: FontWeight.w300
                ),
                decoration: InputDecoration(
                  hintText: '120',
                  hintStyle: TextStyle(color: textColor.withOpacity(0.3)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            SizedBox(height: buttonSpacing),
        // Start Button
            _buildActionButton(
              text: 'Start Timer',
              onPressed: () {
                final minutes = int.tryParse(_timerInputController.text) ?? 0;
                if (minutes > 0) {
                  _stopQuickTimer(); // Stop any running quick timer
                  setState(() {
                    _remainingTime = Duration(minutes: minutes);
                    _currentMode = AppMode.customTimer;
                  });
                  _startTimer(_remainingTime);
                }
              },
        ),
      ],
        );
      },
    );
  }

  Widget _buildCustomTimer() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;
        final isLandscape = availableWidth > availableHeight;
        final timerFontSize = (availableWidth * (isLandscape ? 0.08 : 0.12)).clamp(32.0, 64.0);
        final buttonSpacing = (availableHeight * 0.04).clamp(16.0, 32.0);
        final buttonHorizontalSpacing = (availableWidth * 0.03).clamp(12.0, 24.0);

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatDuration(_remainingTime),
              style: TextStyle(
                fontSize: timerFontSize,
                fontWeight: FontWeight.w200,
                color: _isTimerRunning ? Colors.grey[400] : Colors.redAccent,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: buttonSpacing),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Stop/Resume Button
            _buildActionButton(
              text: _isTimerRunning ? 'Pause' : 'Resume',
              color: _isTimerRunning ? Colors.redAccent : Colors.greenAccent,
              onPressed: _isTimerRunning ? _stopTimer : () => _startTimer(_remainingTime),
            ),
            SizedBox(width: buttonHorizontalSpacing),
            // Reset Button (Resets to initial 120min or user input)
            _buildActionButton(
              text: 'Reset',
              onPressed: () {
                final minutes = int.tryParse(_timerInputController.text) ?? 120;
                _resetTimer(Duration(minutes: minutes));
              },
            ),
          ],
        ),
      ],
        );
      },
    );
  }

  Widget _buildPomodoroTimer() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLightMode = Theme.of(context).brightness == Brightness.light;
        final textColor = Theme.of(context).colorScheme.onBackground;
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;
        final isLandscape = availableWidth > availableHeight;

        Color phaseColor = _pomodoroPhase == 'Work'
            ? isLightMode ? Colors.black87 : Colors.white.withOpacity(0.8)
            : Colors.tealAccent;

        final phaseFontSize = (availableWidth * (isLandscape ? 0.035 : 0.045)).clamp(14.0, 24.0);
        final timerFontSize = (availableWidth * (isLandscape ? 0.08 : 0.12)).clamp(32.0, 64.0);
        final buttonSpacing = (availableHeight * 0.04).clamp(16.0, 32.0);
        final buttonHorizontalSpacing = (availableWidth * 0.03).clamp(12.0, 24.0);
        final padV = (availableHeight * 0.015).clamp(8.0, 20.0);
        final padH = (availableWidth * 0.04).clamp(12.0, 24.0);

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.symmetric(vertical: padV, horizontal: padH),
              child: Text(
                _pomodoroPhase,
                style: TextStyle(
                  fontSize: phaseFontSize,
                  color: phaseColor,
                  height: 1.2,
                ),
              ),
            ),

            Container(
              padding: EdgeInsets.symmetric(vertical: padV, horizontal: availableWidth * 0.08),
              child: Text(
                _formatDuration(_remainingTime),
                style: TextStyle(
                  fontSize: timerFontSize,
                  fontWeight: FontWeight.w200,
                  color: isLightMode
                      ? Colors.grey[800]
                      : Colors.white.withOpacity(0.7),
                  letterSpacing: 2,
                  height: 1.1,
                ),
              ),
            ),
            SizedBox(height: buttonSpacing),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildActionButton(
              text: _isTimerRunning ? 'Pause' : 'Start/Resume',
              color: _isTimerRunning 
                  ? Colors.redAccent 
                  : (Theme.of(context).brightness == Brightness.light 
                      ? const Color(0xFF8AA624) 
                      : const Color(0xFF1F7D53)),
              onPressed: _isTimerRunning ? _stopTimer : () => _startTimer(_remainingTime),
            ),
            SizedBox(width: buttonHorizontalSpacing),
            _buildActionButton(
              text: 'Skip Phase',
              color: Theme.of(context).brightness == Brightness.light
                  ? const Color(0xFFF14A00)  // Light mode: light red
                  : const Color(0xFFC62300),  // Dark mode: dark red
              onPressed: () {
                _stopTimer();
                _triggerVibration();
                _playCompletionSound();
                _switchPomodoroPhase();
              },
            ),
          ],
        ),
      ],
        );
      },
    );
  }

  // Reusable button style
  Widget _buildActionButton({
    required String text,
    required VoidCallback onPressed,
    Color? color,
  }) {
    color ??= Theme.of(context).colorScheme.onBackground;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        // Using withOpacity for readability
        backgroundColor: color.withOpacity(0.15),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          // Using withOpacity for readability
          side: BorderSide(color: color.withOpacity(0.5)),
        ),
        elevation: 0,
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
      child: Text(text),
    );
  }

  // --- VIBRATION LOGIC ---
  Future<void> _triggerVibration() async {
    await _performVibration();
  }

  Future<void> _performVibration() async {
    try {
      debugPrint('Triggering vibration...');
      bool? hasVibrator = await Vibration.hasVibrator();
      debugPrint('Vibration capabilities - hasVibrator: $hasVibrator');

      // If the device reports no vibrator or returns null, fall back to haptic
      if (hasVibrator != true) {
        debugPrint('No vibrator reported; using haptic fallback');
        try {
          // Use multiple haptic impacts for distinct feedback
          await HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 100));
          await HapticFeedback.heavyImpact();
        } catch (_) {}
        return;
      }

      _isVibrating = true;
      debugPrint('Starting vibration...');

      // Distinct vibration pattern for timer completion: longer duration with pattern
      try {
        // Pattern: immediate start, vibrate 500ms, pause 100ms, vibrate 500ms
        await Vibration.vibrate(pattern: [0, 500, 100, 500]);
        debugPrint('Pattern vibration started successfully');
        return;
      } catch (e) {
        debugPrint('Pattern vibration failed: $e, trying single vibration');
      }

      // Fallback: single longer vibration
      try {
        await Vibration.vibrate(duration: 1000);
        debugPrint('Single vibration started successfully');
        return;
      } catch (e) {
        debugPrint('Single vibration also failed: $e');
      }

      // Final fallback: haptic feedback so user still feels something
      try {
        await HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 100));
        await HapticFeedback.heavyImpact();
      } catch (_) {
        // No-op if haptics also fail
      }
    } catch (e) {
      debugPrint('Vibration error: $e');
      // Last resort haptic feedback attempt
      try {
        await HapticFeedback.heavyImpact();
      } catch (_) {
        // No-op if haptics also fail
      }
    }
  }

  // --- MAIN BUILD METHOD ---

  @override
  Widget build(BuildContext context) {
    Widget mainContent;
    String appBarTitle;
    List<Widget> actions = [];
    final textColor = Theme.of(context).colorScheme.onBackground;

    // This method is no longer needed as we handle gestures in the build method
    Widget buildWithFullscreenGesture(Widget child) => child;

    switch (_currentMode) {
      case AppMode.clock:
        mainContent = _buildClockView();
        appBarTitle = 'Klok';
        actions.addAll([
          // Timer icon (rightmost)
          IconButton(
            icon: Text('⏱︎',
              style: TextStyle(
                fontSize: 20,
                color: textColor,
              ),
            ),
            onPressed: _showQuickTimerDialog,
          ),
          // Settings icon
          IconButton(
            icon: Text('⏣',
              style: TextStyle(
                fontSize: 20,
                color: textColor,
              ),
            ),
            onPressed: _showSettingsDialog,
          ),
          // Pomodoro icon (leftmost)
          IconButton(
            padding: const EdgeInsets.only(left: 8, right: 8, top: 8.5, bottom: 14),
            icon: Transform.translate(
              offset: const Offset(0, -1),
              child: Text('◴',
                style: TextStyle(
                  fontSize: 30,
                  height: 1,
                  color: textColor,
                ),
              ),
            ),
            onPressed: () {
              _stopTimer();
              _stopQuickTimer();
              debugPrint('Switching to pomodoro mode');
              setState(() {
                _currentMode = AppMode.pomodoro;
                _pomodoroPhase = 'Work';
                _remainingTime = _workDuration;
              });
            },
          ),
        ]);
        break;
      case AppMode.customTimer:
        mainContent = _buildCustomTimer();
        appBarTitle = 'Timer';
        actions = [
          IconButton(
            icon: Icon(Icons.close, size: 24, color: textColor),
            onPressed: () async {
              _stopTimer();
              // Stop timer end sound when closing
              try {
                await _audioManager?.stopTimerEndSound();
              } catch (e) {
                debugPrint('Error stopping timer end sound: $e');
              }
              setState(() {
                _currentMode = AppMode.clock;
              });
            },
          ),
        ];
        break;
      case AppMode.pomodoro:
        mainContent = _buildPomodoroTimer();
        appBarTitle = 'Pomodoro';
        actions = [
          IconButton(
            icon: Text(
              '⌞ ⌝',
              style: TextStyle(
                fontSize: 18,
                height: 1.0,
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            tooltip: 'Fullscreen',
            onPressed: _toggleFullscreen,
          ),
        ];
        break;
      case AppMode.quickTimer:
        mainContent = _buildQuickTimer();
        appBarTitle = 'Quick Timer';
        actions = [
          IconButton(
            icon: Text(
              '⌞ ⌝',
              style: TextStyle(
                fontSize: 18,
                height: 1.0,
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            tooltip: 'Fullscreen',
            onPressed: _toggleFullscreen,
          ),
        ];
        break;
    }

    // Build the app bar only if not in fullscreen or if UI is shown in fullscreen
    final appBar = _isFullscreen ? null : AppBar(
      title: _isFullscreen ? null : Container(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 1.0),
        child: Text(
          appBarTitle,
          style: TextStyle(
            fontFamily: 'LexendGiga',
            fontSize: 24,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
            height: 1.1,
            color: textColor,
          ),
        ),
      ),
      backgroundColor: _isFullscreen ? Colors.black.withOpacity(0.5) : null,
      elevation: 0,
      automaticallyImplyLeading: !_isFullscreen,
      leading: _currentMode != AppMode.clock && !_isFullscreen
          ? IconButton(
              icon: Text('ᐊ', 
                style: TextStyle(
                  fontSize: 25, 
                  height: 0.9,
                  color: Theme.of(context).colorScheme.onBackground,
                )
              ),
              onPressed: () async {
                _stopTimer();
                _stopQuickTimer(); // Stop any running quick timer
                // Stop audio when navigating away
                try {
                  await _audioManager?.stopTimerEndSound();
                  await _audioManager?.stopCompletionSound();
                } catch (e) {
                  debugPrint('Error stopping audio: $e');
                }
                // Cancel any ongoing vibration when leaving the screen
                if (_isVibrating) {
                  try {
                    await Vibration.cancel();
                    _isVibrating = false;
                  } catch (e) {
                    debugPrint('Error cancelling vibration: $e');
                  }
                }
                setState(() {
                  _currentMode = AppMode.clock;
                });
              },
            )
          : null,
      actions: _isFullscreen 
          ? []
          : actions,
    );

    Widget scaffold = Scaffold(
      // true when keyboard may appear (Settings/Timer Input); false on Quick Timer countdown to avoid transition overflow
      resizeToAvoidBottomInset: true,
      appBar: appBar,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                // Safety net: scrollable body so content never overflows (landscape, keyboard, small devices)
                Positioned.fill(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                        minWidth: constraints.maxWidth,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: constraints.maxWidth * 0.03,
                              vertical: constraints.maxHeight * 0.01,
                            ),
                            child: mainContent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_isFullscreen && _showFullscreenUI)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: IconButton(
                          icon: Icon(Icons.fullscreen_exit, color: Theme.of(context).colorScheme.onBackground, size: 30),
                          onPressed: _toggleFullscreen,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );

    // Wrap with gesture detector for fullscreen taps if in fullscreen mode
    if (_isFullscreen) {
      return GestureDetector(
        onDoubleTap: _handleFullscreenTap,
        child: Container(
          color: Colors.black,
          child: scaffold,
        ),
      );
    }
    
    return scaffold;
  }
}