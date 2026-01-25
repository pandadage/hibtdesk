import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:provider/provider.dart';

class EmployeeListPage extends StatefulWidget {
  const EmployeeListPage({Key? key}) : super(key: key);

  @override
  _EmployeeListPageState createState() => _EmployeeListPageState();
}

class _EmployeeListPageState extends State<EmployeeListPage> {
  List<dynamic> employees = [];
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
  
  Future<void> _connect(String employeeId) async {
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
          Provider.of<ServerModel>(context, listen: false).connect(deviceId, password: password);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('连接失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('员工列表'),
        actions: [
          IconButton(icon: Icon(Icons.refresh), onPressed: _fetchEmployees),
        ],
      ),
      body: ListView.builder(
        itemCount: employees.length,
        itemBuilder: (context, index) {
          final emp = employees[index];
          final isOnline = emp['is_online'] == 1;
          return ListTile(
            leading: Icon(Icons.computer, color: isOnline ? Colors.green : Colors.grey),
            title: Text('${emp['employee_name']} (工号: ${emp['employee_id']})'),
            subtitle: Text('设备: ${emp['device_name']} - ${emp['department'] ?? "无部门"}'),
            trailing: ElevatedButton(
              onPressed: isOnline ? () => _connect(emp['employee_id']) : null,
              child: Text('连接'),
            ),
          );
        },
      ),
    );
  }
}
