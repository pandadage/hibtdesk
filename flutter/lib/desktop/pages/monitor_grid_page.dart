import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/common.dart';

class MonitorGridPage extends StatefulWidget {
  const MonitorGridPage({Key? key}) : super(key: key);

  @override
  _MonitorGridPageState createState() => _MonitorGridPageState();
}

class _MonitorGridPageState extends State<MonitorGridPage> {
  int gridSize = 16; // 默认 4x4 = 16
  List<dynamic> onlineEmployees = [];
  Timer? _refreshTimer;
  String? token;
  
  final String apiServer = "http://38.181.2.76:3000/api";

  @override
  void initState() {
    super.initState();
    _fetchOnlineEmployees();
    _refreshTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      _fetchOnlineEmployees();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchOnlineEmployees() async {
    try {
      // 获取 token (如果需要的话，这里暂时先直接请求，复用 EmployeeListPage 的逻辑更佳，但这里先简单处理)
      // 注意：这里使用的是 online_only=true，如果 API 需要 token，则必须先登录。
      // 为保持一致性，建议也检查 token。但 monitor wall 可能是公开的？
      // 根据之前的 API 分析，/api/employee/list 需要 authMiddleware。
      
      Map<String, String> headers = {};
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      } else {
        // 尝试自动登录获取 token
         await _autoLogin();
         if (token != null) headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.get(
        Uri.parse('$apiServer/employee/list?online_only=true'),
        headers: headers
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            onlineEmployees = data['employees'];
          });
        }
      }
    } catch (e) {
      print('Fetch online employees error: $e');
    }
  }

  Future<void> _autoLogin() async {
     try {
        final loginRes = await http.post(
          Uri.parse('$apiServer/admin/login'),
          body: json.encode({'username': 'admin', 'password': 'admin123'}),
          headers: {'Content-Type': 'application/json'},
        );
        if (loginRes.statusCode == 200) {
          final loginData = json.decode(loginRes.body);
          if (loginData['success']) {
            token = loginData['token'];
          }
        }
     } catch (e) {
       print("Auto login failed: $e");
     }
  }

  void _connect(String employeeId) async {
      try {
        if (token == null) await _autoLogin();
        if (token == null) return;

        final response = await http.get(
          Uri.parse('$apiServer/employee/$employeeId'),
          headers: {'Authorization': 'Bearer $token'}
        );
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success']) {
            final emp = data['employee'];
            // 连接并自动最大化窗口 (connect 方法通常会打开新窗口)
            connect(context, emp['device_id'], password: emp['device_password']);
          }
        }
      } catch (e) {
        print("Connect error: $e");
      }
  }

  @override
  Widget build(BuildContext context) {
    int crossAxisCount = 4;
    if (gridSize == 25) crossAxisCount = 5;
    if (gridSize == 36) crossAxisCount = 6;

    return Column(
      children: [
        // Custom Header
        Container(
          height: 60,
          padding: EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.dashboard_rounded, color: Colors.blue, size: 28),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '监控墙',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  Text(
                    '${onlineEmployees.length} 台设备在线',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              Spacer(),
              // Grid Size Selector
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: DropdownButton<int>(
                  value: gridSize,
                  underline: SizedBox(),
                  icon: Icon(Icons.grid_view, size: 20, color: Colors.grey[600]),
                  style: TextStyle(color: Colors.grey[800], fontSize: 14),
                  items: [
                    DropdownMenuItem(value: 16, child: Text('16 宫格')),
                    DropdownMenuItem(value: 25, child: Text('25 宫格')),
                    DropdownMenuItem(value: 36, child: Text('36 宫格')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => gridSize = v);
                  },
                ),
              ),
              SizedBox(width: 16),
              IconButton(
                onPressed: _fetchOnlineEmployees,
                icon: Icon(Icons.refresh, color: Colors.grey[600]),
                tooltip: '刷新',
              ),
            ],
          ),
        ),
        
        // Grid Content
        Expanded(
          child: Container(
            color: Colors.grey[100],
            padding: EdgeInsets.all(8),
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 1.6,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: gridSize,
              itemBuilder: (context, index) {
                if (index < onlineEmployees.length) {
                  final emp = onlineEmployees[index];
                  return _buildMonitorCard(emp);
                } else {
                  return _buildEmptyCard();
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMonitorCard(dynamic emp) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: Colors.black,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _connect(emp['employee_id']),
        onHover: (value) {}, // TODO: Add hover effect
        child: Stack(
          children: [
            // Placeholder for screen stream
            // 实际项目中这里应该是实时画面流，现在仅显示图标
            Center(
              child: Icon(Icons.desktop_windows, size: 48, color: Colors.white24),
            ),
            
            // Online Indicator
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    ),
                    SizedBox(width: 4),
                    Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            
            // Bottom Info Bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emp['employee_name'] ?? 'Unknown',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      "${emp['department'] ?? ''} - ${emp['employee_id']}",
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[400]!),
      ),
      child: Center(
        child: Icon(Icons.add_to_queue, color: Colors.grey[500], size: 32),
      ),
    );
  }
}
