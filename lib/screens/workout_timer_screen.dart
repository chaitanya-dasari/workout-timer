import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WorkoutTimerScreen extends StatefulWidget {
  const WorkoutTimerScreen({super.key});

  @override
  State<WorkoutTimerScreen> createState() => _WorkoutTimerScreenState();
}

class _WorkoutTimerScreenState extends State<WorkoutTimerScreen> {
  // Timer state
  String phase = "IDLE"; // IDLE -> PREP -> WORK -> REST -> PREP ... -> DONE
  int seconds = 30;
  int workSeconds = 30;
  int restSeconds = 30;
  int totalSets = 10;
  int currentSet = 1;
  bool prepEnabled = true;
  Timer? timer;
  bool isRunning = false;
  final int prepSeconds = 3; // 3-second "get ready" before each WORK

  // Audio players: one for main cues, one dedicated to fast beeps.
  late final AudioPlayer _player;
  late final AudioPlayer _countdownPlayer;

  // Getter: total duration of the current phase.
  int get currentPhaseTotalSeconds {
    switch (phase) {
      case "PREP":
        return prepSeconds;
      case "WORK":
        return workSeconds;
      case "REST":
        return restSeconds;
      default:
        return workSeconds; // IDLE/DONE: show work length by default
    }
  }

  // Getter: progress 1.0 (just started/full) to 0.0 (finished/empty).
  double get currentProgress {
    final int total = currentPhaseTotalSeconds;
    if (total <= 0) return 0;
    final int clampedSeconds = seconds.clamp(0, total);
    return clampedSeconds / total;
  }

  bool get settingsLocked =>
      isRunning || phase == "PREP" || phase == "WORK" || phase == "REST";

  int get _maxAllowedSets {
    final int perSet = workSeconds + restSeconds;
    if (perSet <= 0) return 1;
    final int maxSets = 10800 ~/ perSet; // 3 hours in seconds
    return maxSets < 1 ? 1 : maxSets;
  }

  int get _totalTimeSeconds => totalSets * (workSeconds + restSeconds);

  @override
  void initState() {
    super.initState(); // Always call super so the base class sets up properly.
    _player = AudioPlayer();
    _countdownPlayer = AudioPlayer();
    _countdownPlayer.setReleaseMode(ReleaseMode.stop);
    _countdownPlayer.setVolume(1.0);
    // Preload the countdown sound so subsequent beeps start instantly.
    _countdownPlayer.setSourceAsset('sounds/countdown_beep.mp3');

    // Load saved settings from device storage.
    loadSettings();
  }

  @override
  void dispose() {
    _player.stop();
    _player.dispose();
    _countdownPlayer.stop();
    _countdownPlayer.dispose();
    timer?.cancel();
    super.dispose();
  }

  // Save current settings to device storage.
  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance(); // Access key-value storage.
    await prefs.setInt('workSeconds', workSeconds);
    await prefs.setInt('restSeconds', restSeconds);
    await prefs.setInt('totalSets', totalSets);
    await prefs.setBool('prepEnabled', prepEnabled);
  }

  // Load settings from device storage; if missing, keep defaults.
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final int? savedWork = prefs.getInt('workSeconds');
    final int? savedRest = prefs.getInt('restSeconds');
    final int? savedSets = prefs.getInt('totalSets');
    final bool? savedPrep = prefs.getBool('prepEnabled');
    if (!mounted) return;
    if (savedWork != null || savedRest != null || savedSets != null || savedPrep != null) {
      setState(() {
        workSeconds = savedWork ?? workSeconds;
        restSeconds = savedRest ?? restSeconds;
        totalSets = savedSets ?? totalSets;
        prepEnabled = savedPrep ?? prepEnabled;

        // Sync UI and timer state with loaded values.
        phase = "IDLE";
        seconds = workSeconds;
        currentSet = 1;
        isRunning = false;
      });
    }
  }

  Future<void> playWorkSound() async {
    await _player.stop();
    await _player.play(AssetSource('sounds/work_start.mp3'));
  }

  Future<void> playRestSound() async {
    await _player.stop();
    await _player.play(AssetSource('sounds/rest_start.mp3'));
  }

  Future<void> playDoneSound() async {
    await _player.stop();
    await _player.play(AssetSource('sounds/done.mp3'));
  }

  Future<void> playCountdownBeep() async {
    try {
      // Restart the short countdown beep cleanly each time.
      await _countdownPlayer.stop();
      await _countdownPlayer.play(
        AssetSource('sounds/countdown_beep.mp3'),
        mode: PlayerMode.lowLatency,
      );
    } catch (_) {
      // If audio fails, silently ignore for now.
    }
  }

  void _showLockedMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stop and reset to change settings.')),
    );
  }

  void _showClampedMessage(int maxSets) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Max sets for 3 hours is $maxSets. Value adjusted.')),
    );
  }

  Future<int?> _openNumberPicker({
    required String title,
    required int min,
    required int max,
    required int currentValue,
  }) async {
    int tempValue = currentValue.clamp(min, max);
    final controller = FixedExtentScrollController(initialItem: tempValue - min);

    return showModalBottomSheet<int>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              SizedBox(
                height: 200,
                child: CupertinoPicker(
                  scrollController: controller,
                  itemExtent: 40,
                  onSelectedItemChanged: (index) {
                    tempValue = min + index;
                  },
                  children: List.generate(max - min + 1, (i) {
                    final value = min + i;
                    return Center(child: Text('$value'));
                  }),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, tempValue),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _startWorkPhase() {
    phase = "WORK";
    seconds = workSeconds;
    playWorkSound(); // SET START alert
  }

  Future<void> _selectWorkSeconds() async {
    if (settingsLocked) {
      _showLockedMessage();
      return;
    }
    final picked = await _openNumberPicker(
      title: 'Work (seconds)',
      min: 1,
      max: 300,
      currentValue: workSeconds,
    );
    if (picked != null && picked != workSeconds) {
      setState(() {
        workSeconds = picked;
        final maxSets = _maxAllowedSets;
        if (totalSets > maxSets) {
          totalSets = maxSets;
          _showClampedMessage(maxSets);
        }
        phase = "IDLE";
        seconds = workSeconds;
        currentSet = 1;
        isRunning = false;
      });
      saveSettings();
    }
  }

  Future<void> _selectRestSeconds() async {
    if (settingsLocked) {
      _showLockedMessage();
      return;
    }
    final picked = await _openNumberPicker(
      title: 'Rest (seconds)',
      min: 1,
      max: 300,
      currentValue: restSeconds,
    );
    if (picked != null && picked != restSeconds) {
      setState(() {
        restSeconds = picked;
        final maxSets = _maxAllowedSets;
        if (totalSets > maxSets) {
          totalSets = maxSets;
          _showClampedMessage(maxSets);
        }
        phase = "IDLE";
        seconds = workSeconds;
        currentSet = 1;
        isRunning = false;
      });
      saveSettings();
    }
  }

  Future<void> _selectTotalSets() async {
    if (settingsLocked) {
      _showLockedMessage();
      return;
    }
    final maxSets = _maxAllowedSets;
    final picked = await _openNumberPicker(
      title: 'Total Sets',
      min: 1,
      max: maxSets,
      currentValue: totalSets.clamp(1, maxSets),
    );
    if (picked != null && picked != totalSets) {
      setState(() {
        totalSets = picked;
        phase = "IDLE";
        seconds = workSeconds;
        currentSet = 1;
        isRunning = false;
      });
      saveSettings();
    }
  }

  void startTimer() {
    if (isRunning) return;
    timer?.cancel();

    setState(() {
      phase = prepEnabled ? "PREP" : "WORK";
      seconds = prepEnabled ? prepSeconds : workSeconds;
      isRunning = true;
    });
    if (phase == "PREP") {
      // First beep at the start of prep (for "3").
      playCountdownBeep();
    } else {
      playWorkSound();
    }

    timer = Timer.periodic(
      const Duration(seconds: 1),
      (Timer t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() {
          seconds--;

          if (phase == "PREP") {
            if (seconds > 0 && seconds <= 2) {
              playCountdownBeep(); // Beep at 2 and 1 here (3 was at start).
            }
            if (seconds <= 0) {
              _startWorkPhase();
            }
          } else if (phase == "WORK") {
            if (seconds <= 0) {
              phase = "REST";
              seconds = restSeconds;
              playRestSound(); // REST START alert at WORK -> REST
            }
          } else if (phase == "REST") {
            if (seconds <= 0) {
              currentSet++;
              if (currentSet > totalSets) {
                t.cancel();
                phase = "DONE";
                seconds = 0;
                isRunning = false;
                playDoneSound();
              } else {
                if (prepEnabled) {
                  phase = "PREP";
                  seconds = prepSeconds;
                  playRestSound(); // REST START alert when PREP countdown begins
                  playCountdownBeep();
                } else {
                  _startWorkPhase();
                }
              }
            }
          }
        });
      },
    );
   }

  void pauseTimer() {
    timer?.cancel();
    setState(() {
      isRunning = false;
    });
  }

  void resetTimer() {
    timer?.cancel();
    setState(() {
      phase = "IDLE";
      seconds = workSeconds;
      currentSet = 1;
      isRunning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = _phaseAccentColor();
    final Color accentDim = accent.withOpacity(0.6);
    const Color textOnDark = Colors.white;

    final TextStyle phaseStyle = const TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: textOnDark,
    );
    final TextStyle timerStyle = const TextStyle(
      fontSize: 56,
      fontWeight: FontWeight.w800,
      color: textOnDark,
    );
    final TextStyle setStyle = const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w500,
      color: Colors.white70,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Workout Timer"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // ConstrainedBox + SingleChildScrollView let content scroll on small screens,
            // avoiding overflow while still stretching to full height when space allows.
            return AnimatedContainer(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF0F1624),
                    accentDim,
                    const Color(0xFF0B1020),
                  ],
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            "Workout Timer",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "Intervals with prep beeps, progress, and saved settings",
                            style: TextStyle(color: Colors.white60, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildMainCard(
                        accent: accent,
                        phaseStyle: phaseStyle,
                        timerStyle: timerStyle,
                        setStyle: setStyle,
                      ),
                      const SizedBox(height: 12),
                      TimerSettingsPanel(
                        workSeconds: workSeconds,
                        restSeconds: restSeconds,
                        totalSets: totalSets,
                        prepEnabled: prepEnabled,
                        locked: settingsLocked,
                        onSelectWork: _selectWorkSeconds,
                        onSelectRest: _selectRestSeconds,
                        onSelectSets: _selectTotalSets,
                        onTogglePrep: (value) {
                          if (settingsLocked) {
                            _showLockedMessage();
                            return;
                          }
                          setState(() {
                            prepEnabled = value;
                            phase = "IDLE";
                            seconds = workSeconds;
                            currentSet = 1;
                            isRunning = false;
                          });
                          saveSettings();
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildControls(accent),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMainCard({
    required Color accent,
    required TextStyle phaseStyle,
    required TextStyle timerStyle,
    required TextStyle setStyle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Text(
              _phaseLabel(),
              key: ValueKey<String>(phase),
              style: phaseStyle.copyWith(color: accent),
            ),
          ),
          const SizedBox(height: 16),
          _buildCircularTimer(accent, timerStyle),
          const SizedBox(height: 12),
          Text(
            "Set ${currentSet.clamp(1, totalSets)} of $totalSets",
            style: setStyle,
          ),
          const SizedBox(height: 6),
          Text(
            "~${_estimatedMinutesLeft()} min left",
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularTimer(Color accent, TextStyle timerStyle) {
    return SizedBox(
      height: 220,
      width: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            height: 200,
            width: 200,
            child: CircularProgressIndicator(
              value: currentProgress,
              strokeWidth: 14,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Text(
              _formatTime(seconds),
              key: ValueKey<int>(seconds),
              style: timerStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(Color accent) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: startTimer,
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Start", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: pauseTimer,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Pause", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: resetTimer,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white24,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Reset", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  String _formatTime(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    if (m == 0) return s.toString();
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  int _estimatedMinutesLeft() {
    final remainingSets = (totalSets - currentSet).clamp(0, totalSets);
    final perSet = workSeconds + restSeconds;
    final int remainingSeconds = remainingSets * perSet + seconds;
    return (remainingSeconds / 60).ceil();
  }

  Color _phaseAccentColor() {
    switch (phase) {
      case "PREP":
        return Colors.amberAccent.shade200;
      case "WORK":
        return Colors.greenAccent.shade400;
      case "REST":
        return Colors.tealAccent.shade200;
      case "DONE":
        return Colors.purpleAccent.shade200;
      default:
        return Colors.blueAccent.shade200;
    }
  }
}

// Stateless settings panel reused inside the screen.
// It receives current values and callbacks from the parent (data flows parent -> child).
class TimerSettingsPanel extends StatelessWidget {
  final int workSeconds;
  final int restSeconds;
  final int totalSets;
  final bool prepEnabled;
  final bool locked;
  final VoidCallback onSelectWork;
  final VoidCallback onSelectRest;
  final VoidCallback onSelectSets;
  final ValueChanged<bool> onTogglePrep;

  const TimerSettingsPanel({
    super.key,
    required this.workSeconds,
    required this.restSeconds,
    required this.totalSets,
    required this.prepEnabled,
    required this.locked,
    required this.onSelectWork,
    required this.onSelectRest,
    required this.onSelectSets,
    required this.onTogglePrep,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled = locked;
    return Opacity(
      opacity: disabled ? 0.6 : 1,
      child: IgnorePointer(
        ignoring: disabled,
        child: Card(
          color: Colors.white.withOpacity(0.08),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Settings",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 12),
                _buildSettingButton(
                  context: context,
                  label: "Work",
                  value: "$workSeconds sec",
                  onPressed: onSelectWork,
                ),
                const SizedBox(height: 12),
                _buildSettingButton(
                  context: context,
                  label: "Rest",
                  value: "$restSeconds sec",
                  onPressed: onSelectRest,
                ),
                const SizedBox(height: 12),
                _buildSettingButton(
                  context: context,
                  label: "Sets",
                  value: "$totalSets",
                  onPressed: onSelectSets,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        "Enable 3-second setup countdown",
                        style: TextStyle(fontSize: 14, color: Colors.white),
                      ),
                    ),
                    Switch(
                      value: prepEnabled,
                      onChanged: locked ? null : onTogglePrep,
                      activeColor: Colors.lightGreenAccent,
                    ),
                  ],
                ),
                if (locked) ...[
                  const SizedBox(height: 12),
                  const Text(
                    "Stop and reset to change settings.",
                    style: TextStyle(fontSize: 12, color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingButton({
    required BuildContext context,
    required String label,
    required String value,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        backgroundColor: Colors.white.withOpacity(0.1),
        foregroundColor: Colors.white,
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

extension _PhaseLabel on _WorkoutTimerScreenState {
  String _phaseLabel() {
    switch (phase) {
      case "PREP":
        return "Get Ready";
      case "WORK":
        return "WORK";
      case "REST":
        return "REST";
      case "DONE":
        return "Done";
      default:
        return "Ready";
    }
  }
}
