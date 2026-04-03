import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

class AdminPage extends StatefulWidget {
  @override
  _AdminPageState createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {

  String server = "https://bus-transport-server.onrender.com";
  String faceserver = "http://192.168.1.6:5000";
  List buses = [];
  List stops = [];
  List logs = [];

  int activeBuses = 0;
  int delayedBuses = 0;
  int students = 0;
  int emergency = 0;

  // Loading states
  bool isLoadingDashboard = false;
  bool isLoadingBuses = false;
  bool isLoadingLogs = false;
  String? selectedBusForStops;
  
  // Emergency alerts variables
  List<Map<String, dynamic>> emergencyAlerts = [];
  List<Map<String, dynamic>> alertHistory = [];
  bool isLoadingAlerts = false;
  bool isSendingReroute = false;
  
  // Attendance variables
  List<Map<String, dynamic>> attendanceRecords = [];
  bool isLoadingAttendance = false;
  String? selectedAttendanceBus;
  String selectedAttendanceDate = DateTime.now().toIso8601String().substring(0, 10);
  
  // Bus summary for selected bus
  Map<String, dynamic> busSummary = {};
  bool isLoadingBusSummary = false;
  
  // Route history variables
  List<Map<String, dynamic>> routeHistory = [];
  bool isLoadingRoutes = false;
  bool isDownloadingRoute = false;
  String? selectedRouteBus;
  String selectedRouteDate = DateTime.now().toIso8601String().substring(0, 10);
  
  // Reroute dialog controllers
  TextEditingController oldBusController = TextEditingController();
  TextEditingController newBusController = TextEditingController();
  TextEditingController rerouteReasonController = TextEditingController();

  // ---------------- LOAD DASHBOARD ----------------

  Future loadDashboard() async {
    setState(() {
      isLoadingDashboard = true;
    });
    var url = Uri.parse("$server/dashboard");
    try {
      var res = await http.get(url);
      if(res.statusCode == 200){
        var data = jsonDecode(res.body);
        setState(() {
          activeBuses = data["active_buses"] ?? 0;
          delayedBuses = data["delayed_buses"] ?? 0;
          students = data["students"] ?? 0;
          emergency = data["emergency"] ?? 0;
        });
      }
    } catch(e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading dashboard: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        isLoadingDashboard = false;
      });
    }
  }

  // ---------------- LOAD BUSES ----------------

  Future loadBuses() async {
    setState(() {
      isLoadingBuses = true;
    });
    var url = Uri.parse("$server/getBuses");
    try {
      var res = await http.get(url);
      if(res.statusCode == 200){
        setState(() {
          buses = jsonDecode(res.body);
        });
      }
    } catch(e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading buses: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        isLoadingBuses = false;
      });
    }
  }

  // ---------------- LOAD BUS SUMMARY ----------------

  Future loadBusSummary(String busId) async {
    setState(() {
      isLoadingBusSummary = true;
    });
    try {
      var url = Uri.parse("$server/busSummary/$busId");
      var res = await http.get(url);
      if(res.statusCode == 200){
        setState(() {
          busSummary = jsonDecode(res.body);
        });
      }
    } catch(e) {
      print("Error loading bus summary: $e");
    } finally {
      setState(() {
        isLoadingBusSummary = false;
      });
    }
  }

  // ---------------- LOAD STOPS ----------------

  Future loadStops(String busId) async {
    setState(() {
      selectedBusForStops = busId;
    });
    var url = Uri.parse("$server/getStops/$busId");
    try {
      var res = await http.get(url);
      if(res.statusCode == 200){
        setState(() {
          stops = jsonDecode(res.body);
        });
      }
    } catch(e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading stops: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // ---------------- LOAD LOGS ----------------

  Future loadLogs() async {
    setState(() {
      isLoadingLogs = true;
    });
    var url = Uri.parse("$server/getLogs");
    try {
      var res = await http.get(url);
      if(res.statusCode == 200){
        setState(() {
          logs = jsonDecode(res.body);
        });
      }
    } catch(e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading logs: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        isLoadingLogs = false;
      });
    }
  }

  // ---------------- DOWNLOAD REPORT ----------------

  Future downloadReport() async {
    var url = Uri.parse("$server/downloadReport");
    try {
      if(await canLaunchUrl(url)){
        await launchUrl(url);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Download started"), backgroundColor: Colors.green),
        );
      }
    } catch(e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error downloading report: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // ---------------- FETCH EMERGENCY ALERTS ----------------

  Future fetchEmergencyAlerts() async {
    setState(() {
      isLoadingAlerts = true;
    });
    try {
      var url = Uri.parse("$server/getAdminAlerts");
      var res = await http.get(url);
      if (res.statusCode == 200) {
        var data = jsonDecode(res.body);
        setState(() {
          emergencyAlerts = List<Map<String, dynamic>>.from(data["alerts"]);
          emergency = emergencyAlerts.length;
        });
      }
    } catch (e) {
      print("Error fetching alerts: $e");
    } finally {
      setState(() {
        isLoadingAlerts = false;
      });
    }
  }
  
  // ---------------- FETCH ALERT HISTORY ----------------

  Future fetchAlertHistory() async {
    try {
      var url = Uri.parse("$server/getAlertHistory");
      var res = await http.get(url);
      if (res.statusCode == 200) {
        var data = jsonDecode(res.body);
        setState(() {
          alertHistory = List<Map<String, dynamic>>.from(data["alerts"]);
        });
      }
    } catch (e) {
      print("Error fetching history: $e");
    }
  }

  // ---------------- FETCH ATTENDANCE RECORDS ----------------

  Future fetchAttendance() async {
    if (selectedAttendanceBus == null) return;
    setState(() {
      isLoadingAttendance = true;
    });
    try {
      var url = Uri.parse("$server/getAttendance/$selectedAttendanceBus?date=$selectedAttendanceDate");
      var res = await http.get(url);
      if (res.statusCode == 200) {
        var data = jsonDecode(res.body);
        setState(() {
          attendanceRecords = List<Map<String, dynamic>>.from(data["records"]);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text("Failed to load attendance"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        isLoadingAttendance = false;
      });
    }
  }

  // ---------------- FETCH ROUTE HISTORY ----------------

  Future fetchRouteHistory() async {
    if (selectedRouteBus == null) return;
    setState(() { isLoadingRoutes = true; routeHistory = []; });
    try {
      var url = Uri.parse("$server/getRoutes/$selectedRouteBus?date=$selectedRouteDate");
      var res = await http.get(url);
      if (res.statusCode == 200) {
        var data = jsonDecode(res.body);
        setState(() {
          routeHistory = List<Map<String, dynamic>>.from(data["routes"]);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to load route history"), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() { isLoadingRoutes = false; });
    }
  }

  // ---------------- DOWNLOAD ROUTE ----------------

  Future downloadRoute(String routeId, String format) async {
    setState(() { isDownloadingRoute = true; });
    try {
      var url = Uri.parse("$server/downloadRoute/$routeId?format=$format");
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.download_done, color: Colors.white),
                const SizedBox(width: 8),
                Text("Downloading route as $format..."),
              ]),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Download failed"), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() { isDownloadingRoute = false; });
    }
  }

  // ---------------- FORMAT DURATION ----------------

  String formatDuration(String? start, String? end) {
    if (start == null || end == null) return "—";
    try {
      final s = DateTime.parse(start);
      final e = DateTime.parse(end);
      final diff = e.difference(s);
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      if (h > 0) return "${h}h ${m}m";
      return "${m}m";
    } catch (_) {
      return "—";
    }
  }
  
  // ---------------- ACKNOWLEDGE ALERT ----------------

  Future acknowledgeAlert(int alertId) async {
    try {
      await http.post(
        Uri.parse("$server/acknowledgeAlert"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"alert_id": alertId, "user_type": "admin"}),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Alert acknowledged"), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
      );
      fetchEmergencyAlerts();
      fetchAlertHistory();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error acknowledging alert: $e"), backgroundColor: Colors.red),
      );
    }
  }
  
  // ---------------- RESOLVE ALERT ----------------

  Future resolveAlert(int alertId) async {
    try {
      await http.post(
        Uri.parse("$server/resolveAlert"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"alert_id": alertId}),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Alert resolved"), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
      );
      fetchEmergencyAlerts();
      fetchAlertHistory();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error resolving alert: $e"), backgroundColor: Colors.red),
      );
    }
  }
  
  // ---------------- REROUTE BUS DIALOG ----------------

  void showRerouteDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.swap_horiz, color: Color(0xFF0A84FF)),
              SizedBox(width: 8),
              Text("Reroute Bus"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Replace a broken bus with a replacement bus",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: "Original Bus",
                  prefixIcon: const Icon(Icons.directions_bus, color: Color(0xFF0A84FF)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: buses.map((bus) {
                  return DropdownMenuItem(
                    value: bus.toString(),
                    child: Text(bus.toString()),
                  );
                }).toList(),
                onChanged: (value) {
                  oldBusController.text = value ?? "";
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: "Replacement Bus",
                  prefixIcon: const Icon(Icons.directions_bus, color: Color(0xFF0A84FF)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: buses.map((bus) {
                  return DropdownMenuItem(
                    value: bus.toString(),
                    child: Text(bus.toString()),
                  );
                }).toList(),
                onChanged: (value) {
                  newBusController.text = value ?? "";
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: rerouteReasonController,
                decoration: InputDecoration(
                  labelText: "Reason (Optional)",
                  prefixIcon: const Icon(Icons.description, color: Color(0xFF0A84FF)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                oldBusController.clear();
                newBusController.clear();
                rerouteReasonController.clear();
                Navigator.pop(context);
              },
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF0A84FF), Color(0xFF1E90FF)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ElevatedButton(
                onPressed: () async {
                  if (oldBusController.text.isEmpty || newBusController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please select both buses"), backgroundColor: Colors.orange),
                    );
                    return;
                  }
                  setState(() { isSendingReroute = true; });
                  try {
                    var url = Uri.parse("$server/reroute");
                    var response = await http.post(
                      url,
                      headers: {"Content-Type": "application/json"},
                      body: jsonEncode({
                        "old_bus": oldBusController.text,
                        "new_bus": newBusController.text,
                        "reason": rerouteReasonController.text.isEmpty ? "Admin reroute" : rerouteReasonController.text,
                      }),
                    );
                    if (response.statusCode == 200) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Bus ${oldBusController.text} rerouted to ${newBusController.text}"),
                        backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
                      );
                      oldBusController.clear();
                      newBusController.clear();
                      rerouteReasonController.clear();
                      Navigator.pop(context);
                      loadBuses(); // Refresh bus list
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Error rerouting bus: $e"), backgroundColor: Colors.red),
                    );
                  } finally {
                    setState(() { isSendingReroute = false; });
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                child: isSendingReroute
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                    : const Text("Reroute Bus"),
              ),
            ),
          ],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
      },
    );
  }

  // ---------------- INIT ----------------

  @override
  void initState() {
    super.initState();
    loadDashboard();
    loadBuses();
    fetchEmergencyAlerts();
    fetchAlertHistory();
    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        fetchEmergencyAlerts();
      }
    });
  }

  // ---------------- UI ----------------

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
              // Custom App Bar
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
                      child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "Admin Dashboard",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, letterSpacing: 0.5, color: Colors.white),
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
                      // Active Emergency Alerts Card
                      if (emergencyAlerts.isNotEmpty)
                        Card(
                          elevation: 5,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          margin: const EdgeInsets.only(bottom: 20),
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
                                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
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
                                        Row(children: [const Icon(Icons.directions_bus, size: 14, color: Colors.red), const SizedBox(width: 4), Text("Bus: ${alert['bus_id']}")]),
                                        const SizedBox(height: 4),
                                        Row(children: [const Icon(Icons.location_on, size: 14, color: Colors.red), const SizedBox(width: 4), Expanded(child: Text(alert['location_name'], style: const TextStyle(fontSize: 12)))]),
                                        const SizedBox(height: 4),
                                        Text("Time: ${alert['alert_time']}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                        const SizedBox(height: 8),
                                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                          if (!alert['admin_acknowledged'])
                                            TextButton(onPressed: () => acknowledgeAlert(alert['id']), child: const Text("Acknowledge", style: TextStyle(color: Colors.green))),
                                          const SizedBox(width: 8),
                                          ElevatedButton(onPressed: () => resolveAlert(alert['id']), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size(80, 30)), child: const Text("Resolve", style: TextStyle(fontSize: 12))),
                                        ]),
                                      ],
                                    ),
                                  )),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // System Overview Card
                      Card(
                        elevation: 5,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        margin: const EdgeInsets.only(bottom: 20),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.2), blurRadius: 20, spreadRadius: 0, offset: const Offset(0, 8))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFF0A84FF).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.dashboard, color: Color(0xFF0A84FF), size: 20)),
                                  const SizedBox(width: 10),
                                  const Text("SYSTEM OVERVIEW", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                                  if (isLoadingDashboard) Padding(padding: const EdgeInsets.only(left: 8), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF0A84FF))))),
                                ],
                              ),
                              const SizedBox(height: 20),
                              // FIXED: Wrap instead of GridView for responsive layout
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _buildStatCard("Active Buses", activeBuses.toString(), Icons.directions_bus, const Color(0xFF1E90FF)),
                                  _buildStatCard("Delayed Buses", delayedBuses.toString(), Icons.schedule, Colors.orange),
                                  _buildStatCard("Students", students.toString(), Icons.people, Colors.green),
                                  _buildStatCard("Emergency Alerts", emergency.toString(), Icons.warning, Colors.red),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Bus Fleet Card - FIXED NO OVERFLOW
                      Card(
                        elevation: 5,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        margin: const EdgeInsets.only(bottom: 20),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.2), blurRadius: 20, spreadRadius: 0, offset: const Offset(0, 8))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header with Wrap to prevent overflow
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  // Title
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0A84FF).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.directions_bus_filled, color: Color(0xFF0A84FF), size: 20),
                                      ),
                                      const SizedBox(width: 10),
                                      const Text("BUS FLEET", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                                    ],
                                  ),
                                  // Buttons
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      Container(
                                        height: 40,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          gradient: const LinearGradient(colors: [Color(0xFFFF6B6B), Color(0xFFC62828)]),
                                        ),
                                        child: ElevatedButton(
                                          onPressed: showRerouteDialog,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(horizontal: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.swap_horiz, size: 16),
                                              SizedBox(width: 4),
                                              Text("Reroute"),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Container(
                                        height: 40,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          gradient: const LinearGradient(colors: [Color(0xFF1E90FF), Color(0xFF0A84FF)]),
                                        ),
                                        child: ElevatedButton(
                                          onPressed: loadBuses,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(horizontal: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          child: isLoadingBuses
                                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                                              : const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.refresh, size: 16),
                                                    SizedBox(width: 4),
                                                    Text("Load"),
                                                  ],
                                                ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              if (buses.isEmpty && !isLoadingBuses)
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      children: [
                                        Icon(Icons.directions_bus_outlined, size: 48, color: const Color(0xFF0F172A).withOpacity(0.3)),
                                        const SizedBox(height: 8),
                                        Text("No buses loaded", style: TextStyle(color: const Color(0xFF0F172A).withOpacity(0.5))),
                                      ],
                                    ),
                                  ),
                                ),
                              if (buses.isNotEmpty)
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: buses.length,
                                  itemBuilder: (context, index) {
                                    final bus = buses[index];
                                    final isSelected = selectedBusForStops == bus.toString();
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: isSelected ? const Color(0xFF0A84FF).withOpacity(0.05) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: isSelected ? const Color(0xFF0A84FF) : const Color(0xFF0F172A).withOpacity(0.1)),
                                      ),
                                      child: ListTile(
                                        leading: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0A84FF).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(Icons.directions_bus, color: Color(0xFF0A84FF), size: 20),
                                        ),
                                        title: Text(bus.toString(), style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF0F172A))),
                                        trailing: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0A84FF).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.location_on, color: Color(0xFF0A84FF), size: 16),
                                              SizedBox(width: 4),
                                              Text("Stops", style: TextStyle(color: Color(0xFF0A84FF), fontSize: 12)),
                                            ],
                                          ),
                                        ),
                                        onTap: () => loadStops(bus.toString()),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Bus Stops Card
                      if (stops.isNotEmpty)
                        Card(
                          elevation: 5,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          margin: const EdgeInsets.only(bottom: 20),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.2), blurRadius: 20, spreadRadius: 0, offset: const Offset(0, 8))],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.stop_circle, color: Colors.green, size: 20)), const SizedBox(width: 10), Text("BUS STOPS - $selectedBusForStops", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)))]),
                                const SizedBox(height: 16),
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: stops.length,
                                  itemBuilder: (context, index) {
                                    final s = stops[index];
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
                                      child: Row(
                                        children: [
                                          Container(width: 32, height: 32, decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle), child: Center(child: Text("${index + 1}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)))),
                                          const SizedBox(width: 12),
                                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s["stop_name"], style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F172A))), const SizedBox(height: 4), Text("${s["latitude"]}, ${s["longitude"]}", style: TextStyle(fontSize: 12, color: const Color(0xFF0F172A).withOpacity(0.6)))])),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Attendance Records Card
                      Card(
                        elevation: 5,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        margin: const EdgeInsets.only(bottom: 20),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.2), blurRadius: 20, spreadRadius: 0, offset: const Offset(0, 8))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.fact_check, color: Colors.green, size: 20)), const SizedBox(width: 10), const Text("Attendance Records", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)))]),
                              const SizedBox(height: 16),
                              // Bus selector
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withOpacity(0.3))),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    hint: const Text("Select Bus"),
                                    value: selectedAttendanceBus,
                                    isExpanded: true,
                                    icon: const Icon(Icons.keyboard_arrow_down, color: Colors.green),
                                    items: buses.map((bus) => DropdownMenuItem(value: bus.toString(), child: Text(bus.toString()))).toList(),
                                    onChanged: (value) { setState(() { selectedAttendanceBus = value; attendanceRecords = []; }); },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Date + Load button row
                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () async {
                                        DateTime? picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime.now());
                                        if (picked != null) { setState(() { selectedAttendanceDate = picked.toIso8601String().substring(0, 10); attendanceRecords = []; }); }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                        decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withOpacity(0.3))),
                                        child: Row(children: [const Icon(Icons.calendar_today, color: Colors.green, size: 16), const SizedBox(width: 8), Text(selectedAttendanceDate, style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)))]),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF00C48C), Color(0xFF008F67)]), borderRadius: BorderRadius.circular(12)),
                                    child: ElevatedButton(
                                      onPressed: isLoadingAttendance ? null : fetchAttendance,
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
                                      child: isLoadingAttendance ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("Load", style: TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                ],
                              ),
                              if (attendanceRecords.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    _buildAttendancePill("Present", attendanceRecords.where((r) => r['present'] == true).length, Colors.green),
                                    _buildAttendancePill("Absent", attendanceRecords.where((r) => r['present'] == false).length, Colors.red),
                                    _buildAttendancePill("Total", attendanceRecords.length, Colors.blueGrey),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Divider(),
                                ...attendanceRecords.map((record) {
                                  bool present = record['present'] == true;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(color: present ? Colors.green.withOpacity(0.05) : Colors.red.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: present ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2))),
                                    child: Row(
                                      children: [
                                        CircleAvatar(radius: 16, backgroundColor: present ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1), child: Icon(present ? Icons.check : Icons.close, size: 16, color: present ? Colors.green : Colors.red)),
                                        const SizedBox(width: 12),
                                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(record['name'] ?? record['reg_no'].toString(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)), Text(record['reg_no'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade500))])),
                                        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: present ? Colors.green : Colors.red, borderRadius: BorderRadius.circular(20)), child: Text(present ? "Present" : "Absent", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                              if (attendanceRecords.isEmpty && selectedAttendanceBus != null && !isLoadingAttendance)
                                Padding(padding: const EdgeInsets.only(top: 16), child: Center(child: Text("No attendance records found.\nSelect a bus and date, then tap Load.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)))),
                            ],
                          ),
                        ),
                      ),

                      // Route History Card
                      Card(
                        elevation: 5,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        margin: const EdgeInsets.only(bottom: 20),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.2), blurRadius: 20, spreadRadius: 0, offset: const Offset(0, 8))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFF0A84FF).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.route, color: Color(0xFF0A84FF), size: 20)), const SizedBox(width: 10), const Text("Route History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)))]),
                              const SizedBox(height: 16),
                              // Bus dropdown
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF0A84FF).withOpacity(0.3))),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    hint: const Text("Select Bus"),
                                    value: selectedRouteBus,
                                    isExpanded: true,
                                    icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF0A84FF)),
                                    items: buses.map((bus) => DropdownMenuItem(value: bus.toString(), child: Text(bus.toString()))).toList(),
                                    onChanged: (value) { setState(() { selectedRouteBus = value; routeHistory = []; }); },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Date picker + Load button
                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () async {
                                        DateTime? picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime.now());
                                        if (picked != null) { setState(() { selectedRouteDate = picked.toIso8601String().substring(0, 10); routeHistory = []; }); }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                        decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF0A84FF).withOpacity(0.3))),
                                        child: Row(children: [const Icon(Icons.calendar_today, color: Color(0xFF0A84FF), size: 16), const SizedBox(width: 8), Text(selectedRouteDate, style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)))]),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0A84FF), Color(0xFF1E90FF)]), borderRadius: BorderRadius.circular(12)),
                                    child: ElevatedButton(
                                      onPressed: isLoadingRoutes ? null : fetchRouteHistory,
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
                                      child: isLoadingRoutes ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("Load", style: TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                ],
                              ),
                              if (routeHistory.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                const Divider(),
                                const SizedBox(height: 8),
                                ...routeHistory.asMap().entries.map((entry) {
                                  int idx = entry.key;
                                  var route = entry.value;
                                  int points = route['point_count'] ?? 0;
                                  String duration = formatDuration(route['start_time'], route['end_time']);
                                  String routeId = route['id'].toString();
                                  double avgSpeed = route['avg_speed'] ?? 0;
                                  double maxSpeed = route['max_speed'] ?? 0;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(color: const Color(0xFFF8FAFF), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF0A84FF).withOpacity(0.15))),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFF0A84FF).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.directions_bus, color: Color(0xFF0A84FF), size: 16)), const SizedBox(width: 10), Expanded(child: Text("Trip ${idx + 1} · $selectedRouteBus", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF0F172A))))]),
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 8,
                                          children: [
                                            _buildRouteStat(Icons.timeline, "$points pts"),
                                            _buildRouteStat(Icons.access_time, duration),
                                            _buildRouteStat(Icons.speed, "${avgSpeed.toStringAsFixed(1)} km/h avg"),
                                            _buildRouteStat(Icons.speed, "${maxSpeed.toStringAsFixed(1)} km/h max"),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Row(children: [
                                          Expanded(child: OutlinedButton.icon(onPressed: isDownloadingRoute ? null : () => downloadRoute(routeId, "csv"), icon: const Icon(Icons.download, size: 16), label: const Text("CSV"), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF0A84FF), side: const BorderSide(color: Color(0xFF0A84FF)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 10)))),
                                          const SizedBox(width: 10),
                                          Expanded(child: OutlinedButton.icon(onPressed: isDownloadingRoute ? null : () => downloadRoute(routeId, "geojson"), icon: const Icon(Icons.map_outlined, size: 16), label: const Text("GeoJSON"), style: OutlinedButton.styleFrom(foregroundColor: Colors.teal, side: const BorderSide(color: Colors.teal), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 10)))),
                                        ]),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                              if (routeHistory.isEmpty && selectedRouteBus != null && !isLoadingRoutes)
                                Padding(padding: const EdgeInsets.only(top: 16), child: Center(child: Text("No route records found.\nSelect a bus and date, then tap Load.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)))),
                            ],
                          ),
                        ),
                      ),

                      // Bus Logs Card
                      Card(
                        elevation: 5,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        margin: const EdgeInsets.only(bottom: 20),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.2), blurRadius: 20, spreadRadius: 0, offset: const Offset(0, 8))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(children: [Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.history, color: Colors.orange, size: 20)), const SizedBox(width: 10), const Text("BUS LOGS", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)))]),
                                  Container(
                                    height: 40,
                                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: const LinearGradient(colors: [Color(0xFFFF9800), Color(0xFFF57C00)])),
                                    child: ElevatedButton(
                                      onPressed: loadLogs,
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                      child: isLoadingLogs ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))) : const Row(children: [Icon(Icons.refresh, size: 16), SizedBox(width: 4), Text("Load Logs")]),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              if (logs.isEmpty && !isLoadingLogs)
                                Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [Icon(Icons.history_outlined, size: 48, color: const Color(0xFF0F172A).withOpacity(0.3)), const SizedBox(height: 8), Text("No logs available", style: TextStyle(color: const Color(0xFF0F172A).withOpacity(0.5)))]))),
                              if (logs.isNotEmpty)
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: logs.length,
                                  itemBuilder: (context, index) {
                                    final log = logs[index];
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF0F172A).withOpacity(0.1))),
                                      child: Row(
                                        children: [
                                          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF0A84FF).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.directions_bus, color: Color(0xFF0A84FF), size: 20)),
                                          const SizedBox(width: 12),
                                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text("Bus: ${log["bus_id"]}", style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                                            const SizedBox(height: 4),
                                            Row(children: [const Icon(Icons.login, size: 12, color: Colors.green), const SizedBox(width: 4), Expanded(child: Text(log["entry_time"], style: TextStyle(fontSize: 12, color: const Color(0xFF0F172A).withOpacity(0.6))))]),
                                            Row(children: [const Icon(Icons.logout, size: 12, color: Colors.red), const SizedBox(width: 4), Expanded(child: Text(log["exit_time"], style: TextStyle(fontSize: 12, color: const Color(0xFF0F172A).withOpacity(0.6))))]),
                                          ])),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Download Report Button
                      Card(
                        elevation: 5,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        margin: const EdgeInsets.only(bottom: 20),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.2), blurRadius: 20, spreadRadius: 0, offset: const Offset(0, 8))],
                          ),
                          child: Container(
                            width: double.infinity,
                            height: 56,
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: const LinearGradient(colors: [Color(0xFF34C759), Color(0xFF30B0C7)]), boxShadow: [BoxShadow(color: const Color(0xFF34C759).withOpacity(0.4), blurRadius: 12, spreadRadius: 0)]),
                            child: ElevatedButton(
                              onPressed: downloadReport,
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.download, size: 20), SizedBox(width: 8), Text("Download CSV Report", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))]),
                            ),
                          ),
                        ),
                      ),

                      // Bottom accent glow
                      const SizedBox(height: 20),
                      Center(child: Container(height: 4, width: 100, decoration: BoxDecoration(color: const Color(0xFF00D4FF), borderRadius: BorderRadius.circular(2), boxShadow: [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.5), blurRadius: 10, spreadRadius: 2)]))),
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

  Widget _buildRouteStat(IconData icon, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: Colors.grey.shade500), const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))]);
  }

  Widget _buildAttendancePill(String label, int count, Color color) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)), child: Text("$label: $count", style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)));
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 60) / 2,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: const Color(0xFF0F172A).withOpacity(0.6)),
            ),
          ],
        ),
      ),
    );
  }
}