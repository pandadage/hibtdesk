import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bot_toast/bot_toast.dart';

class AdminProfilePage extends StatefulWidget {
  final VoidCallback onLogout;
  
  const AdminProfilePage({Key? key, required this.onLogout}) : super(key: key);

  @override
  _AdminProfilePageState createState() => _AdminProfilePageState();
}

class _AdminProfilePageState extends State<AdminProfilePage> {
  Map<String, dynamic>? adminInfo;
  bool isLoading = true;
  String? errorMessage;
  
  final String apiServer = "http://38.181.2.76:3000/api";

  @override
  void initState() {
    super.initState();
    _loadAdminInfo();
  }

  Future<void> _loadAdminInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('admin_token');
      final username = prefs.getString('admin_username') ?? 'admin';
      
      if (token == null) {
        setState(() {
          isLoading = false;
          errorMessage = '未登录';
        });
        return;
      }
      
      // 获取统计信息
      final response = await http.get(
        Uri.parse('$apiServer/stats'),
        headers: {'Authorization': 'Bearer $token'},
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            adminInfo = {
              'username': username,
              'total_employees': data['stats']['total_employees'] ?? 0,
              'online_count': data['stats']['online_count'] ?? 0,
              'total_departments': data['stats']['total_departments'] ?? 0,
            };
            isLoading = false;
          });
        }
      } else {
        setState(() {
          adminInfo = {'username': username};
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        adminInfo = {'username': 'admin'};
      });
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('退出登录'),
        content: Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('退出', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('admin_token');
      await prefs.remove('admin_username');
      BotToast.showText(text: '已退出登录');
      widget.onLogout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[50],
      child: Center(
        child: Container(
          width: 400,
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: isLoading
            ? Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 头像
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.blue[100],
                    child: Icon(Icons.admin_panel_settings, size: 50, color: Colors.blue),
                  ),
                  SizedBox(height: 16),
                  
                  // 用户名
                  Text(
                    adminInfo?['username'] ?? 'admin',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '管理员',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  SizedBox(height: 24),
                  
                  // 统计信息
                  if (adminInfo != null) ...[
                    Divider(),
                    SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStatItem('员工总数', adminInfo?['total_employees']?.toString() ?? '0'),
                        _buildStatItem('在线人数', adminInfo?['online_count']?.toString() ?? '0'),
                        _buildStatItem('部门数', adminInfo?['total_departments']?.toString() ?? '0'),
                      ],
                    ),
                    SizedBox(height: 24),
                    Divider(),
                  ],
                  
                  SizedBox(height: 24),
                  
                  // 退出登录按钮
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _logout,
                      icon: Icon(Icons.logout, color: Colors.white),
                      label: Text('退出登录', style: TextStyle(fontSize: 16, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }
}
