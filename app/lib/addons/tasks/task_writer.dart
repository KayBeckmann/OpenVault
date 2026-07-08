/// Pure text transforms for toggling a task's done-state in a file's content.
///
/// Kept free of file I/O so it is fully unit-testable. The actual save (backend
/// on web, LocalVaultService on native) is done by a [TaskFileWriter] in A3b.
class TaskWriter {
  static final _checkbox = RegExp(r'^(\s*[-*]\s+\[)([ xX])(\].*)$');
  static final _doneDate = RegExp(r'\s*✅\s*\d{4}-\d{2}-\d{2}');

  /// Returns [content] with the checkbox on [line] set to [done].
  ///
  /// When completing and [addDoneDate] is true, appends `✅ <date>`; when
  /// re-opening, any existing `✅ <date>` is removed. All other signifiers on
  /// the line are preserved. If [line] is not a checkbox, [content] is returned
  /// unchanged.
  static String setDone(
    String content,
    int line, {
    required bool done,
    DateTime? date,
    bool addDoneDate = true,
  }) {
    final lines = content.split('\n');
    if (line < 0 || line >= lines.length) return content;

    final m = _checkbox.firstMatch(lines[line]);
    if (m == null) return content;

    var rebuilt = '${m.group(1)}${done ? 'x' : ' '}${m.group(3)}';

    if (done) {
      if (addDoneDate && !_doneDate.hasMatch(rebuilt)) {
        rebuilt = '$rebuilt ✅ ${_fmt(date ?? DateTime.now())}';
      }
    } else {
      rebuilt = rebuilt.replaceAll(_doneDate, '');
    }

    lines[line] = rebuilt;
    return lines.join('\n');
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Platform abstraction for persisting a task toggle back to the vault file.
/// Implemented in A3b (web: backend API, native: LocalVaultService).
abstract class TaskFileWriter {
  /// Reads a vault file's content.
  Future<String> read(String filePath);

  /// Writes [content] back to a vault file.
  Future<void> write(String filePath, String content);
}
