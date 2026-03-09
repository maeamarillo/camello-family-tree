String formatDate(DateTime d) {
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  final m = months[d.month - 1];
  return '$m ${d.day}, ${d.year}';
}
