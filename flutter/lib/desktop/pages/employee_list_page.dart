import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:provider/provider.dart';
import 'package:bot_toast/bot_toast.dart';

class EmployeeListPage extends StatefulWidget {
  const EmployeeListPage({Key? key}) : super(key: key);

  @override
  _EmployeeListPageState createState() => _EmployeeListPageState();
}

class _EmployeeListPageState extends State<EmployeeListPage> {
  List<dynamic> employees = [];
  String _searchQuery = '';
  bool isLoading = false;
  Timer? _timer;
  String? token; // 需要实现登录逻辑获取 token

  // TODO: 从配置中获取 API 地址
  final String apiServer = "http://38.181.2.76:3000/api";

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
    _timer = Timer.periodic(Duration(seconds: 30), (timer) {
      _fetchEmployees();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchEmployees() async {
    // 暂时不需要 Token 即可获取列表 (假设 API 已调整或演示模式)
    // 或者需要先实现登录。此处简化，假设 API 允许匿名访问或已经在其他地方登录。
    try {
      final response = await http.get(Uri.parse('$apiServer/employee/list'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            employees = data['employees'];
          });
        }
      }
    } catch (e) {
      print('Fetch employees error: $e');
    }
  }
  
  Future<void> _connect(String employeeId, {bool isFileTransfer = false}) async {
    // 获取员工详情（包含连接密码）
    try {
      // 需要管理员 token。这里先硬编码或者需要先登录。
      // 为了演示，假设后端 API /employee/:id 不需要 auth (或者我们需要先实现登录)
      // 在实际生产中，必须先登录。
      
      // 临时：模拟登录获取 token (硬编码 admin/admin123)
      if (token == null) {
        final loginRes = await http.post(
          Uri.parse('$apiServer/admin/login'),
          body: json.encode({'username': 'admin', 'password': 'admin123'}), // 默认密码
          headers: {'Content-Type': 'application/json'},
        );
        if (loginRes.statusCode == 200) {
           final loginData = json.decode(loginRes.body);
           if (loginData['success']) {
             token = loginData['token'];
           }
        }
      }
      
      if (token == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('需要管理员登录')));
        return;
      }

      final response = await http.get(
        Uri.parse('$apiServer/employee/$employeeId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          final emp = data['employee'];
          String deviceId = emp['device_id'];
          String password = emp['device_password'];
          
          // 调用 RustDesk 连接
          connect(context, deviceId, password: password, isFileTransfer: isFileTransfer);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('连接失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredEmployees = employees.where((emp) {
      final query = _searchQuery.toLowerCase();
      final id = emp['employee_id'].toString().toLowerCase();
      final name = emp['employee_name'].toString().toLowerCase();
      return id.contains(query) || name.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: TextField(
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: '搜索工号或姓名...',
              hintStyle: TextStyle(color: Colors.white70),
              border: InputBorder.none,
              prefixIcon: Icon(Icons.search, color: Colors.white70),
              contentPadding: EdgeInsets.symmetric(vertical: 8.0), // Center vertically
            ),
            cursorColor: Colors.white,
          ),
        ),
        actions: [
          IconButton(icon: Icon(Icons.refresh), onPressed: _fetchEmployees),
        ],
      ),
      body: ListView.builder(
        itemCount: filteredEmployees.length,
        itemBuilder: (context, index) {
          final emp = filteredEmployees[index];
          final isOnline = emp['is_online'] == 1;
          return Card(
            margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: ListTile(
              leading: Stack(
                children: [
                   Icon(Icons.computer, size: 36, color: isOnline ? Colors.green : Colors.grey),
                   if (isOnline)
                     Positioned(right: 0, bottom: 0, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)))
                ],
              ),
              title: Text('${emp['employee_name']} (工号: ${emp['employee_id']})', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('设备: ${emp['device_name']} - ${emp['department'] ?? "无部门"}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Connect (Remote Control)
                  Tooltip(
                    message: "远程控制",
                    child: IconButton(
                      icon: Icon(Icons.desktop_windows, color: isOnline ? Colors.blue : Colors.grey),
                      onPressed: isOnline ? () => _connect(emp['employee_id'], isFileTransfer: false) : null,
                    ),
                  ),
                  
                  // 2. File Transfer
                  Tooltip(
                    message: "文件传输",
                    child: IconButton(
                      icon: Icon(Icons.folder_shared, color: isOnline ? Colors.orange : Colors.grey),
                      onPressed: isOnline ? () => _connect(emp['employee_id'], isFileTransfer: true) : null,
                    ),
                  ),

                  // 3. Monitor Wall (Add)
                  Tooltip(
                    message: "加入监控墙",
                    child: IconButton(
                      icon: Icon(Icons.dashboard_customize, color: isOnline ? Colors.purple : Colors.grey),
                      onPressed: isOnline ? () {
                         BotToast.showText(text: "已添加到监控墙");
                         // TODO: Update global state for Monitor Grid
                      } : null,
                    ),
                  ),

                  // 4. View Recordings (via File Transfer to specific path or special API)
                  Tooltip(
                    message: "查看录像",
                    child: IconButton(
                      icon: Icon(Icons.video_library, color: isOnline ? Colors.redAccent : Colors.grey),
                      onPressed: isOnline ? () => _connect(emp['employee_id'], isFileTransfer: true) : null, // Re-use FT for now, ideally navigate to C:\EmployeeRecords
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
