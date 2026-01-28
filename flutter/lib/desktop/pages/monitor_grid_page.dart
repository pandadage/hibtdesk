import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    _loadSettings();
    _fetchOnlineEmployees();
    _refreshTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      _fetchOnlineEmployees();
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        gridSize = prefs.getInt('monitor_grid_size') ?? 16;
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchOnlineEmployees() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString('admin_token');
      final List<String> pinnedIds = prefs.getStringList('monitor_pinned_ids') ?? [];
      
      Map<String, String> headers = {};
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.get(
        Uri.parse('$apiServer/employee/list?online_only=true'),
        headers: headers
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          if (mounted) {
            setState(() {
              List<dynamic> allOnline = data['employees'];
              // 如果没有收藏任何员工，则显示所有在线的（默认模式）
              // 如果有收藏，则只显示收藏且在线的
              if (pinnedIds.isEmpty) {
                onlineEmployees = allOnline;
              } else {
                onlineEmployees = allOnline.where((emp) {
                  return pinnedIds.contains(emp['employee_id'].toString());
                }).toList();
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Fetch online employees error: $e');
    }
  }

  void _connect(String employeeId) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        token = prefs.getString('admin_token');
        
        if (token == null) {
          BotToast.showText(text: '未登录，请先登录');
          return;
        }

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

  Widget _buildGridOption(int value) {
    final bool isSelected = gridSize == value;
    return InkWell(
      onTap: () {
        setState(() => gridSize = value);
        SharedPreferences.getInstance().then((prefs) {
          prefs.setInt('monitor_grid_size', value);
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey[300]!),
        ),
        child: Text(
          '$value 宫格',
          style: TextStyle(
            color: isSelected ? Colors.blue : Colors.grey[600],
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int crossAxisCount = 4;
    if (gridSize == 25) crossAxisCount = 5;
    if (gridSize == 36) crossAxisCount = 6;
    if (gridSize == 64) crossAxisCount = 8;

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
              // Grid Size Selector
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                   _buildGridOption(16),
                   SizedBox(width: 8),
                   _buildGridOption(25),
                   SizedBox(width: 8),
                   _buildGridOption(36),
                   SizedBox(width: 8),
                   _buildGridOption(64),
                ],
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
