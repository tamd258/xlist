import 'dart:io';

import 'package:get/get.dart';
import 'package:keframe/keframe.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/material.dart' hide SearchController;
import 'package:pull_down_button/pull_down_button.dart';
import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:xlist/common/index.dart';
import 'package:xlist/helper/index.dart';
import 'package:xlist/models/index.dart';
import 'package:xlist/constants/index.dart';
import 'package:xlist/repositorys/index.dart';
import 'package:xlist/routes/app_pages.dart';
import 'package:xlist/pages/search/index.dart';
import 'package:xlist/components/object_grid/object_grid_item.dart';
import 'package:xlist/components/object_list/object_list_item.dart';

class SearchPage extends GetView<SearchController> {
  const SearchPage({Key? key}) : super(key: key);

  /// 去掉 basePath 前缀
  String _stripBase(String p) {
    final basePath = controller.userInfo.value.basePath ?? '/';
    if (basePath != '/' && p.startsWith(basePath)) {
      return p.replaceFirst(RegExp(basePath), '');
    }
    return p;
  }

  /// 跳转到目录页 (用于 "所在目录")
  void _jumpToParent(FsSearchModel s) {
    final parent = _stripBase(s.parent ?? '/');
    if (parent.isEmpty || parent == '/') {
      // 根目录, 返回上级
      Get.back();
      return;
    }
    final lastSlash = parent.lastIndexOf('/');
    final dirPath = lastSlash <= 0 ? '/' : parent.substring(0, lastSlash + 1);
    final dirName = parent.substring(lastSlash + 1);
    ObjectHelper.click(
      path: dirPath,
      type: FileType.FOLDER,
      name: dirName,
    );
  }

  /// 处理点击 (普通模式)
  void _onItemTap(FsSearchModel s) {
    final path = _stripBase(s.parent ?? '/');
    ObjectHelper.click(
      path: '${path == '/' ? '' : path}/',
      type: s.type!,
      name: s.name!,
      objects: [
        ObjectModel.fromJson({
          'name': s.name,
          'type': s.type,
          'is_dir': s.isDir,
          'size': s.size,
        }),
      ],
    );
  }

  /// 显示文件属性
  void _showProperties(FsSearchModel s) {
    showCupertinoModalPopup(
      context: Get.context!,
      builder: (ctx) {
        return Container(
          height: Get.height * .45,
          color: CommonUtils.backgroundColor,
          padding: EdgeInsets.all(20.r),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    'properties'.tr,
                    style: Get.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(height: 20.h),
                _propRow(s.name ?? '', label: 'rename'.tr),
                _propRow(
                  s.isDir == true ? 'directory'.tr : 'file_type'.tr,
                  label: 'file_type'.tr,
                ),
                _propRow(
                  s.isDir == true
                      ? '-'
                      : CommonUtils.formatFileSize(s.size ?? 0),
                  label: 'file_size'.tr,
                ),
                _propRow(s.parent ?? '', label: 'parent_path'.tr),
                Spacer(),
                CupertinoButton.filled(
                  child: Text('close'.tr),
                  onPressed: () => Get.back(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _propRow(String value, {required String label}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.r),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 200.w,
            child: Text(label,
                style: Get.textTheme.bodyMedium
                    ?.copyWith(color: CupertinoColors.systemGrey)),
          ),
          Expanded(child: Text(value, style: Get.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  /// 批量删除
  Future<void> _batchDelete() async {
    final items = controller.selectedItems;
    if (items.isEmpty) {
      SmartDialog.showToast('toast_no_selection'.tr);
      return;
    }
    final ok = await showOkCancelAlertDialog(
      context: Get.context!,
      title: 'dialog_prompt_title'.tr,
      message: 'dialog_remove_message'.tr,
      okLabel: 'confirm'.tr,
      cancelLabel: 'cancel'.tr,
    );
    if (ok != OkCancelResult.ok) return;

    SmartDialog.showLoading();
    int count = 0;
    try {
      for (final item in items) {
        final response = await ObjectRepository.remove(
          path: item.parent ?? '/',
          name: item.name ?? '',
        );
        if (response['code'] == HttpStatus.ok) count++;
      }
      SmartDialog.dismiss();
      SmartDialog.showToast(
          'toast_remove_batch'.tr.replaceAll('@count', '$count'));
      await controller.refreshList();
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast(e.toString());
    }
  }

  /// 批量移动 / 复制
  void _batchMoveOrCopy({required bool isCopy}) {
    final items = controller.selectedItems;
    if (items.isEmpty) {
      SmartDialog.showToast('toast_no_selection'.tr);
      return;
    }
    final srcItems = items
        .map((s) => {'srcDir': s.parent ?? '/', 'name': s.name ?? ''})
        .toList();

    Get.toNamed(Routes.DIRECTORY, arguments: {
      'srcItems': srcItems,
      // 兼容字段
      'srcDir': items.first.parent ?? '/',
      'srcObject': ObjectModel.fromJson({
        'name': items.first.name,
        'type': items.first.type,
        'is_dir': items.first.isDir,
        'size': items.first.size,
      }),
      'root': true,
      'isCopy': isCopy,
      'tag': 'search',
      'source': '',
    })?.then((_) => controller.refreshList());
  }

  /// 重命名 (单个)
  Future<void> _renameSingle() async {
    final items = controller.selectedItems;
    if (items.length != 1) {
      SmartDialog.showToast('toast_select_one_only'.tr);
      return;
    }
    final s = items.first;

    final data = await showTextInputDialog(
      context: Get.context!,
      title: 'dialog_rename_title'.tr,
      message: 'dialog_rename_message'.tr,
      okLabel: 'confirm'.tr,
      cancelLabel: 'cancel'.tr,
      textFields: [
        DialogTextField(
            hintText: 'dialog_rename_hint'.tr, initialText: s.name),
      ],
    );
    if (data == null || data.isEmpty) return;

    SmartDialog.showLoading();
    try {
      final parent = s.parent ?? '/';
      final fullPath =
          parent.endsWith('/') ? '$parent${s.name}' : '$parent/${s.name}';
      final response = await ObjectRepository.rename(
        path: fullPath,
        name: data.first,
      );
      if (response['code'] != HttpStatus.ok) {
        throw response['message'];
      }
      SmartDialog.dismiss();
      SmartDialog.showToast('toast_rename_success'.tr);
      await controller.refreshList();
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast(e.toString());
    }
  }

  /// 显示所在目录 (单个)
  void _showLocationSingle() {
    final items = controller.selectedItems;
    if (items.length != 1) {
      SmartDialog.showToast('toast_select_one_only'.tr);
      return;
    }
    controller.exitSelection();
    _jumpToParent(items.first);
  }

  /// 属性 (单个)
  void _showPropertiesSingle() {
    final items = controller.selectedItems;
    if (items.length != 1) {
      SmartDialog.showToast('toast_select_one_only'.tr);
      return;
    }
    _showProperties(items.first);
  }

  /// ============ UI ============

  /// 排序按钮 (PullDown)
  Widget _buildSortButton() {
    final sortType = controller.sortType.value;
    return PullDownButton(
      itemBuilder: (context) => [
        PullDownMenuItem(
          title: 'pull_down_name'.tr,
          icon: [SortType.NAME_DESC, SortType.NAME_ASC].contains(sortType)
              ? (sortType == SortType.NAME_DESC
                  ? CupertinoIcons.chevron_down
                  : CupertinoIcons.chevron_up)
              : null,
          onTap: () => controller.setSortType(sortType == SortType.NAME_ASC
              ? SortType.NAME_DESC
              : SortType.NAME_ASC),
        ),
        PullDownMenuItem(
          title: 'pull_down_size'.tr,
          icon: [SortType.SIZE_DESC, SortType.SIZE_ASC].contains(sortType)
              ? (sortType == SortType.SIZE_DESC
                  ? CupertinoIcons.chevron_down
                  : CupertinoIcons.chevron_up)
              : null,
          onTap: () => controller.setSortType(sortType == SortType.SIZE_DESC
              ? SortType.SIZE_ASC
              : SortType.SIZE_DESC),
        ),
        PullDownMenuDivider.large(),
        PullDownMenuItem(
          title: 'select'.tr,
          icon: CupertinoIcons.checkmark_circle,
          onTap: () => controller.enterSelection(),
        ),
      ],
      buttonBuilder: (context, showMenu) => CupertinoButton(
        onPressed: showMenu,
        padding: EdgeInsets.zero,
        child: Icon(
          CupertinoIcons.ellipsis_circle,
          size: CommonUtils.navIconSize,
        ),
      ),
    );
  }

  /// 顶部搜索栏
  Widget _buildSearchBar() {
    return SliverToBoxAdapter(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: CommonUtils.isPad ? 20 : 50.w)
            .copyWith(bottom: 20.h),
        child: Obx(() {
          final inSelection = controller.selectionMode.value;
          if (inSelection) {
            // 选择模式头部
            final total = controller.searchList.length;
            final count = controller.selectedIndexes.length;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: Text(count == total && total > 0
                      ? 'unselect_all'.tr
                      : 'select_all'.tr),
                  onPressed: controller.toggleSelectAll,
                ),
                Text(
                  'selected_count'.tr.replaceAll('@count', '$count'),
                  style: Get.textTheme.bodyLarge,
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: Text('cancel_select'.tr),
                  onPressed: controller.exitSelection,
                ),
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: CommonUtils.isPad ? Get.width - 180 : 720.w,
                child: CupertinoSearchTextField(
                  placeholder: 'search'.tr,
                  autofocus: true,
                  controller: controller.searchController,
                  style: Get.textTheme.bodyLarge,
                  onChanged: controller.onChanged,
                ),
              ),
              _buildSortButton(),
              Container(
                width: CommonUtils.isPad ? 50 : 100.w,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerRight,
                  child: Text('cancel'.tr),
                  onPressed: () => Get.back(),
                ),
              )
            ],
          );
        }),
      ),
    );
  }

  /// 单项构建 - 列表
  Widget _buildListTile(int index) {
    final s = controller.searchList[index];
    final inSelection = controller.selectionMode.value;
    final selected = controller.selectedIndexes.contains(index);

    final tile = Row(
      children: [
        if (inSelection)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.r),
            child: Icon(
              selected
                  ? CupertinoIcons.checkmark_square_fill
                  : CupertinoIcons.square,
              color: selected
                  ? Get.theme.primaryColor
                  : CupertinoColors.systemGrey,
              size: CommonUtils.isPad ? 24 : 60.sp,
            ),
          ),
        Expanded(
          child: ObjectListItem(
            isShowPreview: controller.isShowPreview.value,
            object: ObjectModel.fromJson({
              'name': s.name,
              'type': s.type,
              'is_dir': s.isDir,
              'size': s.size,
            }),
          ),
        ),
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        if (inSelection) {
          await HapticFeedback.selectionClick();
          controller.toggleSelect(index);
        } else {
          _onItemTap(s);
        }
      },
      onLongPress: () async {
        await HapticFeedback.mediumImpact();
        if (!controller.selectionMode.value) {
          controller.enterSelection(initialIndex: index);
        }
      },
      child: Column(
        children: [
          tile,
          Container(
            padding: EdgeInsets.only(top: 20.r),
            child: Divider(
                height: 1.r,
                indent: inSelection ? 280.r : 190.r,
                endIndent: 15.r),
          ),
        ],
      ),
    );
  }

  /// 网格构建项
  Widget _buildGridTile(int index) {
    final s = controller.searchList[index];
    final inSelection = controller.selectionMode.value;
    final selected = controller.selectedIndexes.contains(index);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        if (inSelection) {
          await HapticFeedback.selectionClick();
          controller.toggleSelect(index);
        } else {
          _onItemTap(s);
        }
      },
      onLongPress: () async {
        await HapticFeedback.mediumImpact();
        if (!controller.selectionMode.value) {
          controller.enterSelection(initialIndex: index);
        }
      },
      child: Stack(
        children: [
          ObjectGridItem(
            isShowPreview: controller.isShowPreview.value,
            object: ObjectModel.fromJson({
              'name': s.name,
              'type': s.type,
              'is_dir': s.isDir,
              'size': s.size,
            }),
          ),
          if (inSelection)
            Positioned(
              top: 5,
              right: 5,
              child: Icon(
                selected
                    ? CupertinoIcons.checkmark_square_fill
                    : CupertinoIcons.square,
                color: selected
                    ? Get.theme.primaryColor
                    : CupertinoColors.systemGrey,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSliverList() {
    if (CommonUtils.isPad) {
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: 5),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.0,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) =>
                FrameSeparateWidget(index: index, child: _buildGridTile(index)),
            childCount: controller.searchList.length,
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) =>
            FrameSeparateWidget(index: index, child: _buildListTile(index)),
        childCount: controller.searchList.length,
      ),
    );
  }

  /// 底部操作栏
  Widget _buildActionBar() {
    return Obx(() {
      if (!controller.selectionMode.value) return SizedBox.shrink();
      final hasAny = controller.selectedIndexes.isNotEmpty;
      final isOne = controller.selectedIndexes.length == 1;

      Widget action(IconData icon, String label, VoidCallback? onTap) {
        final enabled = onTap != null;
        return Expanded(
          child: CupertinoButton(
            padding: EdgeInsets.symmetric(vertical: 10.r),
            onPressed: enabled ? onTap : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: CommonUtils.isPad ? 22 : 50.sp,
                    color: enabled
                        ? Get.theme.primaryColor
                        : CupertinoColors.systemGrey),
                SizedBox(height: 4.h),
                Text(label,
                    style: Get.textTheme.bodySmall?.copyWith(
                        color: enabled
                            ? Get.theme.primaryColor
                            : CupertinoColors.systemGrey)),
              ],
            ),
          ),
        );
      }

      final user = controller.userInfo.value;
      return Container(
        decoration: BoxDecoration(
          color: CommonUtils.backgroundColor,
          border: Border(
              top: BorderSide(color: CupertinoColors.separator, width: 0.3)),
        ),
        padding: EdgeInsets.symmetric(horizontal: 5.r, vertical: 5.r),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              action(
                CupertinoIcons.doc_on_doc,
                'copy'.tr,
                hasAny && PermissionHelper.canCopy(user)
                    ? () => _batchMoveOrCopy(isCopy: true)
                    : null,
              ),
              action(
                CupertinoIcons.folder,
                'move'.tr,
                hasAny && PermissionHelper.canMove(user)
                    ? () => _batchMoveOrCopy(isCopy: false)
                    : null,
              ),
              action(
                CupertinoIcons.location,
                'show_location'.tr,
                isOne ? _showLocationSingle : null,
              ),
              action(
                CupertinoIcons.info,
                'properties'.tr,
                isOne ? _showPropertiesSingle : null,
              ),
              action(
                CupertinoIcons.pencil,
                'rename'.tr,
                isOne && PermissionHelper.canRename(user) ? _renameSingle : null,
              ),
              action(
                CupertinoIcons.trash,
                'delete'.tr,
                hasAny && PermissionHelper.canDelete(user) ? _batchDelete : null,
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildCustomScrollView() {
    return CustomScrollView(
      shrinkWrap: false,
      physics: GetPlatform.isAndroid ? BouncingScrollPhysics() : null,
      controller: controller.scrollController,
      slivers: <Widget>[
        _buildSearchBar(),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 30.r),
          sliver: SizeCacheWidget(
            child: Obx(() {
              // 读取 selectionMode 和 selectedIndexes 以触发重建
              final _ = controller.selectionMode.value;
              final __ = controller.selectedIndexes.length;
              return _buildSliverList();
            }),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildCustomScrollView()),
            _buildActionBar(),
          ],
        ),
      ),
    );
  }
}
