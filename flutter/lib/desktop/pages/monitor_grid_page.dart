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
  // TODO: 从配置读取
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
      final response = await http.get(Uri.parse('$apiServer/employee/list?online_only=true'));
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

  void _connect(String employeeId) async {
      // 获取员工详情进行连接
      try {
        // FIXME: 需要 token，此处假设已有或者临时绕过
        final response = await http.get(Uri.parse('$apiServer/employee/$employeeId'));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success']) {
            final emp = data['employee'];
            Provider.of<ServerModel>(context, listen: false)
                .connect(emp['device_id'], password: emp['device_password']);
          }
        }
      } catch (e) {
        // error
      }
  }

  @override
  Widget build(BuildContext context) {
    int crossAxisCount = 4;
    if (gridSize == 25) crossAxisCount = 5;
    if (gridSize == 36) crossAxisCount = 6;

    return Scaffold(
      appBar: AppBar(
        title: Text('监控墙 (${onlineEmployees.length} 在线)'),
        actions: [
          DropdownButton<int>(
            value: gridSize,
            dropdownColor: Colors.blue,
            style: TextStyle(color: Colors.white),
            items: [
              DropdownMenuItem(value: 16, child: Text('16 宫格')),
              DropdownMenuItem(value: 25, child: Text('25 宫格')),
              DropdownMenuItem(value: 36, child: Text('36 宫格')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => gridSize = v);
            },
          ),
          SizedBox(width: 20),
        ],
      ),
      body: GridView.builder(
        padding: EdgeInsets.all(5),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 1.6, // 16:10 屏幕比例
          crossAxisSpacing: 5,
          mainAxisSpacing: 5,
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
    );
  }

  Widget _buildMonitorCard(dynamic emp) {
    return Card(
      color: Colors.black87,
      child: InkWell(
        onTap: () => _connect(emp['employee_id']),
        child: Stack(
          children: [
            Center(
              child: Icon(Icons.monitor, size: 40, color: Colors.green.withOpacity(0.5)),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black54,
                padding: EdgeInsets.symmetric(vertical: 2, horizontal: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      emp['employee_name'] ?? 'Unknown',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      emp['department'] ?? '',
                      style: TextStyle(color: Colors.grey, fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 5,
              right: 5,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard() {
    return Card(
      color: Colors.grey[900],
      child: Center(
        child: Icon(Icons.monitor, color: Colors.white10),
      ),
    );
  }
}
