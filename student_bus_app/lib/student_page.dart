import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:geocoding/geocoding.dart';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';

class StudentPage extends StatefulWidget {
  final String busId;

  const StudentPage({Key? key, required this.busId}) : super(key: key);

  @override
  _StudentPageState createState() => _StudentPageState();
}

class _StudentPageState extends State<StudentPage> {

  String server = "https://bus-transport-server.onrender.com";

  GoogleMapController? mapController;
  Timer? timer;

  LatLng busLocation = const LatLng(13.013396, 79.132097);
  Set<Marker> markers = {};

  String delayStatus = "Checking...";
  String etaStatus = "Calculating...";
  double latitude = 0;
  double longitude = 0;
  double distanceToCollege = 0;

  String locationName = "Fetching location...";
  double prevLat = 0;
  double prevLng = 0;
  DateTime? lastUpdate;
  String busStatus = "Checking...";
  double currentSpeed = 0;

  bool isLoading = true;
  bool mapReady = false;
  bool isSendingEmergency = false;
  
  String scanStatus = "Waiting for bus location...";
  
  BitmapDescriptor busIcon = BitmapDescriptor.defaultMarker;

  // ---------------- DISTANCE CALCULATION ----------------

  double calculateDistance(lat1, lon1, lat2, lon2) {
    const R = 6371;
    var dLat = (lat2 - lat1) * pi / 180;
    var dLon = (lon2 - lon1) * pi / 180;
    var a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            (sin(dLon / 2) * sin(dLon / 2));
    var c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  // ---------------- ETA CALCULATION ----------------

  String calculateETA(double distanceKm, double speedKmh) {
    if (speedKmh <= 0) {
      return "Unknown";
    }
    double timeHours = distanceKm / speedKmh;
    int minutes = (timeHours * 60).round();
    
    if (minutes < 1) {
      return "< 1 min";
    } else if (minutes < 60) {
      return "$minutes mins";
    } else {
      int hours = minutes ~/ 60;
      int mins = minutes % 60;
      return "$hours h $mins m";
    }
  }

  // ---------------- LOCATION NAME ----------------

  Future getLocationName(double lat, double lng) async {
    try {
      if (lat == 0 && lng == 0) {
        if (mounted) {
          setState(() {
            locationName = "Waiting for live location...";
          });
        }
        return;
      }

      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty && mounted) {
        Placemark place = placemarks[0];
        setState(() {
          locationName = "${place.locality ?? ''}, ${place.subAdministrativeArea ?? ''}";
          if (locationName == ", " || locationName == "") {
            locationName = "${place.street ?? ''}, ${place.country ?? ''}";
          }
          if (locationName == "" || locationName == ", ") {
            locationName = "Current Location";
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          locationName = "Location not found";
        });
      }
    }
  }

  // ---------------- LOAD BUS ICON ----------------

  Future loadBusIcon() async {
    try {
      busIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/bus.png',
      );
    } catch (e) {
      print("Error loading bus icon: $e");
      busIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
  }

  // ---------------- FETCH LOCATION ----------------

  Future fetchLocation() async {
    try {
      setState(() {
        scanStatus = "Fetching bus location...";
      });
      
      var url = Uri.parse("$server/getLocation/${widget.busId}");
      var response = await http.get(url);

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);

        double lat = (data["latitude"] as num).toDouble();
        double lng = (data["longitude"] as num).toDouble();
        String delay = data["delay"] ?? "Unknown";
        double speed = (data["speed"] as num?)?.toDouble() ?? 0;
        String eta = data["eta"] ?? "Calculating...";
        double distance = (data["distance_to_college"] as num?)?.toDouble() ?? 0;

        getLocationName(lat, lng);

        // Calculate speed if not provided
        if (speed == 0 && lastUpdate != null && prevLat != 0) {
          double distanceMoved = calculateDistance(prevLat, prevLng, lat, lng);
          double timeDiff = DateTime.now().difference(lastUpdate!).inSeconds / 3600;
          if (timeDiff > 0) {
            speed = distanceMoved / timeDiff;
          }
        }

        prevLat = lat;
        prevLng = lng;
        lastUpdate = DateTime.now();

        String status;
        if (speed == 0) {
          status = "Stopped";
        } else if (speed < 10) {
          status = "Slow";
        } else {
          status = "Moving";
        }

        // Recalculate ETA if needed
        if (eta == "Calculating..." || eta == "Unknown") {
          eta = calculateETA(distance, speed);
        }

        LatLng newPosition = LatLng(lat, lng);

        if (!mounted) return;

        // Save to local storage
        final prefs = await SharedPreferences.getInstance();
        prefs.setDouble("lat", lat);
        prefs.setDouble("lng", lng);
        prefs.setString("locationName", locationName);
        prefs.setString("delay", delay);
        prefs.setString("eta", eta);
        prefs.setString("status", status);
        prefs.setDouble("speed", speed);
        prefs.setDouble("distance", distance);

        setState(() {
          isLoading = false;
          latitude = lat;
          longitude = lng;
          delayStatus = delay;
          etaStatus = eta;
          busStatus = status;
          currentSpeed = speed;
          distanceToCollege = distance;
          busLocation = newPosition;
          scanStatus = speed > 0 ? "Bus is moving" : "Bus is stationary";

          markers = {
            Marker(
              markerId: const MarkerId("bus"),
              position: newPosition,
              icon: busIcon,
              infoWindow: InfoWindow(
                title: "Bus ${widget.busId}",
                snippet: "$delay | ETA: $eta",
              ),
              rotation: 0,
              anchor: const Offset(0.5, 0.5),
            )
          };
        });

        if (mapReady && mounted) {
          mapController?.animateCamera(
            CameraUpdate.newLatLng(newPosition),
          );
        }
        
        // Check for geofencing alert (near college)
        if (distance < 0.5 && distance > 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("🎓 Bus is approaching college campus!"),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } else {
        print("❌ Location API error: ${response.statusCode}");
        _loadCachedData();
      }
    } catch (e) {
      print("❌ Network error: $e");
      _loadCachedData();
    }
  }

  // ---------------- LOAD CACHED DATA (OFFLINE MODE) ----------------

  Future _loadCachedData() async {
    if (mounted) {
      setState(() {
        scanStatus = "Offline mode - showing last known location";
      });
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      double? lat = prefs.getDouble("lat");
      double? lng = prefs.getDouble("lng");
      
      if (lat != null && lng != null && mounted) {
        setState(() {
          isLoading = false;
          latitude = lat;
          longitude = lng;
          locationName = prefs.getString("locationName") ?? "Offline Mode";
          delayStatus = prefs.getString("delay") ?? "Offline Mode";
          etaStatus = prefs.getString("eta") ?? "Unknown";
          busStatus = prefs.getString("status") ?? "Offline";
          currentSpeed = prefs.getDouble("speed") ?? 0;
          distanceToCollege = prefs.getDouble("distance") ?? 0;
          scanStatus = "Offline mode - cached location";
          
          busLocation = LatLng(lat, lng);
          
          markers = {
            Marker(
              markerId: const MarkerId("bus"),
              position: LatLng(lat, lng),
              icon: busIcon,
              infoWindow: InfoWindow(
                title: "Bus ${widget.busId}",
                snippet: "Offline Mode",
              ),
              rotation: 0,
              anchor: const Offset(0.5, 0.5),
            )
          };
        });
        
        if (mapReady && mounted) {
          mapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(lat, lng)),
          );
        }
      } else {
        setState(() {
          isLoading = false;
          delayStatus = "No Data Available";
          etaStatus = "Unknown";
          busStatus = "Offline";
          locationName = "No cached data";
          scanStatus = "No data available - waiting for driver";
        });
      }
    } catch (storageError) {
      if (mounted) {
        setState(() {
          isLoading = false;
          delayStatus = "Error";
          etaStatus = "Error";
          busStatus = "Error";
          locationName = "Storage error";
          scanStatus = "Error loading data";
        });
      }
    }
  }

  // ---------------- SEND EMERGENCY ALERT ----------------

  Future sendEmergencyAlert() async {
    if (latitude == 0 || longitude == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("📍 Waiting for location data..."),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Show confirmation dialog
    bool? confirmed = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text("SEND EMERGENCY ALERT?"),
          ],
        ),
        content: const Text(
          "This will notify the driver and admin immediately.\n\nOnly use in real emergencies!",
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Colors.red, Color(0xFFC62828)]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              child: const Text("Send Alert"),
            ),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );

    if (confirmed != true) return;

    setState(() {
      isSendingEmergency = true;
    });

    try {
      var url = Uri.parse("$server/sendEmergency");
      var response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "student_reg": "STUDENT_ID", // This should come from login
          "bus_id": widget.busId,
          "latitude": latitude,
          "longitude": longitude,
          "location_name": locationName,
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🚨 Emergency Alert Sent! Help is on the way."),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      } else {
        throw Exception("Failed to send alert");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Failed to send alert: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        isSendingEmergency = false;
      });
    }
  }

  // ---------------- AUTO REFRESH ----------------

  void startAutoTracking() {
    timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        fetchLocation();
      }
    });
  }

  // ---------------- HELPER METHODS ----------------

  Color _getStatusColor(String status) {
    if (status == "Moving") return Colors.green;
    if (status == "Slow") return Colors.orange;
    if (status == "Stopped") return Colors.red;
    if (status == "Offline") return Colors.grey;
    return const Color(0xFF0A84FF);
  }

  IconData _getStatusIcon(String status) {
    if (status == "Moving") return Icons.directions_bus;
    if (status == "Slow") return Icons.speed;
    if (status == "Stopped") return Icons.stop_circle;
    if (status == "Offline") return Icons.cloud_off;
    return Icons.info;
  }

  Color _getDelayColor(String status) {
    if (status.toLowerCase().contains("on time")) return Colors.green;
    if (status.toLowerCase().contains("delay")) return Colors.orange;
    if (status.toLowerCase().contains("error")) return Colors.red;
    if (status.toLowerCase().contains("offline")) return Colors.grey;
    return const Color(0xFF0A84FF);
  }

  String _getLastUpdateText() {
    if (busStatus == "Offline") return "Offline Mode";
    if (lastUpdate == null) return "Just now";
    final diff = DateTime.now().difference(lastUpdate!);
    if (diff.inSeconds < 5) return "Just now";
    return "${diff.inSeconds}s ago";
  }

  String _getMapStyle() {
    return '''
    [
      {
        "elementType": "geometry",
        "stylers": [{"color": "#242f3e"}]
      },
      {
        "elementType": "labels.text.fill",
        "stylers": [{"color": "#746855"}]
      },
      {
        "featureType": "road",
        "elementType": "geometry",
        "stylers": [{"color": "#38414e"}]
      },
      {
        "featureType": "water",
        "elementType": "geometry.fill",
        "stylers": [{"color": "#0A84FF"}]
      }
    ]
    ''';
  }

  @override
  void initState() {
    super.initState();
    loadBusIcon();
    fetchLocation();
    startAutoTracking();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A84FF), Color(0xFF003B8E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.directions_bus_filled,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Live Bus Tracking",
                            style: TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                          Text(
                            "Bus ${widget.busId}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Status indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(busStatus).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _getStatusColor(busStatus), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _getStatusColor(busStatus),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            busStatus,
                            style: TextStyle(
                              color: _getStatusColor(busStatus),
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                        onPressed: fetchLocation,
                        tooltip: 'Refresh location',
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                    ),
                  ],
                ),
              ),

              // Map
              Expanded(
                flex: 3,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00D4FF).withOpacity(0.3),
                        blurRadius: 15,
                        spreadRadius: 0,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: busLocation,
                        zoom: 15,
                      ),
                      onMapCreated: (controller) {
                        mapController = controller;
                        setState(() {
                          mapReady = true;
                        });
                      },
                      markers: markers,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                      zoomControlsEnabled: true,
                      compassEnabled: true,
                      mapToolbarEnabled: false,
                      style: _getMapStyle(),
                    ),
                  ),
                ),
              ),

              // Info Panel
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00D4FF).withOpacity(0.2),
                              blurRadius: 10,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF0A84FF), Color(0xFF1E90FF)],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.location_on,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    "Current Location",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                if (busStatus != "Offline")
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: Colors.green,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          "LIVE",
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Location name
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: busStatus == "Offline" ? Colors.grey.withOpacity(0.1) : const Color(0xFFF5F5F5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: busStatus == "Offline"
                                      ? Colors.grey.withOpacity(0.3)
                                      : const Color(0xFF0A84FF).withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    busStatus == "Offline" ? Icons.cloud_off : Icons.location_on,
                                    color: busStatus == "Offline" ? Colors.grey : const Color(0xFF0A84FF),
                                    size: 14,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      locationName,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: busStatus == "Offline" ? Colors.grey[600] : const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Coordinates Row
                            Row(
                              children: [
                                Expanded(
                                  child: _buildCompactInfoTile(
                                    icon: Icons.north_east,
                                    label: "Latitude",
                                    value: latitude.toStringAsFixed(6),
                                    isOffline: busStatus == "Offline",
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildCompactInfoTile(
                                    icon: Icons.south_east,
                                    label: "Longitude",
                                    value: longitude.toStringAsFixed(6),
                                    isOffline: busStatus == "Offline",
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Speed, ETA, Delay Row
                            Row(
                              children: [
                                Expanded(
                                  child: _buildCompactSpeedTile(currentSpeed, isOffline: busStatus == "Offline"),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildCompactETATile(etaStatus, isOffline: busStatus == "Offline"),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildCompactDelayTile(delayStatus, isOffline: busStatus == "Offline"),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Distance to college
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F5F5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.school, color: Color(0xFF0A84FF), size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Distance to College: ",
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                  Text(
                                    distanceToCollege > 0 ? "${distanceToCollege.toStringAsFixed(1)} km" : "Calculating...",
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0A84FF),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Bus Status Card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _getStatusColor(busStatus).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _getStatusColor(busStatus)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _getStatusIcon(busStatus),
                                    color: _getStatusColor(busStatus),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          "Bus Status",
                                          style: TextStyle(fontSize: 11, color: Color(0xFF0F172A)),
                                        ),
                                        Text(
                                          busStatus,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: _getStatusColor(busStatus),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    _getLastUpdateText(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: const Color(0xFF0F172A).withOpacity(0.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Status Message
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: scanStatus.contains("waiting") 
                                    ? Colors.orange.withOpacity(0.1)
                                    : scanStatus.contains("offline")
                                        ? Colors.grey.withOpacity(0.1)
                                        : Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: scanStatus.contains("waiting") 
                                      ? Colors.orange
                                      : scanStatus.contains("offline")
                                          ? Colors.grey
                                          : Colors.green,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    scanStatus.contains("waiting") 
                                        ? Icons.timer
                                        : scanStatus.contains("offline")
                                            ? Icons.cloud_off
                                            : Icons.gps_fixed,
                                    size: 14,
                                    color: scanStatus.contains("waiting") 
                                        ? Colors.orange
                                        : scanStatus.contains("offline")
                                            ? Colors.grey
                                            : Colors.green,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      scanStatus,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: scanStatus.contains("waiting") 
                                            ? Colors.orange
                                            : scanStatus.contains("offline")
                                                ? Colors.grey
                                                : Colors.green,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Emergency Button
                            Container(
                              width: double.infinity,
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(colors: [Color(0xFFFF4B4B), Color(0xFFC62828)]),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.4),
                                    blurRadius: 12,
                                    spreadRadius: 0,
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: isSendingEmergency ? null : sendEmergencyAlert,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                child: isSendingEmergency
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
                                          Icon(Icons.warning_amber_rounded, size: 20),
                                          SizedBox(width: 8),
                                          Text("🚨 EMERGENCY - Send Alert", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Offline Mode Message
                            if (busStatus == "Offline")
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.orange),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.wifi_off, color: Colors.orange, size: 14),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        "Offline Mode - Showing last known location",
                                        style: TextStyle(fontSize: 11, color: Colors.orange),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            const SizedBox(height: 12),

                            // Bottom accent
                            Center(
                              child: Container(
                                height: 3,
                                width: 60,
                                decoration: BoxDecoration(
                                  color: busStatus == "Offline" ? Colors.grey : const Color(0xFF00D4FF),
                                  borderRadius: BorderRadius.circular(1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (busStatus == "Offline" ? Colors.grey : const Color(0xFF00D4FF)).withOpacity(0.5),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 16),
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

  // Helper widgets
  Widget _buildCompactInfoTile({
    required IconData icon,
    required String label,
    required String value,
    bool isOffline = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isOffline ? Colors.grey.withOpacity(0.1) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: isOffline ? Colors.grey : const Color(0xFF0A84FF), size: 12),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: isOffline ? Colors.grey : const Color(0xFF0F172A).withOpacity(0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isOffline ? Colors.grey : const Color(0xFF0F172A),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactSpeedTile(double speed, {bool isOffline = false}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: isOffline 
            ? LinearGradient(colors: [Colors.grey.withOpacity(0.1), Colors.grey.withOpacity(0.05)])
            : LinearGradient(colors: [const Color(0xFF0A84FF).withOpacity(0.1), const Color(0xFF0A84FF).withOpacity(0.05)]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isOffline ? Colors.grey.withOpacity(0.3) : const Color(0xFF0A84FF).withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.speed, color: isOffline ? Colors.grey : const Color(0xFF0A84FF), size: 20),
          const SizedBox(height: 4),
          Text(
            "${speed.toStringAsFixed(1)}",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isOffline ? Colors.grey : const Color(0xFF0A84FF),
            ),
          ),
          const Text(
            "km/h",
            style: TextStyle(fontSize: 9, color: Color(0xFF0F172A)),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactETATile(String eta, {bool isOffline = false}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isOffline ? Colors.grey.withOpacity(0.1) : const Color(0xFF0A84FF).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isOffline ? Colors.grey : const Color(0xFF0A84FF)),
      ),
      child: Column(
        children: [
          Icon(Icons.access_time, color: isOffline ? Colors.grey : const Color(0xFF0A84FF), size: 20),
          const SizedBox(height: 4),
          Text(
            eta,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isOffline ? Colors.grey : const Color(0xFF0A84FF),
            ),
            textAlign: TextAlign.center,
          ),
          const Text(
            "ETA",
            style: TextStyle(fontSize: 9, color: Color(0xFF0F172A)),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactDelayTile(String delay, {bool isOffline = false}) {
    Color color = isOffline ? Colors.grey : _getDelayColor(delay);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isOffline ? Colors.grey.withOpacity(0.1) : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Column(
        children: [
          Icon(isOffline ? Icons.cloud_off : Icons.watch_later, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            delay,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}