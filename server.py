from flask import Flask, request, jsonify, send_file
import pandas as pd
import sqlite3
import csv
import math
import time
import os
import numpy as np
import base64
from io import BytesIO
from datetime import datetime, timedelta
from PIL import Image

# Face recognition imports
try:
    import face_recognition
    FACE_RECOGNITION_AVAILABLE = True
except ImportError:
    FACE_RECOGNITION_AVAILABLE = False
    print("⚠️ Face_recognition not installed. Install with: pip install face_recognition")

app = Flask(__name__)

EXCEL_FILE = "transport_data.xlsx"

COLLEGE_LAT = 13.013396
COLLEGE_LON = 79.132097
GATE_RADIUS = 0.2

# ---------------- DATABASE ----------------

conn = sqlite3.connect("transport.db", check_same_thread=False)
cursor = conn.cursor()

cursor.execute("""
CREATE TABLE IF NOT EXISTS bus_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bus_id TEXT,
    entry_time TEXT,
    exit_time TEXT,
    arrival_time TEXT
)
""")

# 🔥 Create anomaly logs table
cursor.execute("""
CREATE TABLE IF NOT EXISTS anomaly_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bus_id TEXT,
    anomaly_type TEXT,
    latitude REAL,
    longitude REAL,
    speed REAL,
    timestamp TEXT,
    status TEXT
)
""")

# 🔥 Create face attendance table
cursor.execute("""
CREATE TABLE IF NOT EXISTS face_attendance (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id TEXT,
    bus_id TEXT,
    time TEXT,
    status TEXT
)
""")

# 🔥 Create SOS alerts table
cursor.execute("""
CREATE TABLE IF NOT EXISTS sos_alerts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id TEXT,
    bus_id TEXT,
    latitude REAL,
    longitude REAL,
    location_name TEXT,
    timestamp TEXT,
    status TEXT
)
""")

conn.commit()

# ---------------- ANOMALY TRACKING ----------------

bus_history = {}  # store previous locations with timestamps
bus_anomalies = {}  # store current anomaly messages
anomaly_alerted = {}  # track if anomaly already notified

# Define route boundaries (adjust based on your college location)
# For Vellore area (latitude: 12.9 to 13.1, longitude: 79.1 to 79.3)
MIN_LAT = 12.9
MAX_LAT = 13.1
MIN_LON = 79.0
MAX_LON = 79.3

# Define speed limits (km/h)
OVERSPEED_LIMIT = 80  # Overspeeding if > 80 km/h
STOP_DURATION_THRESHOLD = 300  # 5 minutes = 300 seconds

# ---------------- GEOFENCING ----------------

BUS_STOPS = [
    {"name": "Main Gate", "lat": 13.013396, "lon": 79.132097},
    {"name": "Library Stop", "lat": 13.014, "lon": 79.133},
    {"name": "Hostel Stop", "lat": 13.012, "lon": 79.131},
]

geo_alerts = []

# ---------------- DRIVER BEHAVIOR ----------------

driver_behavior = {}

# ---------------- ANALYTICS ----------------

speed_records = []
delay_records = []

# ---------------- FACE ATTENDANCE ----------------

face_attendance = []
known_face_encodings = []
known_face_ids = []

def load_known_faces():
    """Load all student face images from faces/ folder"""
    if not FACE_RECOGNITION_AVAILABLE:
        print("Face recognition not available")
        return
    
    folder = "faces"
    
    if not os.path.exists(folder):
        os.makedirs(folder)
        print(f"Created {folder} folder. Add student images as 'register_number.jpg'")
        return
    
    for file in os.listdir(folder):
        if file.endswith((".jpg", ".jpeg", ".png")):
            path = os.path.join(folder, file)
            try:
                image = face_recognition.load_image_file(path)
                encodings = face_recognition.face_encodings(image)
                
                if encodings:
                    known_face_encodings.append(encodings[0])
                    student_id = os.path.splitext(file)[0]
                    known_face_ids.append(student_id)
                    print(f"Loaded face for student: {student_id}")
                else:
                    print(f"No face detected in {file}")
            except Exception as e:
                print(f"Error loading {file}: {e}")

# Load faces on startup
load_known_faces()

# ---------------- ANOMALY DETECTION FUNCTION ----------------

def detect_anomaly(bus_id, lat, lon, speed):
    """
    Detect anomalies in bus movement:
    - Overspeeding: speed > 80 km/h
    - Unexpected Stop: bus stopped for > 5 minutes
    - Route Deviation: bus outside defined route boundaries
    """
    anomaly = None
    current_time = datetime.now()
    
    # 🚫 Check for Overspeeding
    if speed > OVERSPEED_LIMIT:
        anomaly = "Overspeeding"
        print(f"⚠️ ANOMALY: Bus {bus_id} is overspeeding at {speed} km/h")
    
    # ⛔ Check for Unexpected Stop (bus stopped and last location was moving)
    elif speed == 0:
        if bus_id in bus_history:
            last_time = bus_history[bus_id]["time"]
            last_speed = bus_history[bus_id]["speed"]
            
            # Only flag if last speed was > 0 (bus was moving before stopping)
            if last_speed > 0:
                time_diff = (current_time - last_time).total_seconds()
                
                if time_diff > STOP_DURATION_THRESHOLD:
                    anomaly = "Unexpected Stop"
                    print(f"⚠️ ANOMALY: Bus {bus_id} has been stopped for {int(time_diff)} seconds")
    
    # 🔀 Check for Route Deviation
    if lat < MIN_LAT or lat > MAX_LAT or lon < MIN_LON or lon > MAX_LON:
        anomaly = "Route Deviation"
        print(f"⚠️ ANOMALY: Bus {bus_id} deviated from route at ({lat}, {lon})")
    
    # Save to history
    bus_history[bus_id] = {
        "lat": lat,
        "lon": lon,
        "speed": speed,
        "time": current_time
    }
    
    # Store anomaly if detected
    if anomaly:
        # Only store if different from last stored anomaly or if time elapsed
        if bus_id not in anomaly_alerted or anomaly_alerted[bus_id] != anomaly:
            bus_anomalies[bus_id] = {
                "anomaly": anomaly,
                "lat": lat,
                "lon": lon,
                "speed": speed,
                "time": current_time.strftime("%Y-%m-%d %H:%M:%S")
            }
            anomaly_alerted[bus_id] = anomaly
            
            # 🔥 Save anomaly to database
            try:
                cursor.execute("""
                    INSERT INTO anomaly_logs (bus_id, anomaly_type, latitude, longitude, speed, timestamp, status)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (bus_id, anomaly, lat, lon, speed, current_time.strftime("%Y-%m-%d %H:%M:%S"), "active"))
                conn.commit()
            except Exception as e:
                print(f"Error saving anomaly to database: {e}")
    else:
        # Clear anomaly if bus is back to normal
        if bus_id in bus_anomalies:
            # Update anomaly status to resolved in database
            try:
                cursor.execute("""
                    UPDATE anomaly_logs 
                    SET status = 'resolved' 
                    WHERE bus_id = ? AND status = 'active'
                """, (bus_id,))
                conn.commit()
            except Exception as e:
                print(f"Error updating anomaly status: {e}")
            del bus_anomalies[bus_id]
            if bus_id in anomaly_alerted:
                del anomaly_alerted[bus_id]
    
    return anomaly

# ---------------- GEO-FENCING FUNCTION ----------------

def check_geofence(bus_id, lat, lon):
    """Check if bus has entered any geofenced areas"""
    alerts = []
    
    # College check
    distance_to_college = calculate_distance(lat, lon, COLLEGE_LAT, COLLEGE_LON)
    
    if distance_to_college < GATE_RADIUS:
        alerts.append(f"Bus {bus_id} entered college campus")
    
    # Stops check
    for stop in BUS_STOPS:
        dist = calculate_distance(lat, lon, stop["lat"], stop["lon"])
        
        if dist < 0.1:  # 100 meters radius
            alerts.append(f"Bus {bus_id} reached {stop['name']}")
    
    # Store alerts
    for alert in alerts:
        geo_alerts.append({
            "bus_id": bus_id,
            "message": alert,
            "time": datetime.now().isoformat()
        })
    
    return alerts

# ---------------- DRIVER BEHAVIOR MONITORING ----------------

def monitor_driver_behavior(bus_id, speed):
    """Monitor driver behavior for harsh driving patterns"""
    behavior = None
    
    # 🚫 Overspeeding
    if speed > OVERSPEED_LIMIT:
        behavior = "Overspeeding"
    
    # ⚠️ Harsh braking / acceleration (basic)
    if bus_id in driver_behavior:
        prev_speed = driver_behavior[bus_id]["speed"]
        speed_diff = abs(speed - prev_speed)
        
        if speed_diff > 30:  # Sudden speed change > 30 km/h
            behavior = "Harsh Driving"
    
    # Store latest speed
    driver_behavior[bus_id] = {
        "speed": speed,
        "time": datetime.now().isoformat()
    }
    
    return behavior

# ---------------- DELAY PREDICTION ----------------

def predict_delay(distance_km, speed_kmph):

    if speed_kmph == 0:
        return "Bus Stopped"

    eta = (distance_km / speed_kmph) * 60

    if eta > 10:
        return "Bus Delayed"

    elif eta > 5:
        return "Slight Delay"

    else:
        return "On Time"


# ---------------- DISTANCE CALCULATION ----------------

def calculate_distance(lat1, lon1, lat2, lon2):

    R = 6371

    dLat = math.radians(lat2 - lat1)
    dLon = math.radians(lon2 - lon1)

    a = (
        math.sin(dLat/2) * math.sin(dLat/2) +
        math.cos(math.radians(lat1)) *
        math.cos(math.radians(lat2)) *
        math.sin(dLon/2) * math.sin(dLon/2)
    )

    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))

    return R * c


# ==================== ROUTES ====================

@app.route("/")
def home():
    """Home route to check if server is running"""
    return jsonify({
        "status": "running",
        "message": "College Transport System API",
        "features": [
            "Real-time bus tracking",
            "Face recognition attendance",
            "Emergency alerts",
            "Anomaly detection",
            "Geo-fencing",
            "Voice assistant"
        ]
    })


# ---------------- GET BUSES ----------------

@app.route("/getBuses")
def get_buses():

    df = pd.read_excel(EXCEL_FILE, sheet_name="Buses")
    buses = df["bus_id"].tolist()

    return jsonify(buses)


# ---------------- STUDENT LOGIN ----------------

@app.route("/studentLogin", methods=["POST"])
def student_login():

    data = request.json
    reg_no = data["reg_no"]

    df = pd.read_excel(EXCEL_FILE, sheet_name="Students")

    student = df[df["reg_no"] == int(reg_no)]

    if student.empty:
        return jsonify({"status":"error"})

    bus = student.iloc[0]["bus_id"]

    return jsonify({
        "status":"success",
        "bus_id":bus
    })


# 🔥🔥🔥 NEW: GET STUDENTS BY BUS (FIX) 🔥🔥🔥
@app.route("/getStudentsByBus/<bus_id>")
def get_students_by_bus(bus_id):
    """Get all students assigned to a specific bus"""
    try:
        df = pd.read_excel(EXCEL_FILE, sheet_name="Students")
        
        # Filter students by bus_id
        students = df[df["bus_id"] == bus_id]
        
        # Convert to list of dictionaries
        result = students[["reg_no", "name"]].to_dict(orient="records")
        
        return jsonify(result)
        
    except Exception as e:
        print(f"Error getting students: {e}")
        return jsonify({"error": str(e)}), 500


# ---------------- BUS CROWD PREDICTION ----------------

bus_boarded = {}

@app.route("/boardBus", methods=["POST"])
def board_bus():

    data = request.json
    bus = data["bus_id"]

    if bus not in bus_boarded:
        bus_boarded[bus] = 0

    bus_boarded[bus] += 1

    return {"count": bus_boarded[bus]}


# ---------------- GET BUS STOPS ----------------

@app.route("/getStops/<bus_id>")
def get_stops(bus_id):

    df = pd.read_excel(EXCEL_FILE, sheet_name="Stops")

    stops = df[df["bus_id"] == bus_id]

    return jsonify(stops.to_dict(orient="records"))


# ---------------- SAVE BUS LOCATION (WITH ALL FEATURES) ----------------

bus_locations = {}

@app.route("/sendLocation", methods=["POST"])
def send_location():

    data = request.json

    bus_id = data["bus_id"]
    latitude = data["latitude"]
    longitude = data["longitude"]
    
    # Get speed from request (if available), otherwise calculate from previous location
    speed = data.get("speed", 30)
    
    # If we have previous location, calculate actual speed
    if bus_id in bus_locations:
        prev_lat = bus_locations[bus_id]["latitude"]
        prev_lng = bus_locations[bus_id]["longitude"]
        distance = calculate_distance(prev_lat, prev_lng, latitude, longitude)
        
        # Time difference (assuming 5 seconds between updates)
        speed = (distance / 5) * 3600  # km/h

    bus_locations[bus_id] = {
        "latitude": latitude,
        "longitude": longitude,
        "last_update": time.time()
    }

    # 🔥 CALL ANOMALY DETECTION
    anomaly = detect_anomaly(bus_id, latitude, longitude, speed)
    
    # 🔥 CALL GEO-FENCING
    geo_alerts_list = check_geofence(bus_id, latitude, longitude)
    
    # 🔥 CALL DRIVER BEHAVIOR MONITORING
    behavior = monitor_driver_behavior(bus_id, speed)
    
    # 🔥 Store speed for analytics
    speed_records.append(speed)
    if len(speed_records) > 1000:
        speed_records.pop(0)
    
    # Delay tracking for analytics
    delay_status = predict_delay(calculate_distance(latitude, longitude, COLLEGE_LAT, COLLEGE_LON), speed)
    delay_records.append(delay_status)
    if len(delay_records) > 1000:
        delay_records.pop(0)

    distance = calculate_distance(latitude, longitude, COLLEGE_LAT, COLLEGE_LON)

    if distance < GATE_RADIUS:
        print("Bus reached college:", bus_id)

    return jsonify({
        "status": "ok",
        "anomaly": anomaly,
        "geo_alerts": geo_alerts_list,
        "behavior": behavior,
        "speed": round(speed, 2)
    })


# ---------------- GET LOCATION ----------------

@app.route("/getLocation/<bus_id>")
def get_location(bus_id):

    if bus_id in bus_locations:

        lat = bus_locations[bus_id]["latitude"]
        lng = bus_locations[bus_id]["longitude"]

        distance = calculate_distance(lat, lng, COLLEGE_LAT, COLLEGE_LON)
        speed = 30  # Default speed

        delay_status = predict_delay(distance, speed)

        # Check if there's an anomaly for this bus
        anomaly_info = None
        if bus_id in bus_anomalies:
            anomaly_info = bus_anomalies[bus_id]

        response = {
            "latitude": lat,
            "longitude": lng,
            "delay": delay_status
        }
        
        if anomaly_info:
            response["anomaly"] = anomaly_info["anomaly"]
            response["anomaly_detected"] = True

        return jsonify(response)

    return jsonify({
        "latitude":0,
        "longitude":0,
        "delay":"Unknown"
    })


# 🔥🔥🔥 NEW: FACE RECOGNITION API (FIX) 🔥🔥🔥
@app.route("/recognizeFace", methods=["POST"])
def recognize_face():
    """Recognize face from image and return student ID"""
    
    if not FACE_RECOGNITION_AVAILABLE:
        return jsonify({
            "status": "error", 
            "message": "Face recognition library not installed"
        })

    try:
        data = request.json
        image_data = data.get("image", "")
        
        if not image_data:
            return jsonify({"status": "error", "message": "No image data"})
        
        # Decode base64 image
        image_bytes = base64.b64decode(image_data)
        image = Image.open(BytesIO(image_bytes))
        image = np.array(image)
        
        # Detect faces
        face_locations = face_recognition.face_locations(image)
        face_encodings = face_recognition.face_encodings(image, face_locations)
        
        if not face_encodings:
            return jsonify({"status": "unknown", "message": "No face detected"})
        
        face_encoding = face_encodings[0]
        
        if not known_face_encodings:
            return jsonify({"status": "error", "message": "No registered faces found"})
        
        # Compare with known faces
        matches = face_recognition.compare_faces(known_face_encodings, face_encoding)
        face_distances = face_recognition.face_distance(known_face_encodings, face_encoding)
        
        best_match_index = np.argmin(face_distances)
        
        if matches[best_match_index]:
            student_id = known_face_ids[best_match_index]
            confidence = float(1 - face_distances[best_match_index])
            
            return jsonify({
                "status": "recognized",
                "reg_no": student_id,
                "name": student_id,
                "confidence": round(confidence, 2)
            })
        
        return jsonify({"status": "unknown", "message": "Face not recognized"})
        
    except Exception as e:
        print(f"Face recognition error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500


# 🔥🔥🔥 NEW: SOS ALERT API (FIX) 🔥🔥🔥
@app.route("/sendAlert", methods=["POST"])
def send_alert():
    """Receive SOS alert from student"""
    try:
        data = request.json
        
        student_id = data.get("student_id", "Unknown")
        bus_id = data.get("bus_id", "Unknown")
        latitude = data.get("latitude", 0)
        longitude = data.get("longitude", 0)
        location_name = data.get("location_name", "Unknown")
        
        current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        print("🚨 SOS ALERT RECEIVED!")
        print(f"   Student: {student_id}")
        print(f"   Bus: {bus_id}")
        print(f"   Location: {location_name}")
        print(f"   Coordinates: {latitude}, {longitude}")
        print(f"   Time: {current_time}")
        
        # Save to database
        cursor.execute("""
            INSERT INTO sos_alerts (student_id, bus_id, latitude, longitude, location_name, timestamp, status)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (student_id, bus_id, latitude, longitude, location_name, current_time, "active"))
        conn.commit()
        
        return jsonify({
            "status": "success",
            "message": "Alert received and forwarded to driver and admin",
            "alert_id": cursor.lastrowid
        })
        
    except Exception as e:
        print(f"SOS alert error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500


# 🔥 NEW: GET ACTIVE SOS ALERTS
@app.route("/getSOSAlerts")
def get_sos_alerts():
    """Get all active SOS alerts"""
    try:
        cursor.execute("""
            SELECT * FROM sos_alerts 
            WHERE status = 'active'
            ORDER BY timestamp DESC
        """)
        
        rows = cursor.fetchall()
        alerts = []
        
        for row in rows:
            alerts.append({
                "id": row[0],
                "student_id": row[1],
                "bus_id": row[2],
                "latitude": row[3],
                "longitude": row[4],
                "location_name": row[5],
                "timestamp": row[6],
                "status": row[7]
            })
        
        return jsonify({"alerts": alerts, "count": len(alerts)})
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# 🔥 NEW: RESOLVE SOS ALERT
@app.route("/resolveSOSAlert", methods=["POST"])
def resolve_sos_alert():
    """Resolve an SOS alert"""
    try:
        data = request.json
        alert_id = data["alert_id"]
        
        cursor.execute("""
            UPDATE sos_alerts 
            SET status = 'resolved' 
            WHERE id = ?
        """, (alert_id,))
        conn.commit()
        
        return jsonify({
            "status": "success",
            "message": f"Alert {alert_id} resolved"
        })
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# 🔥 NEW: GET ALL ANOMALIES
@app.route("/getAnomalies")
def get_anomalies():
    """Get all active anomalies"""
    anomalies_list = []
    for bus_id, anomaly_data in bus_anomalies.items():
        anomalies_list.append({
            "bus_id": bus_id,
            "anomaly_type": anomaly_data["anomaly"],
            "latitude": anomaly_data["lat"],
            "longitude": anomaly_data["lon"],
            "speed": anomaly_data["speed"],
            "timestamp": anomaly_data["time"]
        })
    return jsonify({
        "anomalies": anomalies_list,
        "count": len(anomalies_list)
    })


# 🔥 NEW: GET ANOMALY HISTORY
@app.route("/getAnomalyHistory")
def get_anomaly_history():
    """Get historical anomaly logs"""
    try:
        cursor.execute("""
            SELECT * FROM anomaly_logs 
            ORDER BY timestamp DESC 
            LIMIT 100
        """)
        
        rows = cursor.fetchall()
        history = []
        
        for row in rows:
            history.append({
                "id": row[0],
                "bus_id": row[1],
                "anomaly_type": row[2],
                "latitude": row[3],
                "longitude": row[4],
                "speed": row[5],
                "timestamp": row[6],
                "status": row[7]
            })
        
        return jsonify({
            "history": history,
            "count": len(history)
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# 🔥 NEW: RESOLVE ANOMALY (Admin)
@app.route("/resolveAnomaly", methods=["POST"])
def resolve_anomaly():
    """Resolve an active anomaly"""
    data = request.json
    bus_id = data["bus_id"]
    
    if bus_id in bus_anomalies:
        del bus_anomalies[bus_id]
        
        # Update database
        try:
            cursor.execute("""
                UPDATE anomaly_logs 
                SET status = 'resolved' 
                WHERE bus_id = ? AND status = 'active'
            """, (bus_id,))
            conn.commit()
        except Exception as e:
            print(f"Error updating anomaly: {e}")
        
        return jsonify({
            "status": "success",
            "message": f"Anomaly resolved for bus {bus_id}"
        })
    
    return jsonify({
        "status": "error",
        "message": "No active anomaly found for this bus"
    })


# 🔥 NEW: GET GEO-FENCING ALERTS
@app.route("/getGeoAlerts")
def get_geo_alerts():
    """Get all geo-fencing alerts"""
    return jsonify(geo_alerts)


# 🔥 NEW: GET DRIVER BEHAVIOR
@app.route("/getDriverBehavior")
def get_driver_behavior():
    """Get driver behavior data"""
    return jsonify(driver_behavior)


# 🔥 NEW: ANALYTICS API
@app.route("/analytics")
def analytics():
    """Get analytics data"""
    avg_speed = sum(speed_records) / len(speed_records) if speed_records else 0
    
    delay_count = delay_records.count("Bus Delayed") + delay_records.count("Slight Delay")
    total = len(delay_records) if delay_records else 1
    delay_rate = (delay_count / total) * 100
    
    return jsonify({
        "average_speed": round(avg_speed, 2),
        "delay_rate": round(delay_rate, 2),
        "total_records": len(speed_records),
        "current_active_buses": len(bus_locations),
        "anomaly_count": len(bus_anomalies)
    })


# 🔥 NEW: FACE ATTENDANCE API (Alternative endpoint)
@app.route("/faceAttendance", methods=["POST"])
def face_attendance_api():
    """Mark attendance using face recognition (alternative endpoint)"""
    
    if not FACE_RECOGNITION_AVAILABLE:
        return jsonify({
            "status": "failed",
            "message": "Face recognition library not installed"
        })
    
    if 'image' not in request.files:
        return jsonify({"status": "failed", "message": "No image uploaded"})
    
    file = request.files['image']
    bus_id = request.form.get("bus_id", "Unknown")
    
    try:
        # Convert image to numpy array
        image = face_recognition.load_image_file(file)
        
        face_locations = face_recognition.face_locations(image)
        face_encodings = face_recognition.face_encodings(image, face_locations)
        
        if not face_encodings:
            return jsonify({"status": "failed", "message": "No face detected in image"})
        
        for face_encoding in face_encodings:
            if not known_face_encodings:
                return jsonify({"status": "failed", "message": "No student faces loaded. Add images to faces/ folder"})
            
            matches = face_recognition.compare_faces(known_face_encodings, face_encoding)
            face_distances = face_recognition.face_distance(known_face_encodings, face_encoding)
            
            best_match_index = np.argmin(face_distances)
            
            if matches[best_match_index]:
                student_id = known_face_ids[best_match_index]
                current_time = datetime.now().isoformat()
                
                record = {
                    "student_id": student_id,
                    "bus_id": bus_id,
                    "time": current_time,
                    "status": "Present"
                }
                
                face_attendance.append(record)
                
                # Save to database
                cursor.execute("""
                    INSERT INTO face_attendance (student_id, bus_id, time, status)
                    VALUES (?, ?, ?, ?)
                """, (student_id, bus_id, current_time, "Present"))
                conn.commit()
                
                return jsonify({
                    "status": "success",
                    "message": f"Attendance marked for {student_id}",
                    "data": record
                })
        
        return jsonify({
            "status": "failed",
            "message": "Face not recognized. Please register your face first."
        })
        
    except Exception as e:
        return jsonify({"status": "failed", "message": f"Error: {str(e)}"})


# 🔥 NEW: GET FACE ATTENDANCE HISTORY
@app.route("/getFaceAttendance")
def get_face_attendance():
    """Get face attendance history"""
    return jsonify(face_attendance)


# 🔥 NEW: MARK ATTENDANCE API
@app.route("/markAttendance", methods=["POST"])
def mark_attendance():
    """Mark attendance for students"""
    try:
        data = request.json
        bus_id = data.get("bus_id")
        records = data.get("records", [])
        
        current_time = datetime.now().isoformat()
        
        for record in records:
            reg_no = record.get("reg_no")
            present = record.get("present")
            
            if present:
                cursor.execute("""
                    INSERT INTO face_attendance (student_id, bus_id, time, status)
                    VALUES (?, ?, ?, ?)
                """, (reg_no, bus_id, current_time, "Present"))
                conn.commit()
        
        return jsonify({
            "status": "success",
            "message": f"Attendance marked for {len(records)} students"
        })
        
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


# 🔥 NEW: VOICE ASSISTANT API
@app.route("/voiceCommand", methods=["POST"])
def voice_command():
    """Process voice commands"""
    data = request.json
    command = data.get("command", "").lower()
    bus_id = data.get("bus_id")
    
    # 🎤 BUS LOCATION
    if "location" in command or "where" in command:
        if bus_id and bus_id in bus_locations:
            loc = bus_locations[bus_id]
            return jsonify({
                "response": f"Bus {bus_id} is at latitude {loc['latitude']:.6f} and longitude {loc['longitude']:.6f}"
            })
        else:
            return jsonify({"response": "Bus location not available"})
    
    # 🚨 EMERGENCY
    elif "emergency" in command or "help" in command:
        return jsonify({
            "response": f"Emergency alert sent for bus {bus_id}"
        })
    
    # 🚍 BUS STATUS
    elif "status" in command:
        if bus_id and bus_id in bus_locations:
            if bus_id in bus_anomalies:
                return jsonify({
                    "response": f"Bus {bus_id} has an anomaly: {bus_anomalies[bus_id]['anomaly']}"
                })
            else:
                return jsonify({
                    "response": f"Bus {bus_id} is running normally"
                })
        else:
            return jsonify({"response": "Bus status unknown"})
    
    # 📊 ANALYTICS
    elif "analytics" in command or "average" in command or "speed" in command:
        avg_speed = sum(speed_records) / len(speed_records) if speed_records else 0
        return jsonify({
            "response": f"Average bus speed is {round(avg_speed,2)} kilometers per hour. There are {len(bus_anomalies)} active anomalies."
        })
    
    # 🔥 ANOMALIES
    elif "anomaly" in command or "problem" in command:
        if bus_anomalies:
            return jsonify({
                "response": f"There are {len(bus_anomalies)} active anomalies. {list(bus_anomalies.keys())} buses have issues."
            })
        else:
            return jsonify({"response": "No active anomalies detected. All buses are running normally."})
    
    # 🚌 BUS COUNT
    elif "bus count" in command or "how many buses" in command:
        return jsonify({
            "response": f"There are {len(bus_locations)} buses currently active and tracking."
        })
    
    # ❌ UNKNOWN
    else:
        return jsonify({
            "response": "Sorry, I didn't understand. Try saying: bus location, bus status, analytics, anomalies, emergency, or bus count."
        })


# ---------------- EMERGENCY ALERT ----------------

@app.route("/emergency", methods=["POST"])
def emergency():

    data = request.json
    print("Emergency from bus:", data["bus_id"])

    return {"status":"alert sent"}


# ---------------- BUS ENTRY / EXIT LOG ----------------

@app.route("/logBus", methods=["POST"])
def log_bus():

    data = request.json

    bus_id = data["bus_id"]
    entry = data["entry_time"]
    exit_time = data["exit_time"]
    arrival = data["arrival_time"]

    cursor.execute("""
        INSERT INTO bus_log(bus_id,entry_time,exit_time,arrival_time)
        VALUES(?,?,?,?)
    """,(bus_id,entry,exit_time,arrival))

    conn.commit()

    return jsonify({"status":"saved"})


# ---------------- GET LOGS ----------------

@app.route("/getLogs")
def get_logs():

    cursor.execute("SELECT * FROM bus_log")

    rows = cursor.fetchall()

    logs = []

    for r in rows:

        logs.append({
            "bus_id": r[1],
            "entry_time": r[2],
            "exit_time": r[3],
            "arrival_time": r[4]
        })

    return jsonify(logs)


# ---------------- DOWNLOAD REPORT ----------------

@app.route("/downloadReport")
def download_report():

    cursor.execute("SELECT * FROM bus_log")
    rows = cursor.fetchall()

    filename = "bus_report.csv"

    with open(filename,"w",newline="") as file:

        writer = csv.writer(file)

        writer.writerow(["Bus ID","Entry Time","Exit Time","Arrival Time"])

        for r in rows:
            writer.writerow([r[1],r[2],r[3],r[4]])

    return send_file(filename,as_attachment=True)


# ---------------- DASHBOARD ----------------

@app.route("/dashboard")
def dashboard():

    active_buses = len(bus_locations)

    delayed_buses = 0

    total_students = sum(bus_boarded.values()) if bus_boarded else 0

    emergency_count = 0
    
    # 🔥 Count anomalies for dashboard
    anomaly_count = len(bus_anomalies)
    
    # Get SOS alert count
    try:
        cursor.execute("SELECT COUNT(*) FROM sos_alerts WHERE status = 'active'")
        sos_count = cursor.fetchone()[0]
    except:
        sos_count = 0
    
    # Calculate average speed
    avg_speed = sum(speed_records) / len(speed_records) if speed_records else 0

    return jsonify({
        "active_buses": active_buses,
        "delayed_buses": delayed_buses,
        "students": total_students,
        "emergency": emergency_count,
        "anomalies": anomaly_count,
        "sos_alerts": sos_count,
        "average_speed": round(avg_speed, 2)
    })


# ---------------- RUN SERVER ----------------

if __name__ == "__main__":
    print("\n" + "="*50)
    print("🚀 TRANSPORT SYSTEM SERVER STARTED")
    print("="*50)
    print(f"📊 Face Recognition: {'✅ Available' if FACE_RECOGNITION_AVAILABLE else '❌ Not installed'}")
    print(f"📁 Faces folder: {'faces/'}")
    print(f"📊 Analytics tracking: Enabled")
    print(f"🔔 Geo-fencing: Enabled with {len(BUS_STOPS)} stops")
    print(f"🚨 Anomaly detection: Active")
    print(f"👨‍✈️ Driver behavior: Monitoring")
    print(f"🎤 Voice assistant: Ready")
    print(f"🚨 SOS Alerts: Active")
    print("="*50)
    print("\n✅ Available Endpoints:")
    print("   / - Home")
    print("   /getBuses - List all buses")
    print("   /studentLogin - Student login")
    print("   /getStudentsByBus/<bus_id> - Get students in a bus")
    print("   /recognizeFace - Face recognition")
    print("   /sendAlert - SOS alert")
    print("   /sendLocation - Update bus location")
    print("   /getLocation/<bus_id> - Get bus location")
    print("   /getAnomalies - Get active anomalies")
    print("   /getSOSAlerts - Get active SOS alerts")
    print("   /analytics - System analytics")
    print("   /dashboard - Dashboard data")
    print("="*50 + "\n")
    app.run(host="0.0.0.0", port=5000, debug=True)
