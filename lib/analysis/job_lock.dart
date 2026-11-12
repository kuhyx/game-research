/// One analysis job at a time, machine-wide.
///
/// The lock is a symlink `<data>/analysis.lock` whose target text is
/// `<pid>:<start time>:<job id>`: creating a symlink is atomic and fails when
/// it exists, so two jobs never both win. The start time (field 22 of
/// `/proc/<pid>/stat`) tells the owner from an unrelated process that reused
/// its pid after a reboot. Older analyzer builds wrote `analysis/lock` (a bare
/// pid) in the session folder; one whose pid is a live analyzer still counts.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Who holds the lock.
class JobHolder {
  /// Creates a holder record.
  const new(this.pid, this.start, this.job);

  /// The owner's pid.
  final int pid;

  /// The owner's `/proc` start time ('' when unknown).
  final String start;

  /// The job id: a session folder name or `finish:<slug>`.
  final String job;

  /// The symlink text.
  String get text => '$pid:$start:$job';
}

/// The machine-wide job lock under a data folder.
class JobLock {
  /// Creates the lock for [dataDir]; [selfPid] is the owner to record.
  new(this.dataDir, {this.procRoot = '/proc', int? selfPid})
    : selfPid = selfPid ?? pid;

  /// `<data>`.
  final String dataDir;

  /// Where `/proc` is (a temp dir in tests).
  final String procRoot;

  /// The pid recorded as owner.
  final int selfPid;

  Link get _link => Link(p.join(dataDir, 'analysis.lock'));

  /// The start time of [ownerPid] from `/proc/<pid>/stat`, '' when unreadable.
  String startTime(int ownerPid) {
    try {
      final stat = File('$procRoot/$ownerPid/stat').readAsStringSync();
      // comm (field 2) may hold spaces and parens: count from the last ')'.
      final rest = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
      return rest.length > 19 ? rest[19] : '';
    } on Object {
      return '';
    }
  }

  bool _alive(int ownerPid, String start) {
    if (!Directory('$procRoot/$ownerPid').existsSync()) return false;
    return start.isEmpty || startTime(ownerPid) == start;
  }

  JobHolder? _readGlobal() {
    final String text;
    try {
      text = _link.targetSync();
    } on FileSystemException {
      return null;
    }
    final parts = text.split(':');
    final owner = parts.length >= 3 ? int.tryParse(parts[0]) : null;
    if (owner == null) return const JobHolder(0, '', '');
    return JobHolder(owner, parts[1], parts.skip(2).join(':'));
  }

  /// Whether [ownerPid] is an analyzer process: an old lock has no start
  /// time, and after a reboot its pid may belong to anything.
  bool _isAnalyzer(int ownerPid) {
    try {
      return File('$procRoot/$ownerPid/cmdline')
          .readAsStringSync()
          .contains('game_research_analyze');
    } on FileSystemException {
      return false;
    }
  }

  JobHolder? _legacy() {
    final root = Directory(dataDir);
    if (!root.existsSync()) return null;
    for (final d in root.listSync().whereType<Directory>()) {
      final file = File(p.join(d.path, 'analysis', 'lock'));
      if (!file.existsSync()) continue;
      final owner = int.tryParse(file.readAsStringSync().trim());
      if (owner != null && owner != selfPid && _isAnalyzer(owner)) {
        return JobHolder(owner, '', p.basename(d.path));
      }
    }
    return null;
  }

  /// The live holder (global lock or an old session lock), null when free.
  JobHolder? holder() {
    final g = _readGlobal();
    if (g != null && g.pid > 0 && _alive(g.pid, g.start)) return g;
    return _legacy();
  }

  /// Takes the lock for [job]; false when a live job holds it.
  bool acquire(String job) {
    Directory(dataDir).createSync(recursive: true);
    if (_legacy() != null) return false;
    final mine = JobHolder(selfPid, startTime(selfPid), job);
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        _link.createSync(mine.text);
        return true;
      } on FileSystemException {
        final cur = _readGlobal();
        if (cur != null && cur.pid > 0 && _alive(cur.pid, cur.start)) {
          return false;
        }
        // Stale or garbled: remove it, but only if it is still that same
        // text (another job may just have taken it over).
        if (cur == null || _link.existsSync() && _same(cur)) _drop();
      }
    }
    return false;
  }

  /// Frees the lock if this process holds it.
  void release() {
    final cur = _readGlobal();
    if (cur != null && cur.pid == selfPid) _drop();
  }

  bool _same(JobHolder seen) => _readGlobal()?.text == seen.text;

  /// Deletes the lock link; a link that is already gone is fine.
  void _drop() {
    if (_link.existsSync()) _link.deleteSync();
  }
}
