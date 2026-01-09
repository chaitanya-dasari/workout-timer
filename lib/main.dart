import 'package:flutter/material.dart';
import 'screens/workout_timer_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Small entry widget: sets up MaterialApp and points to the screen.
    return MaterialApp(
      title: 'Workout Timer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const WorkoutTimerScreen(),
    );
  }
}
