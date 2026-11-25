import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_entry.dart';

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  static const String _storageKey = 'narxoz_diary_entries';

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _captionController = TextEditingController();
  final List<DiaryEntry> _entries = [];

  File? _photo;
  Position? _position;
  DateTime? _capturedAt;
  bool _isLoadingGps = false;
  bool _isLoadingEntries = true;
  String? _gpsMessage;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_storageKey);
      if (raw != null) {
        final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
        _entries
          ..clear()
          ..addAll(decoded
              .map((e) => DiaryEntry.fromJson(e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('Failed to load entries: $e');
    }
    if (mounted) {
      setState(() => _isLoadingEntries = false);
    }
  }

  Future<void> _persistEntries() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String encoded =
          jsonEncode(_entries.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('Failed to save entries: $e');
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
  }

  void _showSettingsDialog({
    required String title,
    required String message,
    required VoidCallback onOpenSettings,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onOpenSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    if (source == ImageSource.camera) {
      final PermissionStatus status = await Permission.camera.request();
      if (!mounted) return;
      if (status.isPermanentlyDenied) {
        _showSettingsDialog(
          title: 'Camera permission blocked',
          message:
              'Camera access was permanently denied. Enable it in the app settings to take photos.',
          onOpenSettings: openAppSettings,
        );
        return;
      }
      if (!status.isGranted) {
        _showMessage('Camera permission denied.');
        return;
      }
    }

    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1080,
      );
      if (picked == null || !mounted) return;

      setState(() {
        _photo = File(picked.path);
        _capturedAt = DateTime.now();
      });

      if (source == ImageSource.camera) {
        await _fetchGps();
      }
    } catch (e) {
      if (mounted) {
        _showMessage(source == ImageSource.camera
            ? 'Camera is not available on this device.'
            : 'Could not open the gallery.');
      }
    }
  }

  Future<void> _fetchGps() async {
    setState(() {
      _isLoadingGps = true;
      _gpsMessage = null;
    });

    try {
      final bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;
      if (!enabled) {
        setState(() => _gpsMessage = 'Location services are turned off.');
        _showSettingsDialog(
          title: 'GPS is disabled',
          message: 'Please enable device location services to geotag photos.',
          onOpenSettings: Geolocator.openLocationSettings,
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted) return;

      if (permission == LocationPermission.denied) {
        setState(() => _gpsMessage = 'Location permission was denied.');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _gpsMessage = 'Location permission is blocked.');
        _showSettingsDialog(
          title: 'Location permission blocked',
          message:
              'Location access was permanently denied. Enable it in the app settings.',
          onOpenSettings: Geolocator.openAppSettings,
        );
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;

      setState(() {
        _position = position;
        _capturedAt ??= DateTime.now();
      });
    } catch (e) {
      if (mounted) {
        setState(() => _gpsMessage = 'Could not get a GPS fix. Try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingGps = false);
      }
    }
  }

  Future<void> _saveEntry() async {
    final File? photo = _photo;
    if (photo == null) {
      _showMessage('Take or pick a photo first.');
      return;
    }

    String storedPath = photo.path;
    try {
      final Directory docsDir = await getApplicationDocumentsDirectory();
      final File stored = await photo.copy(
        '${docsDir.path}/diary_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      storedPath = stored.path;
    } catch (e) {
      debugPrint('Failed to copy photo: $e');
    }

    final String caption = _captionController.text.trim();
    final DiaryEntry entry = DiaryEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      imagePath: storedPath,
      caption: caption.isEmpty ? 'Untitled' : caption,
      latitude: _position?.latitude,
      longitude: _position?.longitude,
      accuracy: _position?.accuracy,
      timestamp: _capturedAt ?? DateTime.now(),
    );

    if (!mounted) return;
    setState(() {
      _entries.insert(0, entry);
      _photo = null;
      _position = null;
      _capturedAt = null;
      _gpsMessage = null;
      _captionController.clear();
    });

    await _persistEntries();
    if (mounted) {
      _showMessage('Entry saved to diary.');
    }
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildPreview(ColorScheme scheme) {
    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _photo == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_camera_outlined,
                      size: 64, color: scheme.outline),
                  const SizedBox(height: 8),
                  Text('No photo selected',
                      style: TextStyle(color: scheme.outline)),
                ],
              )
            : Image.file(_photo!, fit: BoxFit.cover, width: double.infinity),
      ),
    );
  }

  Widget _buildGpsCard(ColorScheme scheme) {
    final Position? pos = _position;
    return Card(
      elevation: 0,
      color: scheme.secondaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow(Icons.place, 'Latitude',
                pos == null ? '—' : pos.latitude.toStringAsFixed(6)),
            _infoRow(Icons.place, 'Longitude',
                pos == null ? '—' : pos.longitude.toStringAsFixed(6)),
            _infoRow(Icons.gps_fixed, 'Accuracy',
                pos == null ? '—' : '± ${pos.accuracy.toStringAsFixed(1)} m'),
            _infoRow(Icons.schedule, 'Timestamp',
                _capturedAt == null ? '—' : formatTimestamp(_capturedAt!)),
            if (_gpsMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_gpsMessage!,
                    style: TextStyle(color: scheme.error)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryCard(DiaryEntry entry) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(entry.imagePath),
                width: 76,
                height: 76,
                fit: BoxFit.cover,
                cacheWidth: 200,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 76,
                  height: 76,
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.broken_image),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.caption,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    entry.latitude != null && entry.longitude != null
                        ? formatCoordinates(entry.latitude!, entry.longitude!)
                        : 'No location',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatTimestamp(entry.timestamp),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('📸 Narxoz Photo Journal'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildPreview(scheme),
            const SizedBox(height: 12),
            _buildGpsCard(scheme),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Take Photo'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Pick Gallery'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _isLoadingGps ? null : _fetchGps,
              icon: _isLoadingGps
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: Text(_isLoadingGps
                  ? 'Locking GPS...'
                  : 'Fetch Current GPS Location'),
            ),
            const Divider(height: 32),
            TextField(
              controller: _captionController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Caption',
                hintText: 'Campus Quad at Narxoz',
                prefixIcon: const Icon(Icons.edit_note),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saveEntry,
              icon: const Icon(Icons.save),
              label: const Text('SAVE ENTRY TO DIARY'),
            ),
            const SizedBox(height: 24),
            Text('📜 Diary Entries (${_entries.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_isLoadingEntries)
              const Center(child: CircularProgressIndicator())
            else if (_entries.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('No entries yet.',
                      style: TextStyle(color: scheme.outline)),
                ),
              )
            else
              ..._entries.map(_buildEntryCard),
          ],
        ),
      ),
    );
  }
}