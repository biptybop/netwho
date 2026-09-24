String timeAgo(DateTime? t) {
  if (t == null) return 'never';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 30) return '${d.inDays} d ago';
  return dateText(t);
}

String dateText(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

String msText(double? ms) {
  if (ms == null) return '—';
  if (ms < 1) return '<1 ms';
  if (ms < 10) return '${ms.toStringAsFixed(1)} ms';
  return '${ms.round()} ms';
}
