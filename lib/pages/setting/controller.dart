import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:xlist/storages/index.dart';
import 'package:xlist/constants/index.dart';
import 'package:xlist/database/entity/index.dart';
import 'package:xlist/services/database_service.dart';

class SettingController extends GetxController {
  final version = ''.obs; // 版本号
  final serverId = Get.find<UserStorage>().serverId.val.obs;
  final serverInfo =
      ServerEntity(url: '', type: 0, username: '', password: '').obs;

  // 自动播放
  final isAutoPlay = Get.find<PreferencesStorage>().isAutoPlay.val.obs;

  // 后台播放
  final isBackgroundPlay =
      Get.find<PreferencesStorage>().isBackgroundPlay.val.obs;

  // 硬件解码
  final isHardwareDecode =
      Get.find<PreferencesStorage>().isHardwareDecode.val.obs;

  // 显示预览图
  final isShowPreview = Get.find<PreferencesStorage>().isShowPreview.val.obs;

  // 主题
  final themeModeText = ''.obs;
  final InAppReview inAppReview = InAppReview.instance;

  /// 数据库路径
  final databasePath = ''.obs;

  /// 偏好设置目录
  final preferencesPath = ''.obs;

  @override
  void onInit() async {
    super.onInit();

    // 获取当前版本号
    final packageInfo = await PackageInfo.fromPlatform();
    version.value = packageInfo.version;

    // 获取当前服务器信息
    serverInfo.value = (await DatabaseService.to.database.serverDao
            .findServerById(serverId.value)) ??
        ServerEntity(url: '', type: 0, username: '无', password: '');

    // 获取当前主题模式
    themeModeText.value =
        ThemeModeTextMap[Get.find<CommonStorage>().themeMode.val]!;

    // 获取存储路径 (数据库用 sqflite 路径，偏好设置用文档目录)
    final dbDir = await getDatabasesPath();
    databasePath.value = '$dbDir/xlist_database.db';
    final docDir = await getApplicationDocumentsDirectory();
    preferencesPath.value = docDir.path;
  }

  /// 备份路径（可自定义到任意云盘目录，如 /阿里云盘/xlist备份）
  final backupPath = Get.find<PreferencesStorage>().backupPath.val.obs;

  /// 备份数据库到 alist 服务器
  Future<void> backupToAlist() async {
    final s = serverInfo.value;
    if (s.url.isEmpty) {
      SmartDialog.showToast('请先配置服务器');
      return;
    }

    final dir = backupPath.value;
    if (dir.isEmpty || dir == '/') {
      SmartDialog.showToast('请先设置备份路径(不能为根目录)');
      return;
    }

    SmartDialog.showLoading(msg: '正在备份到 $dir ...');
    try {
      final url = s.url.endsWith('/') ? s.url : '${s.url}/';
      final auth = base64Encode(utf8.encode('${s.username}:${s.password}'));
      final dio = Dio(BaseOptions(
        headers: {'Authorization': 'Basic $auth'},
        connectTimeout: const Duration(seconds: 30),
      ));

      final dbFile = File(databasePath.value);
      if (!await dbFile.exists()) {
        SmartDialog.dismiss();
        SmartDialog.showToast('数据库文件不存在');
        return;
      }

      final path = dir.startsWith('/') ? dir : '/$dir';
      // 同时存 latest + 时间戳版本
      final now = DateTime.now();
      final ts = '${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}_'
          '${now.hour.toString().padLeft(2,'0')}${now.minute.toString().padLeft(2,'0')}';
      final bytes = await dbFile.readAsBytes();
      await dio.put('${url}dav$path/xlist_backup_latest.db', data: bytes);
      await dio.put('${url}dav$path/xlist_backup_$ts.db', data: bytes);
      SmartDialog.dismiss();
      SmartDialog.showToast('备份成功！$path/ (latest + $ts)');
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('备份失败: $e');
    }
  }

  /// 从 alist 服务器恢复数据库（关闭数据库 → 覆盖文件 → 硬重启）
  Future<void> restoreFromAlist() async {
    final s = serverInfo.value;
    if (s.url.isEmpty) {
      SmartDialog.showToast('请先配置服务器');
      return;
    }

    final dir = backupPath.value;
    if (dir.isEmpty || dir == '/') {
      SmartDialog.showToast('请先设置备份路径(不能为根目录)');
      return;
    }

    final ok = await showOkCancelAlertDialog(
      context: Get.overlayContext!,
      title: '恢复数据',
      message: '将从 $dir/xlist_backup_latest.db 下载并覆盖本地数据，应用将重新启动。确定继续？',
      okLabel: '确定',
      cancelLabel: '取消',
    );
    if (ok != OkCancelResult.ok) return;

    SmartDialog.showLoading(msg: '正在恢复...');
    try {
      final url = s.url.endsWith('/') ? s.url : '${s.url}/';
      final auth = base64Encode(utf8.encode('${s.username}:${s.password}'));
      final dio = Dio(BaseOptions(
        headers: {'Authorization': 'Basic $auth'},
        connectTimeout: const Duration(seconds: 30),
      ));

      final path = dir.startsWith('/') ? dir : '/$dir';
      final response = await dio.get('${url}dav$path/xlist_backup_latest.db',
          options: Options(responseType: ResponseType.bytes));

      // 1. 关闭当前数据库（释放文件锁）
      await DatabaseService.to.close();

      // 2. 清理 WAL/SHM 日志文件，避免旧数据残留
      final dbFile = File(databasePath.value);
      try { await File('${databasePath.value}-wal').delete(); } catch (_) {}
      try { await File('${databasePath.value}-shm').delete(); } catch (_) {}

      // 3. 覆盖数据库文件（flush: true 强制写入磁盘）
      await dbFile.writeAsBytes(response.data, flush: true);

      // 4. 验证写入成功
      final writtenSize = await dbFile.length();
      if (writtenSize != response.data.length) {
        throw Exception('文件写入不完整: $writtenSize / ${response.data.length}');
      }

      SmartDialog.dismiss();
      SmartDialog.showToast('恢复成功(${(writtenSize/1024).toStringAsFixed(0)}KB)，正在重启...');
      // 5. 硬重启（确保 Floor 重新加载数据库）
      await Future.delayed(const Duration(seconds: 3));
      exit(0);
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('恢复失败: $e');
    }
  }

  /// 更换主题
  void changeTheme() async {
    final value = await showModalActionSheet(
      context: Get.overlayContext!,
      actions: [
        SheetAction(label: '跟随系统', key: 'system'),
        SheetAction(label: '明亮', key: 'light'),
        SheetAction(label: '深邃', key: 'dark'),
      ],
      cancelLabel: '取消',
    );

    if (value != null) {
      Get.changeThemeMode(ThemeModeMap[value]!);
      themeModeText.value = ThemeModeTextMap[value]!;
      Get.find<CommonStorage>().themeMode.val = value;
      Future.delayed(Duration(milliseconds: 200), () {
        Get.forceAppUpdate();
      });
    }
  }
}
