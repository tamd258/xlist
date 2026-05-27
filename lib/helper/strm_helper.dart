import 'dart:io';

import 'package:dio/dio.dart';
import 'package:get/get.dart';

import 'package:xlist/helper/driver_helper.dart';
import 'package:xlist/models/index.dart';
import 'package:xlist/storages/index.dart';

class StrmHelper {
  static bool isStrm(String name) {
    return name.toLowerCase().endsWith('.strm');
  }

  static Map<String, String> getHeaders(ObjectModel object, String url) {
    final headers = Map<String, String>.from(
      DriverHelper.getHeaders(object.provider, url),
    );
    final token = Get.find<UserStorage>().token.val;
    if (token.isNotEmpty && _isSameServer(url)) {
      headers[HttpHeaders.authorizationHeader] = token;
    }
    return headers;
  }

  static Future<String> resolvePlayUrl(ObjectModel object, String name) async {
    final rawUrl = object.rawUrl ?? '';
    if (!isStrm(name)) return rawUrl;
    if (rawUrl.isEmpty) throw Exception('strm 文件没有可读取地址');

    final response = await Dio().get<String>(
      rawUrl,
      options: Options(
        headers: getHeaders(object, rawUrl),
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    );

    final content = (response.data ?? '').replaceFirst('\uFEFF', '');
    final line = content
        .split(RegExp(r'[\r\n]+'))
        .map((v) => v.trim())
        .firstWhere(
          (v) => v.isNotEmpty && !v.startsWith('#'),
          orElse: () => '',
        );
    final playUrl = _normalizeUrl(line);
    if (playUrl.isEmpty) throw Exception('strm 内容为空或格式不正确');
    return playUrl;
  }

  static String _normalizeUrl(String url) {
    if (url.isEmpty) return '';
    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme) return url;

    final serverUrl = Get.find<UserStorage>().serverUrl.val;
    if (serverUrl.isEmpty) return url;
    return Uri.parse(serverUrl).resolve(url).toString();
  }

  static bool _isSameServer(String url) {
    try {
      final serverUrl = Get.find<UserStorage>().serverUrl.val;
      if (serverUrl.isEmpty) return false;
      final server = Uri.parse(serverUrl);
      final target = Uri.parse(url);
      return server.scheme == target.scheme &&
          server.host == target.host &&
          server.port == target.port;
    } catch (_) {
      return false;
    }
  }
}
