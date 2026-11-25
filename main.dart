import 'package:flutter/material.dart';

import 'screens/diary_screen.dart';

void main() {
  runApp(const NarxozPhotoJournalApp());
}

class NarxozPhotoJournalApp extends StatelessWidget {
  const NarxozPhotoJournalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Narxoz Photo Journal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF02569B)),
      ),
      home: const DiaryScreen(),
    );
  }
}