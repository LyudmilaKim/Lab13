class DiaryEntry {
  final String id;
  final String imagePath;
  final String caption;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final DateTime timestamp;

  const DiaryEntry({
    required this.id,
    required this.imagePath,
    required this.caption,
    this.latitude,
    this.longitude,
    this.accuracy,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'imagePath': imagePath,
        'caption': caption,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'timestamp': timestamp.toIso8601String(),
      };

  factory DiaryEntry.fromJson(Map<String, dynamic> json) => DiaryEntry(
        id: json['id'] as String,
        imagePath: json['imagePath'] as String,
        caption: json['caption'] as String? ?? 'Untitled',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

String formatTimestamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

String formatCoordinates(double lat, double lng) {
  final String ns = lat >= 0 ? 'N' : 'S';
  final String ew = lng >= 0 ? 'E' : 'W';
  return '${lat.abs().toStringAsFixed(4)}° $ns, '
      '${lng.abs().toStringAsFixed(4)}° $ew';
}