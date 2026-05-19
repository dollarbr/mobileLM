import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

final Dio _dio = Dio();
final Map<String, CancelToken> _cancelTokens = {};

Future<String> getModelsDir() async {
  final dir = await getApplicationDocumentsDirectory();
  final modelsPath = '${dir.path}/models';
  await Directory(modelsPath).create(recursive: true);
  return modelsPath;
}

Future<bool> isModelDownloaded(String path) async {
  return File(path).existsSync();
}

Future<List<String>> getDownloadedModels(String modelsDir) async {
  final dir = Directory(modelsDir);
  if (!await dir.exists()) return [];
  return dir
      .listSync()
      .where((f) =>
          f.path.endsWith('.gguf') ||
          f.path.endsWith('.litertlm') ||
          f.path.endsWith('.safetensors'))
      .map((f) => f.path.split('/').last)
      .toList();
}

Future<int> getModelSize(String path) async {
  final file = File(path);
  if (!await file.exists()) return 0;
  return await file.length();
}

Future<int> getRemoteFileSize(String url, {String? authToken}) async {
  final headers = <String, dynamic>{};
  if (authToken != null && authToken.isNotEmpty) {
    headers['Authorization'] = 'Bearer $authToken';
  }

  final response = await _dio.head(
    url,
    options: Options(headers: headers, followRedirects: true),
  );

  final length = response.headers.value(Headers.contentLengthHeader);
  return int.tryParse(length ?? '') ?? 0;
}

Future<String> downloadModel({
  required String url,
  required String savePath,
  String? authToken,
  void Function(int received, int total)? onProgress,
}) async {
  final tempPath = '$savePath.part';
  final cancelToken = CancelToken();
  final filename = savePath.split('/').last;
  _cancelTokens[filename] = cancelToken;
  var expectedTotalBytes = 0;

  try {
    final tempFile = File(tempPath);
    final oldTempFile = File('$savePath.tmp');
    if (await oldTempFile.exists()) {
      await oldTempFile.delete();
    }
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final headers = <String, dynamic>{};
    if (authToken != null && authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }

    await _dio.download(
      url,
      tempPath,
      cancelToken: cancelToken,
      deleteOnError: false,
      options: Options(
        headers: headers,
        responseType: ResponseType.stream,
        followRedirects: true,
      ),
      onReceiveProgress: (received, total) {
        if (total > 0) {
          expectedTotalBytes = total;
        }
        onProgress?.call(received, total > 0 ? total : 0);
      },
    );

    final downloadedBytes = await tempFile.length();
    if (expectedTotalBytes > 0 && downloadedBytes < expectedTotalBytes) {
      await tempFile.delete();
      throw Exception(
        'Downloaded file is incomplete: $downloadedBytes of $expectedTotalBytes bytes.',
      );
    }
    final finalFile = File(savePath);
    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await tempFile.rename(savePath);
    _cancelTokens.remove(filename);
    return savePath;
  } on DioException catch (e) {
    if (e.type == DioExceptionType.cancel) {
      _cancelTokens.remove(filename);
      return 'PAUSED';
    }
    _cancelTokens.remove(filename);
    throw Exception('Download failed: ${e.message}');
  } catch (e) {
    _cancelTokens.remove(filename);
    rethrow;
  }
}

void pauseDownload(String filename) {
  _cancelTokens[filename]?.cancel('paused');
}

Future<void> deleteModel(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
  final partFile = File('$path.part');
  if (await partFile.exists()) await partFile.delete();
  final tempFile = File('$path.tmp');
  if (await tempFile.exists()) await tempFile.delete();
}
