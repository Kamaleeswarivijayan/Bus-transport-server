import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class DriverPage extends StatefulWidget {
  @override
  _DriverPageState createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> {

  String server = "https://bus-transport-server.onrender.com";

  Location location = Location();
  Timer? timer;
  StreamSubscription<LocationData>? locationSubscription;

  List<String> buses = [];
  String? selectedBus;
  List<Map<String, dynamic>> students = []; // Students on this bus
  List<Map<String, dynamic>> attendanceRecords = []; // For marking attendance

  double latitude = 0;
  double longitude = 0;
  double currentSpeed = 0;

  bool sending = false;
  bool markingAttendance = false;

  // Emergency alerts variables
  List<Map<String, dynamic>> emergencyAlerts = [];
  bool hasEmergency = false;
  Timer? alertTimer;

  // ---------------- FETCH BUS LIST ----------------

  Future fetchBuses() async {
    var url = Uri.parse("$server/getBuses");
    var response = await http.get(url);
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      setState(() {
        buses = List<String>.from(data);
        if (buses.isNotEmpty && selectedBus == null) {
          selectedBus = buses.first;
          fetchStudentsForBus(); // Fetch students when bus is selected
        }
      });
    }
  }

  // ---------------- FETCH STUDENTS FOR THIS BUS ----------------

  Future fetchStudentsForBus() async {
    if (selectedBus == null) return;
    
    try {
      var url = Uri.parse("$server/getStudentsByBus/$selectedBus");
      var response = await http.get(url);
      
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        setState(() {
          students = List<Map<String, dynamic>>.from(data);
          // Initialize attendance records
          attendanceRecords = students.map((s) {
            return {
              "reg_no": s["reg_no"],
              "name": s["name"],
              "present": false,
            };
          }).toList();
        });
        print("✅ Loaded ${students.length} students for bus $selectedBus");
      } else {
        print("❌ Failed to fetch students: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Error fetching students: $e");
    }
  }

  // ---------------- REAL GPS TRACKING (NO SIMULATION) ----------------

  Future<void> startLiveTracking() async {
    if (selectedBus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select a bus first"),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      sending = true;
    });

    // Check if GPS service is enabled
    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        setState(() {
          sending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please enable GPS"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Check permission
    PermissionStatus permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        setState(() {
          sending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Location permission required"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Listen to location changes (REAL GPS ONLY)
    locationSubscription = location.onLocationChanged.listen((LocationData currentLocation) {
      if (!mounted) return;
      
      double lat = currentLocation.latitude ?? 0;
      double lng = currentLocation.longitude ?? 0;
      double speed = currentLocation.speed ?? 0;
      
      // Convert speed from m/s to km/h
      if (speed > 0) {
        speed = speed * 3.6;
      }
      
      setState(() {
        latitude = lat;
        longitude = lng;
        currentSpeed = speed;
      });
      
      print("📍 REAL GPS: Bus $selectedBus at ($lat, $lng), Speed: ${speed.toStringAsFixed(1)} km/h");
      
      // Send location to server
      sendLocationToServer(lat, lng, speed);
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("📍 Live tracking started for Bus $selectedBus"),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------- SEND LOCATION TO BACKEND ----------------

  Future<void> sendLocationToServer(double lat, double lng, double speed) async {
    if (selectedBus == null) return;
    
    try {
      var url = Uri.parse("$server/sendLocation");
      var response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "bus_id": selectedBus,
          "latitude": lat,
          "longitude": lng,
          "speed": speed,
        }),
      );
      
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        if (data["anomaly"] != null) {
          // Show anomaly alert
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("⚠️ Anomaly detected: ${data["anomaly"]}"),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } else {
        print("❌ Failed to send location: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Error sending location: $e");
    }
  }

  // ---------------- STOP TRACKING ----------------

  void stopTracking() {
    setState(() {
      sending = false;
    });
    
    locationSubscription?.cancel();
    timer?.cancel();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("⏹️ Tracking stopped"),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------- MARK ATTENDANCE DIALOG ----------------

  void showAttendanceDialog() {
    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No students found for this bus"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.fact_check, color: Colors.green, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        "Mark Attendance",
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Bus: $selectedBus",
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: attendanceRecords.length,
                      itemBuilder: (context, index) {
                        var record = attendanceRecords[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: CheckboxListTile(
                            title: Text(
                              record["name"],
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(record["reg_no"].toString()),
                            value: record["present"],
                            onChanged: (value) {
                              setModalState(() {
                                attendanceRecords[index]["present"] = value ?? false;
                              });
                            },
                            activeColor: Colors.green,
                            checkboxShape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00C48C), Color(0xFF008F67)],
                      ),
                    ),
                    child: ElevatedButton(
                      onPressed: markingAttendance ? null : () => submitAttendance(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: markingAttendance
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.save, size: 20),
                                SizedBox(width: 8),
                                Text("Save Attendance", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------------- SUBMIT ATTENDANCE ----------------

  Future<void> submitAttendance(BuildContext dialogContext) async {
    setState(() {
      markingAttendance = true;
    });

    try {
      var presentRecords = attendanceRecords.where((r) => r["present"] == true).toList();
      
      var url = Uri.parse("$server/markAttendance");
      var response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "bus_id": selectedBus,
          "records": attendanceRecords,
        }),
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ ${data["marked"]} students marked present"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(dialogContext);
      } else {
        throw Exception("Failed to mark attendance");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Error marking attendance: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        markingAttendance = false;
      });
    }
  }

  // ---------------- FETCH EMERGENCY ALERTS ----------------

  Future fetchEmergencyAlerts() async {
    if (selectedBus == null) return;
    try {
      var url = Uri.parse("$server/getDriverAlerts/$selectedBus");
      var response = await http.get(url);
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        List<Map<String, dynamic>> newAlerts = List<Map<String, dynamic>>.from(data["alerts"]);
        if (newAlerts.isNotEmpty && mounted) {
          setState(() {
            emergencyAlerts = newAlerts;
            hasEmergency = emergencyAlerts.isNotEmpty;
          });
          if (emergencyAlerts.isNotEmpty && mounted) {
            _showEmergencyNotification(emergencyAlerts.first);
          }
        } else if (mounted) {
          setState(() {
            emergencyAlerts = [];
            hasEmergency = false;
          });
        }
      }
    } catch (e) {
      print("Error fetching alerts: $e");
    }
  }

  // ---------------- SHOW EMERGENCY NOTIFICATION ----------------

  void _showEmergencyNotification(Map<String, dynamic> alert) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text("EMERGENCY ALERT!", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.person, color: Colors.red, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      "Student: ${alert['student_reg']}",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Location: ${alert['location_name']}",
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Time: ${alert['alert_time']}",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await http.post(
                  Uri.parse("$server/acknowledgeAlert"),
                  headers: {"Content-Type": "application/json"},
                  body: jsonEncode({"alert_id": alert["id"], "user_type": "driver"}),
                );
                if (mounted) {
                  Navigator.pop(context);
                  fetchEmergencyAlerts();
                }
              },
              child: const Text("Acknowledge", style: TextStyle(color: Colors.green)),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF0A84FF), Color(0xFF1E90FF)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ElevatedButton(
                onPressed: () async {
                  await http.post(
                    Uri.parse("$server/acknowledgeAlert"),
                    headers: {"Content-Type": "application/json"},
                    body: jsonEncode({"alert_id": alert["id"], "user_type": "driver"}),
                  );
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Emergency at: ${alert['location_name']}"),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    fetchEmergencyAlerts();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                child: const Text("Acknowledge & View"),
              ),
            ),
          ],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
      },
    );
  }

  // ---------------- SEND EMERGENCY ----------------

  Future sendEmergency() async {
    if (selectedBus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a bus first"), backgroundColor: Colors.orange),
      );
      return;
    }

    // Show confirmation dialog
    bool? confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text("Send Emergency Alert?"),
          ],
        ),
        content: const Text("This will notify the admin and parents about the emergency."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Send Alert"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      var url = Uri.parse("$server/emergency");
      await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"bus_id": selectedBus})
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🚨 Emergency Alert Sent"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        )
      );
    }
  }

  @override
  void initState() {
    super.initState();
    fetchBuses();
    alertTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && selectedBus != null) {
        fetchEmergencyAlerts();
      }
    });
  }

  @override
  void dispose() {
    locationSubscription?.cancel();
    timer?.cancel();
    alertTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A84FF), Color(0xFF003B8E)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.drive_eta, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "Driver Dashboard",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Emergency Alerts Card
                      if (hasEmergency)
                        Card(
                          margin: const EdgeInsets.only(bottom: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.red, width: 2),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text(
                                          "ACTIVE EMERGENCY ALERTS",
                                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)),
                                        child: Text("${emergencyAlerts.length}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ...emergencyAlerts.map((alert) => Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [const Icon(Icons.person, size: 16, color: Colors.red), const SizedBox(width: 4), Text("Student: ${alert['student_reg']}", style: const TextStyle(fontWeight: FontWeight.bold))]),
                                        const SizedBox(height: 4),
                                        Row(children: [const Icon(Icons.location_on, size: 14, color: Colors.red), const SizedBox(width: 4), Expanded(child: Text(alert['location_name'], style: const TextStyle(fontSize: 12)))]),
                                        const SizedBox(height: 4),
                                        Text("Time: ${alert['alert_time']}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                        const SizedBox(height: 8),
                                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                          if (!alert['driver_acknowledged'])
                                            ElevatedButton(
                                              onPressed: () async {
                                                await http.post(
                                                  Uri.parse("$server/acknowledgeAlert"),
                                                  headers: {"Content-Type": "application/json"},
                                                  body: jsonEncode({"alert_id": alert["id"], "user_type": "driver"}),
                                                );
                                                fetchEmergencyAlerts();
                                              },
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size(80, 30)),
                                              child: const Text("Acknowledge", style: TextStyle(fontSize: 11)),
                                            ),
                                        ]),
                                      ],
                                    ),
                                  )),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Bus Selection Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00D4FF).withOpacity(0.2),
                              blurRadius: 20,
                              spreadRadius: 0,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0A84FF).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.directions_bus, color: Color(0xFF0A84FF), size: 20),
                                ),
                                const SizedBox(width: 10),
                                const Text("Select Bus", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F5F5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF0A84FF).withOpacity(0.3)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  hint: Text("Choose Bus", style: TextStyle(color: const Color(0xFF0F172A).withOpacity(0.5))),
                                  value: buses.contains(selectedBus) ? selectedBus : null,
                                  isExpanded: true,
                                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF0A84FF)),
                                  items: buses.map((bus) {
                                    return DropdownMenuItem(
                                      value: bus,
                                      child: Text(bus, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16)),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      selectedBus = value;
                                      fetchStudentsForBus();
                                      fetchEmergencyAlerts();
                                    });
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Live Location Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00D4FF).withOpacity(0.2),
                              blurRadius: 20,
                              spreadRadius: 0,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: sending ? Colors.green.withOpacity(0.1) : const Color(0xFF0A84FF).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    sending ? Icons.gps_fixed : Icons.gps_not_fixed,
                                    color: sending ? Colors.green : const Color(0xFF0A84FF),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  sending ? "Live Location" : "Location Status",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: sending ? Colors.green : const Color(0xFF0F172A),
                                  ),
                                ),
                                if (sending)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(color: Colors.green.withOpacity(0.5), blurRadius: 8, spreadRadius: 2),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F5F5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFF0A84FF).withOpacity(0.2)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(Icons.north_east, color: Color(0xFF0A84FF), size: 16),
                                                const SizedBox(width: 4),
                                                Text("Latitude", style: TextStyle(fontSize: 12, color: const Color(0xFF0F172A).withOpacity(0.6))),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              latitude.toStringAsFixed(6),
                                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(height: 30, width: 1, color: const Color(0xFF0A84FF).withOpacity(0.2)),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                Text("Longitude", style: TextStyle(fontSize: 12, color: const Color(0xFF0F172A).withOpacity(0.6))),
                                                const SizedBox(width: 4),
                                                const Icon(Icons.south_east, color: Color(0xFF0A84FF), size: 16),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              longitude.toStringAsFixed(6),
                                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  const Divider(),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text("Speed:", style: TextStyle(fontSize: 14, color: Colors.grey)),
                                      Text(
                                        "${currentSpeed.toStringAsFixed(1)} km/h",
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0A84FF)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text("Students on board:", style: TextStyle(fontSize: 14, color: Colors.grey)),
                                      Text(
                                        "${attendanceRecords.where((r) => r["present"] == true).length} / ${students.length}",
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Control Buttons
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00D4FF).withOpacity(0.2),
                              blurRadius: 20,
                              spreadRadius: 0,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            if (!sending)
                              Container(
                                width: double.infinity,
                                height: 56,
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: const LinearGradient(colors: [Color(0xFF1E90FF), Color(0xFF0A84FF)]),
                                ),
                                child: ElevatedButton(
                                  onPressed: startLiveTracking,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.gps_fixed, size: 20),
                                      SizedBox(width: 8),
                                      Text("📍 Start Real GPS Tracking", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ),

                            if (sending)
                              Container(
                                width: double.infinity,
                                height: 56,
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: LinearGradient(colors: [Colors.red.shade400, Colors.red.shade700]),
                                ),
                                child: ElevatedButton(
                                  onPressed: stopTracking,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.stop_circle, size: 20),
                                      SizedBox(width: 8),
                                      Text("⏹️ Stop Tracking", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ),

                            Container(
                              width: double.infinity,
                              height: 56,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(colors: [Color(0xFF00C48C), Color(0xFF008F67)]),
                              ),
                              child: ElevatedButton(
                                onPressed: showAttendanceDialog,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.fact_check, size: 20),
                                    SizedBox(width: 8),
                                    Text("📋 Mark Attendance", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),

                            Container(
                              width: double.infinity,
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(colors: [Color(0xFFFF4B4B), Color(0xFFC62828)]),
                              ),
                              child: ElevatedButton(
                                onPressed: sendEmergency,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.warning_amber_rounded, size: 20),
                                    SizedBox(width: 8),
                                    Text("🚨 Emergency Alert", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (sending)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(color: Colors.green.withOpacity(0.5), blurRadius: 8, spreadRadius: 2),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "📍 Real GPS Tracking Active",
                                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 20),
                      Center(
                        child: Container(
                          height: 4,
                          width: 100,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D4FF),
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00D4FF).withOpacity(0.5),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}