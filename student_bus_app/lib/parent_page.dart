import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui';

class ParentPage extends StatefulWidget {
  final String studentId;

  const ParentPage({Key? key, required this.studentId}) : super(key: key);

  @override
  _ParentPageState createState() => _ParentPageState();
}

class _ParentPageState extends State<ParentPage> {

  String server = "https://bus-transport-server.onrender.com";

  GoogleMapController? mapController;
  Timer? timer;

  LatLng busLocation = const LatLng(13.0134, 79.1321);
  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  Set<Marker> stopMarkers = {};

  String busId = "";
  String delay = "Loading...";
  String eta = "Calculating...";
  String studentName = "";
  String attendance = "Not Marked";
  String attendanceTime = "";
  String attendanceDate = "";
  double busSpeed = 0;
  Map<String, dynamic>? activeAlert;
  List<Map<String, dynamic>> stopsWithEta = [];
  bool isLoading = true;
  bool isTracking = true;
  bool hasNewAttendance = false;

  @override
  void initState() {
    super.initState();
    fetchLocation();
    startAutoRefresh();
  }

  // ---------------- FETCH LOCATION ----------------

  Future<void> fetchLocation() async {
    if (!mounted) return;
    
    try {
      var response = await http.get(
        Uri.parse("$server/parentData/${widget.studentId}"),
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        
        // Check attendance change
        String newAttendance = data["attendance"] ?? "Not Marked";
        if (attendance != "Not Marked" && attendance != newAttendance && newAttendance == "Present") {
          if (mounted) {
            setState(() {
              hasNewAttendance = true;
            });
            _showAttendanceNotification(studentName, newAttendance);
          }
        }
        
        double lat = (data["latitude"] as num?)?.toDouble() ?? 0;
        double lng = (data["longitude"] as num?)?.toDouble() ?? 0;
        
        if (lat != 0 && lng != 0) {
          LatLng newPosition = LatLng(lat, lng);
          busSpeed = (data["speed"] as num?)?.toDouble() ?? 0;
          
          // Create route polyline
          List<dynamic> routePoints = data["route"] ?? [];
          List<LatLng> polylinePoints = routePoints.map<LatLng>((p) {
            return LatLng(p["lat"], p["lon"]);
          }).toList();
          
          if (polylinePoints.isEmpty || polylinePoints.last != newPosition) {
            polylinePoints.add(newPosition);
          }
          
          // Create stops with ETA
          List<dynamic> stops = data["stops"] ?? [];
          stopsWithEta = stops.map<Map<String, dynamic>>((s) {
            return {
              "name": s["name"],
              "lat": s["lat"],
              "lon": s["lon"],
              "eta": s["eta"]
            };
          }).toList();
          
          Set<Marker> stopSet = {};
          for (var stop in stopsWithEta) {
            stopSet.add(
              Marker(
                markerId: MarkerId(stop["name"]),
                position: LatLng(stop["lat"], stop["lon"]),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
                infoWindow: InfoWindow(
                  title: stop["name"],
                  snippet: "ETA: ${stop["eta"]}",
                ),
              ),
            );
          }
          
          setState(() {
            isLoading = false;
            busId = data["bus_id"] ?? "";
            delay = data["delay"] ?? "On Time";
            eta = data["eta"] ?? "Calculating...";
            studentName = data["student_name"] ?? "Student";
            attendance = newAttendance;
            attendanceTime = data["attendance_time"] ?? "";
            attendanceDate = data["attendance_date"] ?? "";
            activeAlert = data["active_alert"];
            busLocation = newPosition;
            
            markers = {
              Marker(
                markerId: const MarkerId("bus"),
                position: newPosition,
                infoWindow: InfoWindow(
                  title: "Bus $busId",
                  snippet: "$delay | ETA: $eta | Speed: ${busSpeed.toStringAsFixed(1)} km/h",
                ),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              ),
            };
            
            if (polylinePoints.length > 1) {
              polylines = {
                Polyline(
                  polylineId: const PolylineId("route"),
                  points: polylinePoints,
                  width: 5,
                  color: Colors.blue,
                ),
              };
            }
            
            stopMarkers = stopSet;
          });
          
          if (mapController != null && isTracking && lat != 0 && lng != 0) {
            mapController!.animateCamera(
              CameraUpdate.newLatLng(newPosition),
            );
          }
        } else {
          setState(() {
            isLoading = false;
            studentName = data["student_name"] ?? "Student";
            attendance = newAttendance;
          });
        }
        
        print("✅ Parent updated: Bus at ($lat, $lng)");
      } else {
        print("❌ Parent API error: ${response.statusCode}");
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print("❌ Parent fetch error: $e");
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // ---------------- SHOW ATTENDANCE NOTIFICATION ----------------

  void _showAttendanceNotification(String name, String status) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Icon(status == "Present" ? Icons.check_circle : Icons.cancel, 
                   color: status == "Present" ? Colors.green : Colors.red),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "$name $status!",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      status == "Present" 
                          ? "Student has boarded the bus"
                          : "Student is absent today",
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        backgroundColor: status == "Present" ? Colors.green : Colors.orange,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ---------------- AUTO REFRESH ----------------

  void startAutoRefresh() {
    timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        fetchLocation();
      }
    });
  }
  
  // ---------------- ZOOM TO BUS ----------------

  void zoomToBus() {
    if (mapController != null && busLocation.latitude != 0 && busLocation.longitude != 0) {
      mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(busLocation, 15),
      );
      setState(() {
        isTracking = true;
      });
    }
  }
  
  // ---------------- TOGGLE TRACKING ----------------

  void toggleTracking() {
    setState(() {
      isTracking = !isTracking;
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Live Bus Tracking"),
        backgroundColor: const Color(0xFF0A84FF),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchLocation,
            tooltip: "Refresh",
          ),
          IconButton(
            icon: Icon(isTracking ? Icons.gps_fixed : Icons.gps_off),
            onPressed: toggleTracking,
            tooltip: isTracking ? "Tracking ON" : "Tracking OFF",
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: zoomToBus,
            tooltip: "Zoom to Bus",
          ),
        ],
      ),
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: busLocation,
              zoom: 14,
            ),
            onMapCreated: (controller) {
              mapController = controller;
            },
            onCameraMove: (_) {
              if (isTracking) {
                setState(() {
                  isTracking = false;
                });
              }
            },
            markers: {...markers, ...stopMarkers},
            polylines: polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            compassEnabled: true,
          ),
          
          // Loading Indicator
          if (isLoading)
            Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0A84FF)),
                ),
              ),
            ),
          
          // No Data Message
          if (!isLoading && busLocation.latitude == 0 && busLocation.longitude == 0)
            Container(
              color: Colors.black45,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_off, size: 50, color: Colors.grey),
                      SizedBox(height: 10),
                      Text(
                        "Waiting for driver to start tracking...",
                        style: TextStyle(fontSize: 16),
                      ),
                      SizedBox(height: 5),
                      Text(
                        "Please ask the driver to start the GPS",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          // Info Panel
          if (!isLoading && busLocation.latitude != 0)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        border: Border.all(
                          color: const Color(0xFF0A84FF).withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Student Info
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A84FF).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.person,
                                  color: Color(0xFF0A84FF),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      studentName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      "Student ID: ${widget.studentId}",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: attendance == "Present" 
                                      ? Colors.green.withOpacity(0.1)
                                      : Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: attendance == "Present" ? Colors.green : Colors.red,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      attendance == "Present" ? Icons.check : Icons.close,
                                      size: 12,
                                      color: attendance == "Present" ? Colors.green : Colors.red,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      attendance,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: attendance == "Present" ? Colors.green : Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 12),
                          
                          // Bus Info
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.directions_bus,
                                  color: Color(0xFF0A84FF),
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Bus $busId",
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      Text(
                                        delay,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: delay.contains("Delay") 
                                              ? Colors.orange 
                                              : Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      "${busSpeed.toStringAsFixed(1)} km/h",
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0A84FF),
                                      ),
                                    ),
                                    Text(
                                      "Speed",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 8),
                          
                          // ETA and Arrival Info
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  color: Color(0xFF0A84FF),
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        "Estimated Arrival",
                                        style: TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                      Text(
                                        eta,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0A84FF),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (attendanceTime.isNotEmpty)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text(
                                        "Boarded at",
                                        style: TextStyle(fontSize: 10, color: Colors.grey),
                                      ),
                                      Text(
                                        attendanceTime,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 8),
                          
                          // Tracking Status
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: isTracking ? Colors.green : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isTracking ? "Live Tracking Active" : "Manual Map Control",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isTracking ? Colors.green : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          
                          // Attendance Notification Indicator
                          if (hasNewAttendance)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.notifications_active, size: 14, color: Colors.green),
                                    SizedBox(width: 6),
                                    Text(
                                      "New attendance update!",
                                      style: TextStyle(fontSize: 11, color: Colors.green),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}