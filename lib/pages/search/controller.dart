import 'package:get/get.dart';
import 'package:flutter/material.dart';

import 'package:xlist/models/index.dart';
import 'package:xlist/services/index.dart';
import 'package:xlist/storages/index.dart';
import 'package:xlist/repositorys/index.dart';
import 'package:xlist/constants/index.dart';

class SearchController extends GetxController {
  static const pageSize = 100;
  final userInfo = UserModel().obs; // 用户信息
  final searchList = <FsSearchModel>[].obs; // Object 数据
  final serverId = Get.find<UserStorage>().serverId.val;

  // 显示预览图
  final isShowPreview = Get.find<PreferencesStorage>().isShowPreview.val.obs;

  // 排序方式
  final sortType = Get.find<PreferencesStorage>().sortType.val.obs;

  // 选择模式
  final selectionMode = false.obs;
  // 已选索引集合
  final selectedIndexes = <int>{}.obs;

  TextEditingController searchController = TextEditingController();
  ScrollController scrollController = ScrollController();

  // 获取参数
  final String path = Get.arguments['path'];
  String password = ''; // 目录密码
  String _lastKeywords = '';

  @override
  void onInit() async {
    super.onInit();

    // 获取目录密码
    final passwordManager = await DatabaseService.to.database.passwordManagerDao
        .findPasswordManagerByPath(serverId, path);
    if (passwordManager != null && passwordManager.isNotEmpty) {
      password = passwordManager.last.password;
    }

    // 获取用户信息
    userInfo.value = await UserRepository.me();
  }

  /// 搜索
  void onChanged(String value) async {
    await getSearchObjectList(value);
  }

  /// 获取搜索数据
  Future<void> getSearchObjectList(String keywords) async {
    _lastKeywords = keywords;
    try {
      final response = await ObjectRepository.search(
        page: 1,
        pageSize: pageSize,
        password: password,
        keywords: keywords,
        parent: path,
      );

      // 退出选择模式
      exitSelection();

      searchList.clear();
      searchList.addAll(_sort(response));
      searchList.refresh();
    } catch (e) {}
  }

  /// 重新搜索 (用于刷新)
  Future<void> refreshList() async {
    if (_lastKeywords.isEmpty) return;
    await getSearchObjectList(_lastKeywords);
  }

  /// 切换排序方式
  Future<void> setSortType(int type) async {
    sortType.value = type;
    Get.find<PreferencesStorage>().sortType.val = type;
    final list = _sort(searchList.toList());
    searchList
      ..clear()
      ..addAll(list);
    searchList.refresh();
    // 排序后已选索引可能错位，清空
    exitSelection();
  }

  /// 排序
  List<FsSearchModel> _sort(List<FsSearchModel> list) {
    final folders = <FsSearchModel>[];
    final files = <FsSearchModel>[];
    for (final v in list) {
      (v.isDir == true) ? folders.add(v) : files.add(v);
    }

    int cmpName(FsSearchModel a, FsSearchModel b, {bool desc = false}) {
      final r = (a.name ?? '').compareTo(b.name ?? '');
      return desc ? -r : r;
    }

    int cmpSize(FsSearchModel a, FsSearchModel b, {bool desc = false}) {
      final r = (a.size ?? 0).compareTo(b.size ?? 0);
      return desc ? -r : r;
    }

    switch (sortType.value) {
      case SortType.NAME_DESC:
        folders.sort((a, b) => cmpName(a, b, desc: true));
        files.sort((a, b) => cmpName(a, b, desc: true));
        break;
      case SortType.SIZE_DESC:
        folders.sort((a, b) => cmpSize(a, b, desc: true));
        files.sort((a, b) => cmpSize(a, b, desc: true));
        break;
      case SortType.SIZE_ASC:
        folders.sort(cmpSize);
        files.sort(cmpSize);
        break;
      // 时间排序回退到名称升序 (搜索结果没有 modified 字段)
      case SortType.NAME_ASC:
      default:
        folders.sort(cmpName);
        files.sort(cmpName);
    }
    return [...folders, ...files];
  }

  // ============ 选择模式 ============

  void enterSelection({int? initialIndex}) {
    selectionMode.value = true;
    selectedIndexes.clear();
    if (initialIndex != null) selectedIndexes.add(initialIndex);
    selectedIndexes.refresh();
  }

  void exitSelection() {
    selectionMode.value = false;
    selectedIndexes.clear();
  }

  void toggleSelect(int index) {
    if (selectedIndexes.contains(index)) {
      selectedIndexes.remove(index);
    } else {
      selectedIndexes.add(index);
    }
    selectedIndexes.refresh();
  }

  void toggleSelectAll() {
    if (selectedIndexes.length == searchList.length) {
      selectedIndexes.clear();
    } else {
      selectedIndexes
        ..clear()
        ..addAll(List.generate(searchList.length, (i) => i));
    }
    selectedIndexes.refresh();
  }

  List<FsSearchModel> get selectedItems =>
      selectedIndexes.map((i) => searchList[i]).toList();
}
