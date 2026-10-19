import 'dart:io';

import 'package:dio/dio.dart';

import '../models/api_types.dart';
import 'api_exception.dart';

/// Thin, typed wrapper over the OpenList HTTP API (v3 / v4).
///
/// Every request is issued against the Base URL the user typed, so sub-path
/// deployments such as `https://host/openlist` work without extra config.
class OpenListApi {
  final String baseUrl;
  final Dio _dio;
  String? token;

  OpenListApi({required this.baseUrl, this.token})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 40),
            sendTimeout: const Duration(seconds: 40),
            validateStatus: (s) => s != null && s < 500,
            headers: const {'Accept': 'application/json'},
            responseType: ResponseType.json,
          ),
        );

  Dio get dio => _dio;

  Options _opts({Map<String, String>? headers, ResponseType? type, Duration? receiveTimeout}) {
    final h = <String, String>{};
    if (token != null && token!.isNotEmpty) h['Authorization'] = token!;
    if (headers != null) h.addAll(headers);
    return Options(
      headers: h,
      responseType: type,
      receiveTimeout: receiveTimeout,
    );
  }

  dynamic _unwrap(dynamic data) {
    if (data is Map) {
      final code = data['code'];
      if (code is num && code.toInt() != 200) {
        throw ApiException(code.toInt(), (data['message'] ?? '请求失败').toString());
      }
      return data['data'];
    }
    return data;
  }

  Future<dynamic> _get(String path, {Map<String, dynamic>? query}) async {
    try {
      final res = await _dio.get(path, queryParameters: query, options: _opts());
      return _unwrap(res.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<dynamic> _post(String path, [Map<String, dynamic>? body]) async {
    try {
      final res = await _dio.post(path, data: body ?? const {}, options: _opts());
      return _unwrap(res.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  // ---------------------------------------------------------------- public

  Future<SiteInfo> publicSettings() async {
    final data = await _get('/api/public/settings');
    if (data is Map<String, dynamic>) return SiteInfo.fromJson(data);
    if (data is Map) return SiteInfo.fromJson(Map<String, dynamic>.from(data));
    return const SiteInfo(title: 'OpenList');
  }

  // ------------------------------------------------------------------ auth

  Future<String> login({required String username, required String password, String otpCode = ''}) async {
    final data = await _post('/api/auth/login', {
      'username': username,
      'password': password,
      if (otpCode.isNotEmpty) 'otp_code': otpCode,
    });
    final tokenValue = (data is Map ? data['token'] : null)?.toString();
    if (tokenValue == null || tokenValue.isEmpty) {
      throw const ApiException(-10, '服务器未返回 token');
    }
    token = tokenValue;
    return tokenValue;
  }

  Future<UserInfo> me() async {
    final data = await _get('/api/me');
    if (data is Map) return UserInfo.fromJson(Map<String, dynamic>.from(data));
    throw const ApiException(-11, '无法读取当前用户');
  }

  // -------------------------------------------------------------------- fs

  Future<FsListPage> list({
    String path = '/',
    String password = '',
    int page = 1,
    int perPage = 100,
    bool refresh = false,
    String orderBy = 'name',
    String orderDirection = 'asc',
  }) async {
    final data = await _post('/api/fs/list', {
      'path': path,
      'password': password,
      'page': page,
      'per_page': perPage,
      'refresh': refresh,
      'order_by': orderBy,
      'order_direction': orderDirection,
    });
    if (data is! Map) return const FsListPage(items: [], total: 0);
    final rawContent = data['content'];
    final items = <FileItem>[];
    if (rawContent is List) {
      for (final e in rawContent) {
        if (e is Map) items.add(FileItem.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return FsListPage(
      items: items,
      total: (data['total'] as num?)?.toInt() ?? items.length,
      write: data['write'] != false,
      provider: data['provider']?.toString(),
    );
  }

  Future<FileItem> get(String path, {String password = ''}) async {
    final data = await _post('/api/fs/get', {'path': path, 'password': password});
    if (data is Map) {
      final item = FileItem.fromJson({
        ...Map<String, dynamic>.from(data),
        'name': data['name'] ?? path.split('/').last,
        'is_dir': data['is_dir'] ?? false,
        'size': data['size'] ?? 0,
      });
      return item;
    }
    throw const ApiException(-12, '无法读取文件信息');
  }

  Future<List<FileItem>> search({
    required String parent,
    required String keywords,
    int scope = 0,
    int page = 1,
    int perPage = 50,
    String password = '',
  }) async {
    final data = await _post('/api/fs/search', {
      'parent': parent,
      'keywords': keywords,
      'scope': scope,
      'page': page,
      'per_page': perPage,
      'password': password,
    });
    if (data is Map && data['content'] is List) {
      return (data['content'] as List)
          .whereType<Map>()
          .map((e) => FileItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  Future<List<DirNode>> dirs({String path = '/', String password = ''}) async {
    final data = await _post('/api/fs/dirs', {'path': path, 'password': password});
    if (data is! List) return const [];
    final out = <DirNode>[];
    for (final e in data) {
      if (e is Map) {
        final name = (e['name'] ?? '').toString();
        final p = (e['path'] ?? '').toString();
        if (name.isEmpty) continue;
        out.add(DirNode(name, p.isEmpty ? path : p));
      }
    }
    return out;
  }

  Future<void> mkdir(String path) => _post('/api/fs/mkdir', {'path': path});

  Future<void> rename(String path, String name) => _post('/api/fs/rename', {'path': path, 'name': name});

  Future<void> move(String srcDir, String dstDir, List<String> names) =>
      _post('/api/fs/move', {'src_dir': srcDir, 'dst_dir': dstDir, 'names': names});

  Future<void> copy(String srcDir, String dstDir, List<String> names) =>
      _post('/api/fs/copy', {'src_dir': srcDir, 'dst_dir': dstDir, 'names': names});

  Future<void> remove(String dir, List<String> names) =>
      _post('/api/fs/remove', {'dir': dir, 'names': names});

  Future<void> addOfflineDownload({
    required List<String> urls,
    required String path,
    String deletePolicy = 'delete_on_upload_succeed',
  }) =>
      _post('/api/fs/add_offline_download', {
        'urls': urls,
        'path': path,
        'delete_policy': deletePolicy,
      });

  // ----------------------------------------------------------------- share

  Future<List<ShareInfo>> shares({int page = 1, int perPage = 100}) async {
    final data = await _get('/api/share/list', query: {'page': page, 'per_page': perPage});
    if (data is Map && data['content'] is List) {
      return (data['content'] as List)
          .whereType<Map>()
          .map((e) => ShareInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (data is List) {
      return data.whereType<Map>().map((e) => ShareInfo.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    return const [];
  }

  Future<ShareInfo?> createShare({
    required String path,
    int expireDays = 0,
    String? password,
  }) async {
    final data = await _post('/api/share/create', {
      'path': path,
      'expire_days': expireDays,
      if (password != null && password.isNotEmpty) 'pwd': password,
    });
    if (data is Map) return ShareInfo.fromJson(Map<String, dynamic>.from(data));
    return null;
  }

  Future<void> deleteShare(String id) => _post('/api/share/delete', {'id': id});

  // ------------------------------------------------------------- admin (A)

  Future<List<StorageMount>> storages() async {
    final data = await _get('/api/admin/storage/list');
    if (data is List) {
      return data.whereType<Map>().map((e) => StorageMount.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    if (data is Map && data['content'] is List) {
      return (data['content'] as List)
          .whereType<Map>()
          .map((e) => StorageMount.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  Future<List<ServerTask>> tasks() async {
    final data = await _get('/api/task/list');
    if (data is List) {
      return data.whereType<Map>().map((e) => ServerTask.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    return const [];
  }

  // -------------------------------------------------------------- urls

  static String _encodePath(String path) {
    final clean = path.startsWith('/') ? path.substring(1) : path;
    return clean.split('/').map(Uri.encodeComponent).join('/');
  }

  /// Signed direct link — supports Range, used for download and streaming.
  String downloadUrl(String path, {String? sign}) {
    final base = '$baseUrl/d/${_encodePath(path)}';
    if (sign == null || sign.isEmpty) return base;
    return '$base?sign=${Uri.encodeComponent(sign)}';
  }

  String proxyUrl(String path, {String? sign}) {
    final base = '$baseUrl/p/${_encodePath(path)}';
    if (sign == null || sign.isEmpty) return base;
    return '$base?sign=${Uri.encodeComponent(sign)}';
  }

  // ------------------------------------------------------------- transfer

  /// Download with optional resume. Streams to [sink] so the caller owns the
  /// file handle and can pause at any byte boundary.
  Future<int> downloadToFile({
    required String path,
    required String sign,
    required File target,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
    int throttleBytesPerSecond = 0,
  }) async {
    final existing = await target.exists() ? await target.length() : 0;
    final headers = <String, String>{};
    if (existing > 0) headers['Range'] = 'bytes=$existing-';
    Response<ResponseBody> res;
    try {
      res = await _dio.get<ResponseBody>(
        downloadUrl(path, sign: sign),
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          followRedirects: true,
          receiveTimeout: const Duration(days: 1),
          sendTimeout: const Duration(days: 1),
          validateStatus: (s) => s != null && s < 400,
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }

    final partial = res.statusCode == 206 && existing > 0;
    final totalHeader = res.headers.value('content-length');
    final contentLength = int.tryParse(totalHeader ?? '') ?? 0;
    final total = partial ? existing + contentLength : contentLength;
    var received = partial ? existing : 0;

    final sink = target.openWrite(mode: partial ? FileMode.append : FileMode.write);
    final body = res.data;
    if (body == null) {
      await sink.close();
      throw const ApiException(-13, '服务器未返回数据流');
    }
    var windowBytes = 0;
    var windowStart = DateTime.now();
    try {
      await for (final chunk in body.stream) {
        sink.add(chunk);
        received += chunk.length;
        windowBytes += chunk.length;
        if (throttleBytesPerSecond > 0) {
          final elapsed = DateTime.now().difference(windowStart).inMilliseconds;
          final expectedMs = windowBytes * 1000 / throttleBytesPerSecond;
          if (elapsed < expectedMs) {
            await Future<void>.delayed(Duration(milliseconds: (expectedMs - elapsed).round()));
          }
          if (windowBytes > throttleBytesPerSecond * 2) {
            windowBytes = 0;
            windowStart = DateTime.now();
          }
        }
        onProgress(received, total);
        if (cancelToken.isCancelled) break;
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    return received;
  }

  Future<void> uploadFile({
    required String remotePath,
    required File source,
    required CancelToken cancelToken,
    required void Function(int sent, int total) onProgress,
  }) async {
    final length = await source.length();
    final headers = <String, String>{
      'File-Path': Uri.encodeComponent(remotePath),
      'Content-Type': 'application/octet-stream',
      'Content-Length': '$length',
    };
    if (token != null && token!.isNotEmpty) headers['Authorization'] = token!;
    try {
      final res = await _dio.put<dynamic>(
        '/api/fs/put',
        data: source.openRead(),
        options: Options(
          headers: headers,
          sendTimeout: const Duration(days: 1),
          receiveTimeout: const Duration(days: 1),
          validateStatus: (s) => s != null && s < 500,
        ),
        cancelToken: cancelToken,
        onSendProgress: onProgress,
      );
      _unwrap(res.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
