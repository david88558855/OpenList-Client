import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/openlist_api.dart';
import '../../core/models/api_types.dart';
import '../../core/models/server_profile.dart';
import '../../core/models/transfer_task.dart';
import '../../core/storage/download_paths.dart';

class TransfersState {
  final List<TransferTask> tasks;
  final List<ServerTask> serverTasks;
  final double downSpeed;
  final double upSpeed;
  final int concurrency;
  final bool pausedGlobally;
  final String? error;

  const TransfersState({
    this.tasks = const [],
    this.serverTasks = const [],
    this.downSpeed = 0,
    this.upSpeed = 0,
    this.concurrency = 2,
    this.pausedGlobally = false,
    this.error,
  });

  List<TransferTask> get active => tasks.where((e) => e.status == TransferStatus.running).toList();
  List<TransferTask> get queued => tasks.where((e) => e.status == TransferStatus.queued).toList();
  List<TransferTask> get paused => tasks.where((e) => e.status == TransferStatus.paused).toList();
  List<TransferTask> get done => tasks.where((e) => e.status == TransferStatus.done).toList();
  List<TransferTask> get failed => tasks.where((e) => e.status == TransferStatus.failed).toList();
  int get pendingCount => tasks.where((e) => e.status == TransferStatus.running || e.status == TransferStatus.queued).length;

  TransfersState copyWith({
    List<TransferTask>? tasks,
    List<ServerTask>? serverTasks,
    double? downSpeed,
    double? upSpeed,
    int? concurrency,
    bool? pausedGlobally,
    String? error,
    bool clearError = false,
  }) =>
      TransfersState(
        tasks: tasks ?? this.tasks,
        serverTasks: serverTasks ?? this.serverTasks,
        downSpeed: downSpeed ?? this.downSpeed,
        upSpeed: upSpeed ?? this.upSpeed,
        concurrency: concurrency ?? this.concurrency,
        pausedGlobally: pausedGlobally ?? this.pausedGlobally,
        error: clearError ? null : (error ?? this.error),
      );
}

class TransfersNotifier extends StateNotifier<TransfersState> {
  final Ref ref;
  final Map<String, CancelToken> _tokens = {};
  final Map<String, int> _previousDone = {};
  Timer? _ticker;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  bool _pumping = false;

  TransfersNotifier(this.ref) : super(const TransfersState()) {
    state = state.copyWith(concurrency: ref.read(appSettingsProvider).concurrency);
    _restore();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  static const _persistKey = 'ol_transfers';

  @override
  void dispose() {
    _ticker?.cancel();
    for (final token in _tokens.values) {
      token.cancel();
    }
    super.dispose();
  }

  void _restore() {
    final raw = ref.read(prefsProvider).getJsonList(_persistKey);
    final restored = <TransferTask>[];
    for (final e in raw) {
      if (e is Map) {
        final task = TransferTask.fromJson(Map<String, dynamic>.from(e));
        if (task.status == TransferStatus.running || task.status == TransferStatus.queued) {
          task.status = TransferStatus.paused;
        }
        if (task.status != TransferStatus.done) restored.add(task);
      }
    }
    if (restored.isNotEmpty) {
      state = state.copyWith(tasks: restored);
    }
  }

  void _persist() {
    final list = state.tasks
        .where((e) => e.status == TransferStatus.paused || e.status == TransferStatus.queued || e.status == TransferStatus.running || e.status == TransferStatus.failed)
        .map((e) => e.toJson())
        .toList();
    ref.read(prefsProvider).setJsonList(_persistKey, list);
  }

  void _emit() => state = state.copyWith(tasks: List<TransferTask>.of(state.tasks));

  void _emitThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastEmit).inMilliseconds < 150) return;
    _lastEmit = now;
    _emit();
  }

  void _tick() {
    if (!mounted) return;
    var down = 0.0;
    var up = 0.0;
    for (final task in state.tasks) {
      final previous = _previousDone[task.id] ?? task.done;
      final delta = task.done - previous;
      _previousDone[task.id] = task.done;
      if (task.status == TransferStatus.running) {
        task.speed = delta < 0 ? 0 : delta.toDouble();
        if (task.kind == TransferKind.download) {
          down += task.speed;
        } else {
          up += task.speed;
        }
      } else {
        task.speed = 0;
      }
    }
    state = state.copyWith(tasks: List<TransferTask>.of(state.tasks), downSpeed: down, upSpeed: up);
  }

  // ------------------------------------------------------------- enqueue

  Future<String?> enqueueDownload(FileItem item, String currentDir) async {
    final session = ref.read(sessionProvider);
    final profile = session.profile;
    if (profile == null || session.api == null) return '尚未连接服务器';
    if (item.isDir) return '暂不支持整目录下载';
    final dir = await _downloadDir(profile);
    final remotePath = item.parent ?? (currentDir == '/' ? '/${item.name}' : '$currentDir/${item.name}');
    // 同名文件不能互相覆盖：已在队列里的同一远程文件复用原路径（续传），
    // 否则在磁盘上顺延出「name (2).ext」。
    final localPath = _resolveLocalPath(dir, item.name, remotePath);
    final task = TransferTask(
      id: 'dl-${DateTime.now().microsecondsSinceEpoch}-${item.name.hashCode}',
      serverId: profile.id,
      serverLabel: profile.name,
      kind: TransferKind.download,
      name: item.name,
      remotePath: remotePath,
      localPath: localPath,
      total: item.size,
      sign: item.sign,
    );
    state = state.copyWith(tasks: [task, ...state.tasks], clearError: true);
    _persist();
    await _pump();
    return null;
  }

  Future<String?> enqueueUpload({required String localPath, required String remoteDir, required String name}) async {
    final session = ref.read(sessionProvider);
    final profile = session.profile;
    if (profile == null || session.api == null) return '尚未连接服务器';
    final remotePath = remoteDir == '/' ? '/$name' : '$remoteDir/$name';
    int size = 0;
    try {
      size = await File(localPath).length();
    } catch (_) {
      size = 0;
    }
    final task = TransferTask(
      id: 'ul-${DateTime.now().microsecondsSinceEpoch}-${name.hashCode}',
      serverId: profile.id,
      serverLabel: profile.name,
      kind: TransferKind.upload,
      name: name,
      remotePath: remotePath,
      localPath: localPath,
      total: size,
    );
    state = state.copyWith(tasks: [task, ...state.tasks], clearError: true);
    _persist();
    await _pump();
    return null;
  }

  // --------------------------------------------------------------- control

  void pause(String id) {
    final task = _find(id);
    if (task == null) return;
    task.status = TransferStatus.paused;
    _tokens[id]?.cancel();
    _persist();
    _emit();
  }

  Future<void> resume(String id) async {
    final task = _find(id);
    if (task == null) return;
    task.status = TransferStatus.queued;
    task.error = null;
    _emit();
    await _pump();
  }

  Future<void> retry(String id) async {
    final task = _find(id);
    if (task == null) return;
    task.error = null;
    task.status = TransferStatus.queued;
    _emit();
    await _pump();
  }

  void remove(String id) {
    _tokens[id]?.cancel();
    _tokens.remove(id);
    _previousDone.remove(id);
    final task = _find(id);
    if (task != null && task.status != TransferStatus.done) {
      try {
        final file = File(task.localPath);
        // 只清理未完成的半成品：完整文件（同名已下载完）不能因为移除任务被删掉。
        final complete = task.total > 0 && file.existsSync() && file.lengthSync() >= task.total;
        if (task.kind == TransferKind.download && file.existsSync() && !complete) {
          file.deleteSync();
        }
      } catch (_) {
        // ignore
      }
    }
    state = state.copyWith(tasks: state.tasks.where((e) => e.id != id).toList());
    _persist();
  }

  void clearFinished() {
    state = state.copyWith(
      tasks: state.tasks.where((e) => e.status != TransferStatus.done && e.status != TransferStatus.failed).toList(),
    );
    _persist();
  }

  Future<void> pauseAll() async {
    state = state.copyWith(pausedGlobally: true);
    for (final task in state.tasks) {
      if (task.status == TransferStatus.running || task.status == TransferStatus.queued) {
        task.status = TransferStatus.paused;
        _tokens[task.id]?.cancel();
      }
    }
    _persist();
    _emit();
  }

  Future<void> resumeAll() async {
    state = state.copyWith(pausedGlobally: false);
    for (final task in state.tasks) {
      if (task.status == TransferStatus.paused) task.status = TransferStatus.queued;
    }
    _emit();
    await _pump();
  }

  Future<void> setConcurrency(int value) async {
    state = state.copyWith(concurrency: value.clamp(1, 8).toInt());
    await _pump();
  }

  void clearError() => state = state.copyWith(clearError: true);

  // ---------------------------------------------------------------- worker

  TransferTask? _find(String id) {
    for (final t in state.tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  OpenListApi? _apiFor(String serverId) {
    final session = ref.read(sessionProvider);
    if (session.profile?.id == serverId) return session.api;
    return null;
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      if (!state.pausedGlobally) {
        var running = state.tasks.where((e) => e.status == TransferStatus.running).length;
        final limit = state.concurrency;
        for (final task in state.tasks.toList()) {
          if (running >= limit) break;
          if (task.status == TransferStatus.queued) {
            running++;
            unawaited(_run(task));
          }
        }
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _run(TransferTask task) async {
    final api = _apiFor(task.serverId);
    if (api == null) {
      task.status = TransferStatus.paused;
      task.error = '切换了服务器，恢复后继续';
      _emit();
      return;
    }
    final token = CancelToken();
    _tokens[task.id] = token;
    task.status = TransferStatus.running;
    task.error = null;
    _emit();
    final settings = ref.read(appSettingsProvider);
    final downLimitKbps = settings.downLimitKbps;
    final upLimitKbps = settings.upLimitKbps;
    try {
      if (task.kind == TransferKind.download) {
        var sign = task.sign;
        if (sign == null || sign.isEmpty) {
          final info = await api.get(task.remotePath);
          sign = info.sign ?? '';
          task.sign = sign;
        }
        final target = File(task.localPath);
        await target.parent.create(recursive: true);
        final received = await api.downloadToFile(
          path: task.remotePath,
          sign: sign,
          target: target,
          cancelToken: token,
          throttleBytesPerSecond: downLimitKbps * 1024,
          onProgress: (done, total) {
            task.done = done;
            if (total > 0) task.total = total;
            _emitThrottled();
          },
        );
        task.done = received;
        if (task.total <= 0) task.total = received;
        if (task.status != TransferStatus.paused) task.status = TransferStatus.done;
      } else {
        await api.uploadFile(
          remotePath: task.remotePath,
          source: File(task.localPath),
          cancelToken: token,
          // v2.3：上传限速生效（此前只把下载限速传下去，上传设置是空转的）。
          throttleBytesPerSecond: upLimitKbps * 1024,
          onProgress: (sent, total) {
            task.done = sent;
            if (total > 0) task.total = total;
            _emitThrottled();
          },
        );
        if (task.status != TransferStatus.paused) {
          task.done = task.total;
          task.status = TransferStatus.done;
        }
      }
    } on ApiException catch (e) {
      if (task.status != TransferStatus.paused) {
        task.status = TransferStatus.failed;
        task.error = e.friendly;
        if (e.needsReauth) await ref.read(sessionProvider.notifier).expire();
      }
    } catch (e) {
      if (task.status != TransferStatus.paused) {
        task.status = TransferStatus.failed;
        task.error = '传输中断，可重试';
      }
    } finally {
      _tokens.remove(task.id);
      _persist();
      _emit();
      await _pump();
    }
  }

  String _resolveLocalPath(String dir, String name, String remotePath) {
    for (final task in state.tasks) {
      if (task.kind == TransferKind.download &&
          task.remotePath == remotePath &&
          task.status != TransferStatus.done) {
        return task.localPath;
      }
    }
    final safe = _safeName(name);
    final candidate = File('$dir${Platform.pathSeparator}$safe');
    if (!candidate.existsSync()) return candidate.path;
    final dot = safe.lastIndexOf('.');
    final base = dot > 0 ? safe.substring(0, dot) : safe;
    final ext = dot > 0 ? safe.substring(dot) : '';
    for (var i = 2; i < 1000; i++) {
      final next = File('$dir${Platform.pathSeparator}$base ($i)$ext');
      if (!next.existsSync()) return next.path;
    }
    return candidate.path;
  }

  Future<String> _downloadDir(ServerProfile profile) async {
    // v2.5：与设置页共用同一套路径规则（Android 落在公共 Download/OpenList），
    // 并处理目录创建失败（未授权公共目录时退回应用私有目录）。
    return ensureDownloadDirFor(ref.read(serverStoreProvider), profile);
  }

  String _safeName(String value) {
    final sanitized = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return sanitized.isEmpty ? 'item' : sanitized;
  }

  Future<void> loadServerTasks() async {
    final api = ref.read(sessionProvider).api;
    if (api == null) return;
    try {
      final tasks = await api.tasks();
      state = state.copyWith(serverTasks: tasks);
    } on ApiException catch (e) {
      state = state.copyWith(error: e.friendly);
    }
  }
}
