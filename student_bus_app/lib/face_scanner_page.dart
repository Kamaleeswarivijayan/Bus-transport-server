import 'package:http_parser/http_parser.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class FaceScannerPage extends StatefulWidget {
  final String busId;
  final String server;

  const FaceScannerPage({
    Key? key,
    required this.busId,
    required this.server,
  }) : super(key: key);

  @override
  _FaceScannerPageState createState() => _FaceScannerPageState();
}

class _FaceScannerPageState extends State<FaceScannerPage> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _cameraReady = false;
  CameraImage? latestImage;
  List<Map<String, dynamic>> studentList = [];
  Map<String, bool> attendanceMap = {};
  Map<String, String> studentNames = {};

  bool isLoadingStudents = true;
  String scanStatus = "Tap button to scan";

  @override
  void initState() {
    super.initState();
    _initCamera();
    _loadStudents();
  }

  // ---------------- CAMERA ----------------
  Future<void> _initCamera() async {
    _cameras = await availableCameras();

    final camera = _cameras.first;

    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();
        
    setState(() {
      _cameraReady = true;
    });

    print("✅ Camera ready");
    await _cameraController!.startImageStream((CameraImage image) {
    latestImage = image;   // ✅ CORRECT
  });

}

  // ---------------- LOAD STUDENTS ----------------
  Future<void> _loadStudents() async {
    var res = await http.get(
      Uri.parse("${widget.server}/getStudentsByBus/${widget.busId}"),
    );

    var data = jsonDecode(res.body);

    setState(() {
      studentList = List<Map<String, dynamic>>.from(data);

      for (var s in studentList) {
        String reg = s['reg_no'].toString();
        attendanceMap[reg] = false;
        studentNames[reg] = s['name'] ?? reg;
      }

      isLoadingStudents = false;
    });
  }

  // ---------------- CAPTURE & SCAN ----------------
Future<void> _captureAndScan() async {
  if (latestImage == null) {
    setState(() {
      scanStatus = "❌ No frame available";
    });
    return;
  }

  try {
    print("📸 Using live frame");

    final bytes = latestImage!.planes[0].bytes;

    var request = http.MultipartRequest(
      'POST',
      Uri.parse("${widget.server}/faceAttendance"),
    );

    request.fields['bus_id'] = widget.busId;

    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: "frame.jpg",
        contentType: MediaType('image', 'jpeg'),
      ),
    );

    print("🚀 Sending to server...");

    var res = await request.send();
    var response = await http.Response.fromStream(res);
    var data = jsonDecode(response.body);

    print(data);

    if (data["status"] == "success") {
      String id = data["data"]["student_id"];

      setState(() {
        attendanceMap[id] = true;
        scanStatus = "✅ ${studentNames[id]} marked";
      });
    } else {
      setState(() {
        scanStatus = "❌ Not recognized";
      });
    }

  } catch (e) {
    print("Error: $e");

    setState(() {
      scanStatus = "❌ Failed to send frame";
    });
  }
}
   // ---------------- SUBMIT ----------------
  Future<void> _submitAttendance() async {
    await http.post(
      Uri.parse("${widget.server}/markAttendance"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "bus_id": widget.busId,
        "records": attendanceMap.entries
            .map((e) => {"reg_no": e.key, "present": e.value})
            .toList(),
      }),
    );

    Navigator.pop(context);
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Face Attendance")),
      body: Column(
        children: [
          Container(
            height: 300,
            margin: const EdgeInsets.all(16),
            child: _cameraReady
                ? CameraPreview(_cameraController!)
                : const Center(child: CircularProgressIndicator()),
          ),

          const SizedBox(height: 10),

          Text(scanStatus),

          const SizedBox(height: 10),

          // 🔥 CAPTURE BUTTON
          ElevatedButton(
            onPressed: _captureAndScan,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 30),
            ),
            child: const Text("📸 Capture & Scan"),
          ),

          const SizedBox(height: 10),

          Expanded(
            child: isLoadingStudents
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: studentList.length,
                    itemBuilder: (context, i) {
                      String reg = studentList[i]['reg_no'].toString();
                      return ListTile(
                        title: Text(studentNames[reg] ?? ""),
                        trailing: Icon(
                          attendanceMap[reg]!
                              ? Icons.check
                              : Icons.close,
                          color: attendanceMap[reg]!
                              ? Colors.green
                              : Colors.red,
                        ),
                      );
                    },
                  ),
          ),

          ElevatedButton(
            onPressed: _submitAttendance,
            child: const Text("Submit Attendance"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }
}
