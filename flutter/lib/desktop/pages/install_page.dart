import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:http/http.dart' as http;

class InstallPage extends StatefulWidget {
  const InstallPage({Key? key}) : super(key: key);

  @override
  State<InstallPage> createState() => _InstallPageState();
}

class _InstallPageState extends State<InstallPage> {
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DragToResizeArea(
      resizeEdgeSize: 8, // Use constant instead of stateGlobal to avoid init issues
      enableResizeEdges: windowManagerEnableResizeEdges,
      child: Scaffold(
        backgroundColor: Theme.of(context).cardColor, // Use card color for frame
        body: Column(
          children: [
             // Custom Simple Title Bar
             SizedBox(
               height: 32,
               child: Row(
                 children: [
                    Expanded(
                      child: GestureDetector(
                        onPanStart: (_) => windowManager.startDragging(),
                        child: Container(
                          color: Colors.transparent, // Hit test target
                          padding: EdgeInsets.only(left: 10),
                          alignment: Alignment.centerLeft,
                          child: Text("HibtDesk Installation", 
                             style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                      )
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 16),
                      onPressed: () {
                         windowManager.close();
                         // Ensure process exit if needed, though close should suffice for main window
                      },
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(minWidth: 40, minHeight: 32),
                      splashRadius: 16,
                    ),
                 ],
               ),
             ),
             Expanded(child: _InstallPageBody()),
          ],
        ),
      ),
    );
  }
}

class _InstallPageBody extends StatefulWidget {
  const _InstallPageBody({Key? key}) : super(key: key);

  @override
  State<_InstallPageBody> createState() => _InstallPageBodyState();
}

class _InstallPageBodyState extends State<_InstallPageBody>
    with WindowListener {
  late final TextEditingController controller;
  // Employee ID Controller
  final TextEditingController employeeIdController = TextEditingController();
  
  // Hardcoded options as per request (disabled/false)
  final RxBool startmenu = false.obs;
  final RxBool desktopicon = false.obs;
  final RxBool printer = false.obs;
  
  final RxBool showProgress = false.obs;
  final RxBool btnEnabled = true.obs;

  _InstallPageBodyState() {
    String drive = Platform.environment['SystemDrive'] ?? 'C:';
    controller = TextEditingController(text: "$drive\\HibtDesk");
    // Ignore existing options, force defaults
  }
  
  // todo move to theme.
  final buttonStyle = OutlinedButton.styleFrom(
    textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
    padding: EdgeInsets.symmetric(vertical: 15, horizontal: 12),
  );

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    gFFI.close();
    super.onWindowClose();
    windowManager.setPreventClose(false);
    windowManager.close();
  }

  InkWell Option(RxBool option, {String label = ''}) {
    return InkWell(
      // todo mouseCursor: "SystemMouseCursors.forbidden" or no cursor on btnEnabled == false
      borderRadius: BorderRadius.circular(6),
      onTap: () => btnEnabled.value ? option.value = !option.value : null,
      child: Row(
        children: [
          Obx(
            () => Checkbox(
              visualDensity: VisualDensity(horizontal: -4, vertical: -4),
              value: option.value,
              onChanged: (v) =>
                  btnEnabled.value ? option.value = !option.value : null,
            ).marginOnly(right: 8),
          ),
          Expanded(
            child: Text(translate(label)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double em = 13;
    final isDarkTheme = MyTheme.currentThemeMode() == ThemeMode.dark;
    return Scaffold(
        backgroundColor: null,
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(translate('Installation'),
                  style: Theme.of(context).textTheme.headlineMedium),
              // Installation Path Hidden as requested
              // Row(
              //   children: [
              //     Text('${translate('Installation Path')}:').marginOnly(right: 10),
              //     Expanded(
              //       child: TextField(
              //         controller: controller,
              //         readOnly: true,
              //         decoration: InputDecoration(
              //           contentPadding: EdgeInsets.all(0.75 * em),
              //         ),
              //       ).workaroundFreezeLinuxMint().marginOnly(right: 10),
              //     ),
              //   ],
              // ).marginSymmetric(vertical: 2 * em),
              SizedBox(height: 1 * em),

              // Employee ID Input
              Row(
                children: [
                  Text('员工工号:').marginOnly(right: 10, left: 30), // Align rough with Install Path
                  Expanded(
                    child: TextField(
                      controller: employeeIdController,
                      decoration: InputDecoration(
                        hintText: "请输入有效工号进行验证",
                        contentPadding: EdgeInsets.all(0.75 * em),
                        border: OutlineInputBorder(),
                      ),
                    ).workaroundFreezeLinuxMint().marginOnly(right: 10),
                  ),
                ],
              ).marginOnly(bottom: 2 * em),

              // Removed Options (Start Menu, Desktop Icon, Printer) as requested

              Row(
                children: [
                  Expanded(
                    // NOT use Offstage to wrap LinearProgressIndicator
                    child: Obx(() => showProgress.value
                        ? LinearProgressIndicator().marginOnly(right: 10)
                        : Offstage()),
                  ),
                  Obx(
                    () => OutlinedButton.icon(
                      icon: Icon(Icons.close_rounded, size: 16),
                      label: Text(translate('Cancel')),
                      onPressed:
                          btnEnabled.value ? () => windowManager.close() : null,
                      style: buttonStyle,
                    ).marginOnly(right: 10),
                  ),
                  Obx(
                    () => ElevatedButton.icon(
                      icon: Icon(Icons.done_rounded, size: 16),
                      label: Text(translate('Accept and Install')),
                      onPressed: btnEnabled.value ? install : null,
                      style: buttonStyle,
                    ),
                  ),
                  Offstage(
                    offstage: true, // Always hide "Run without install"
                    child: Obx(
                      () => OutlinedButton.icon(
                        icon: Icon(Icons.screen_share_outlined, size: 16),
                        label: Text(translate('Run without install')),
                        onPressed: btnEnabled.value
                            ? () => bind.installRunWithoutInstall()
                            : null,
                        style: buttonStyle,
                      ).marginOnly(left: 10),
                    ),
                  ),
                ],
              )
            ],
          ).paddingSymmetric(horizontal: 4 * em, vertical: 3 * em),
        ));
  }

  Future<void> install() async {
    final employeeId = employeeIdController.text.trim();
    if (employeeId.isEmpty) {
      BotToast.showText(text: "请输入员工工号");
      return;
    }

    btnEnabled.value = false;
    showProgress.value = true;

    // Verify Employee ID
    bool isValid = await _verifyEmployeeId(employeeId);
    if (!isValid) {
      BotToast.showText(text: "工号无效或不在员工列表中，禁止安装");
      btnEnabled.value = true;
      showProgress.value = false;
      return;
    }

    String args = '';
    // Always false/disabled as per request
    // if (startmenu.value) args += ' startmenu';
    // if (desktopicon.value) args += ' desktopicon';
    // if (printer.value) args += ' printer';
    
    // Write Employee ID to config
    await bind.mainSetOption(key: "employee_id", value: employeeId);
    
    bind.installInstallMe(options: args, path: controller.text);
  }

  Future<bool> _verifyEmployeeId(String id) async {
    try {
      // API call to verify employee
      // 演示: 如果ID是 '8888' 或者在列表中存在则通过
      // 真实逻辑: GET http://38.181.2.76:3000/api/public/check-employee/$id
      
      final url = Uri.parse("http://38.181.2.76:3000/api/public/check-employee/$id");
      // Use a timeout to avoid hanging
      final response = await http.get(url).timeout(Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Assuming API returns { "success": true, "exists": true } or similar
        // Adjust based on real API. Assuming 200 OK means found for now, 
        // or check data['success']
        return data['success'] == true;
      }
      return false; 
    } catch (e) {
      debugPrint("Verify failed: $e");
      // Fallback for demo/offline testing if configured?
      // Strict mode: fail
      return false;
    }
  }

  void selectInstallPath() async {
    String? install_path = await FilePicker.platform
        .getDirectoryPath(initialDirectory: controller.text);
    if (install_path != null) {
      controller.text = join(install_path, await bind.mainGetAppName());
    }
  }
}
