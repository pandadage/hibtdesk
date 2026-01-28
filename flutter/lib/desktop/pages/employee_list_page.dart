import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:provider/provider.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmployeeListPage extends StatefulWidget {
  const EmployeeListPage({Key? key}) : super(key: key);

  @override
  _EmployeeListPageState createState() => _EmployeeListPageState();
}

class _EmployeeListPageState extends State<EmployeeListPage> {
  List<dynamic> employees = [];
  String _searchQuery = '';
  bool isLoading = true;
  String? errorMessage;
  Timer? _timer;
  String? token;
  List<String> pinnedIds = [];
  List<String> departments = ['全部部门'];
  String selectedDepartment = '全部部门';

  final String apiServer = "http://38.181.2.76:3000/api";

  @override
  void initState() {
    super.initState();
    _loadPinnedIds();
    _fetchDepartments();
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

  Future<void> _loadPinnedIds() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        pinnedIds = prefs.getStringList('monitor_pinned_ids') ?? [];
      });
    }
  }

  Future<void> _togglePin(String id) async {
    final prefs = await SharedPreferences.getInstance();
    if (pinnedIds.contains(id)) {
      pinnedIds.remove(id);
    } else {
      pinnedIds.add(id);
    }
    await prefs.setStringList('monitor_pinned_ids', pinnedIds);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _fetchDepartments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('admin_token');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$apiServer/department/list'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          List<dynamic> deptList = data['departments'];
          List<String> depts = ['全部部门'];
          depts.addAll(deptList.map((d) => d['name'].toString()).toList());
          
          if (mounted) {
            setState(() {
              departments = depts;
              if (!departments.contains(selectedDepartment)) {
                selectedDepartment = '全部部门';
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Fetch departments error: $e');
    }
  }

  Future<void> _fetchEmployees() async {
    if (!mounted) return;
    
    try {
      // 获取存储的 token
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString('admin_token');

      if (token == null) {
        if (mounted) {
          setState(() {
            isLoading = false;
            errorMessage = '未登录，请先登录管理员账号';
          });
        }
        return;
      }
      
      if (token == null) {
        if (mounted) {
          setState(() {
            isLoading = false;
            errorMessage = '管理员登录失败';
          });
        }
        return;
      }
      
      final response = await http.get(
        Uri.parse('$apiServer/employee/list'),
        headers: {'Authorization': 'Bearer $token'},
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          if (mounted) {
            setState(() {
              employees = data['employees'] ?? [];
              isLoading = false;
              errorMessage = null;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              isLoading = false;
              errorMessage = data['message'] ?? '获取员工列表失败';
            });
          }
        }
      } else if (response.statusCode == 401) {
        // Token 过期，清除并重试
        token = null;
        if (mounted) {
          setState(() {
            isLoading = false;
            errorMessage = 'Token已过期，请刷新';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            isLoading = false;
            errorMessage = '服务器错误: ${response.statusCode}';
          });
        }
      }
    } catch (e) {
      print('Fetch employees error: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
          errorMessage = '网络错误: $e';
        });
      }
    }
  }
  
  Future<void> _connect(String employeeId, {bool isFileTransfer = false}) async {
    try {
      if (token == null) {
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
      }
      
      if (token == null) {
        BotToast.showText(text: '需要管理员登录');
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
          
          connect(context, deviceId, password: password, isFileTransfer: isFileTransfer);
        }
      }
    } catch (e) {
      BotToast.showText(text: '连接失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredEmployees = employees.where((emp) {
      if (selectedDepartment != '全部部门') {
        if (emp['department']?.toString() != selectedDepartment) return false;
      }
      final query = _searchQuery.toLowerCase();
      final id = emp['employee_id'].toString().toLowerCase();
      final name = (emp['employee_name'] ?? '').toString().toLowerCase();
      return id.contains(query) || name.contains(query);
    }).toList();

    return Column(
      children: [
        // Clean Premium Search Bar
        Container(
          height: 70,
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
              // Department Selector
              Container(
                height: 40,
                padding: EdgeInsets.symmetric(horizontal: 12),
                margin: EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedDepartment,
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey[600], size: 20),
                    style: TextStyle(color: Colors.grey[800], fontSize: 14, fontWeight: FontWeight.w500),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          selectedDepartment = newValue;
                        });
                      }
                    },
                    items: departments.map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                  ),
                ),
              ),

              // Search Input
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.transparent),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: Colors.grey[500], size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: '搜索工号或姓名...',
                            hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.only(bottom: 12), // Center vertically
                          ),
                          style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                          textAlignVertical: TextAlignVertical.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 16),
              
              // Refresh Button
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: isLoading 
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.blue, strokeWidth: 2))
                    : Icon(Icons.refresh, color: Colors.blue, size: 22),
                  onPressed: isLoading ? null : () {
                    setState(() => isLoading = true);
                    _fetchEmployees();
                  },
                  splashRadius: 24,
                ),
              ),
            ],
          ),
        ),
        
        // Content Area
        Expanded(
          child: _buildContent(filteredEmployees),
        ),
      ],
    );
  }

  Widget _buildContent(List<dynamic> filteredEmployees) {
    if (isLoading && employees.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载员工列表...', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }
    
    if (errorMessage != null && employees.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            SizedBox(height: 16),
            Text('加载失败', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(errorMessage!, style: TextStyle(color: Colors.grey[600])),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  isLoading = true;
                  errorMessage = null;
                });
                _fetchEmployees();
              },
              child: Text('重试'),
            ),
          ],
        ),
      );
    }
    
    if (filteredEmployees.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty ? '暂无员工数据' : '没有找到匹配的员工',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            if (_searchQuery.isEmpty) ...[
              SizedBox(height: 8),
              Text(
                '请先在客户端安装软件并输入工号',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
            ],
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: EdgeInsets.all(8),
      itemCount: filteredEmployees.length,
      itemBuilder: (context, index) {
        final emp = filteredEmployees[index];
        final isOnline = emp['is_online'] == 1;
        return Card(
          margin: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          elevation: 1,
          child: ListTile(
            leading: Stack(
              children: [
                Icon(Icons.computer, size: 36, color: isOnline ? Colors.green : Colors.grey),
                if (isOnline)
                  Positioned(
                    right: 0, 
                    bottom: 0, 
                    child: Container(
                      width: 12, 
                      height: 12, 
                      decoration: BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  )
              ],
            ),
            title: Text(
              '${emp['employee_name'] ?? "未知"} (工号: ${emp['employee_id']})', 
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('设备: ${emp['device_name'] ?? "未知"} - ${emp['department'] ?? "无部门"}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: "远程控制",
                  child: IconButton(
                    icon: Icon(Icons.desktop_windows, color: isOnline ? Colors.blue : Colors.grey[400]),
                    onPressed: isOnline ? () => _connect(emp['employee_id'], isFileTransfer: false) : null,
                  ),
                ),
                Tooltip(
                  message: "文件传输",
                  child: IconButton(
                    icon: Icon(Icons.folder_shared, color: isOnline ? Colors.orange : Colors.grey[400]),
                    onPressed: isOnline ? () => _connect(emp['employee_id'], isFileTransfer: true) : null,
                  ),
                ),
                Tooltip(
                  message: pinnedIds.contains(emp['employee_id'].toString()) ? "从监控墙移除" : "加入监控墙",
                  child: IconButton(
                    icon: Icon(
                      pinnedIds.contains(emp['employee_id'].toString()) ? Icons.dashboard_customize : Icons.dashboard_customize_outlined, 
                      color: pinnedIds.contains(emp['employee_id'].toString()) ? Colors.purple : Colors.grey[400]
                    ),
                    onPressed: () {
                      _togglePin(emp['employee_id'].toString());
                      BotToast.showText(text: pinnedIds.contains(emp['employee_id'].toString()) ? "已从监控墙移除" : "已添加到监控墙");
                    },
                  ),
                ),
                Tooltip(
                  message: "查看录像",
                  child: IconButton(
                    icon: Icon(Icons.video_library, color: isOnline ? Colors.redAccent : Colors.grey[400]),
                    onPressed: isOnline ? () => _connect(emp['employee_id'], isFileTransfer: true) : null,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
