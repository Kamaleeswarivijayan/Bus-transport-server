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
import cv2

app = Flask(__name__)

EXCEL_FILE = "transport_data.xlsx"

COLLEGE_LAT = 13.013396
COLLEGE_LON = 79.132097
GATE_RADIUS = 0.5  # 500 meters
OVERSPEED_LIMIT = 60  # km/h

# ---------------- DATABASE ----------------

conn = sqlite3.connect("transport.db", check_same_thread=False)
cursor = conn.cursor()

# Bus log table
cursor.execute("""
CREATE TABLE IF NOT EXISTS bus_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bus_id TEXT,
    entry_time TEXT,
    exit_time TEXT,
    arrival_time TEXT
)
""")

# Anomaly logs table
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

# Face attendance table
cursor.execute("""
CREATE TABLE IF NOT EXISTS face_attendance (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id TEXT,
    bus_id TEXT,
    time TEXT,
    status TEXT,
    date TEXT
)
""")

# SOS alerts table
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

# Route history table
cursor.execute("""
CREATE TABLE IF NOT EXISTS route_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bus_id TEXT,
    latitude REAL,
    longitude REAL,
    speed REAL,
    timestamp TEXT,
    date TEXT
)
""")

# Emergency alerts table
cursor.execute("""
CREATE TABLE IF NOT EXISTS emergency_alerts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    student_reg TEXT,
    bus_id TEXT,
    latitude REAL,
    longitude REAL,
    location_name TEXT,
    timestamp TEXT,
    status TEXT DEFAULT 'active',
    acknowledged_by_driver INTEGER DEFAULT 0,
    acknowledged_by_admin INTEGER DEFAULT 0
)
""")

# Attendance table
cursor.execute("""
CREATE TABLE IF NOT EXISTS attendance (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id TEXT,
    bus_id TEXT,
    date TEXT,
    status TEXT,
    time TEXT
)
""")

# Bus stops table
cursor.execute("""
CREATE TABLE IF NOT EXISTS bus_stops (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bus_id TEXT,
    stop_name TEXT,
    latitude REAL,
    longitude REAL,
    sequence INTEGER
)
""")

conn.commit()

# ---------------- LIGHTWEIGHT FACE RECOGNITION ----------------

KNOWN_FACES_DIR = "faces"
known_faces = {}

def load_known_faces():
    """Load all student face images using OpenCV (lightweight)"""
    print("\n" + "="*50)
    print("📸 LOADING FACES (LIGHTWEIGHT MODE)")
    print("="*50)
    
    if not os.path.exists(KNOWN_FACES_DIR):
        os.makedirs(KNOWN_FACES_DIR)
        print(f"✅ Created {KNOWN_FACES_DIR} folder")
        print("   Add student images as 'register_number.jpg'")
        return
    
    count = 0
    for file in os.listdir(KNOWN_FACES_DIR):
        if file.endswith((".jpg", ".jpeg", ".png")):
            path = os.path.join(KNOWN_FACES_DIR, file)
            img = cv2.imread(path)
            
            if img is None:
                print(f"⚠️ Could not read {file}")
                continue
            
            # Convert to grayscale
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            student_id = os.path.splitext(file)[0]
            
            known_faces[student_id] = gray
            count += 1
            print(f"✅ Loaded: {student_id}")
    
    print(f"\n✅ Total faces loaded: {count}")
    print("="*50 + "\n")

# Load faces on startup
load_known_faces()

# ---------------- GLOBAL VARIABLES ----------------

bus_locations = {}
bus_history = {}
bus_anomalies = {}
anomaly_alerted = {}
bus_boarded = {}
speed_records = []
delay_records = []

# ---------------- HELPER FUNCTIONS ----------------

def calculate_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two coordinates in km"""
    if lat1 == 0 or lon1 == 0 or lat2 == 0 or lon2 == 0:
        return 999
    R = 6371
    dLat = math.radians(lat2 - lat1)
    dLon = math.radians(lon2 - lon1)
    a = (math.sin(dLat/2) * math.sin(dLat/2) +
         math.cos(math.radians(lat1)) *
         math.cos(math.radians(lat2)) *
         math.sin(dLon/2) * math.sin(dLon/2))
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

def calculate_eta(distance_km, speed_kmh):
    """Calculate ETA in minutes"""
    if speed_kmh == 0:
        return "Unknown"
    time_hr = distance_km / speed_kmh
    mins = int(time_hr * 60)
    if mins < 1:
        return "< 1 min"
    elif mins > 60:
        hours = mins // 60
        minutes = mins % 60
        return f"{hours}h {minutes}m"
    return f"{mins} mins"

def predict_delay(distance_km, speed_kmph):
    """Predict delay status"""
    if speed_kmph == 0:
        return "Bus Stopped"
    eta = (distance_km / speed_kmph) * 60
    if eta > 10:
        return "Delayed"
    elif eta > 5:
        return "Slight Delay"
    else:
        return "On Time"

def detect_anomaly(bus_id, lat, lon, speed):
    """Detect anomalies like overspeeding, route deviation"""
    anomaly = None
    current_time = datetime.now()
    
    if speed > OVERSPEED_LIMIT:
        anomaly = "Overspeeding"
        print(f"⚠️ ANOMALY: Bus {bus_id} is overspeeding at {speed} km/h")
    
    if lat < 12.9 or lat > 13.1 or lon < 79.0 or lon > 79.3:
        anomaly = "Route Deviation"
        print(f"⚠️ ANOMALY: Bus {bus_id} deviated from route at ({lat}, {lon})")
    
    bus_history[bus_id] = {
        "lat": lat,
        "lon": lon,
        "speed": speed,
        "time": current_time
    }
    
    if anomaly:
        if bus_id not in anomaly_alerted or anomaly_alerted[bus_id] != anomaly:
            bus_anomalies[bus_id] = {
                "anomaly": anomaly,
                "lat": lat,
                "lon": lon,
                "speed": speed,
                "time": current_time.strftime("%Y-%m-%d %H:%M:%S")
            }
            anomaly_alerted[bus_id] = anomaly
            
            try:
                cursor.execute("""
                    INSERT INTO anomaly_logs (bus_id, anomaly_type, latitude, longitude, speed, timestamp, status)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (bus_id, anomaly, lat, lon, speed, current_time.strftime("%Y-%m-%d %H:%M:%S"), "active"))
                conn.commit()
            except Exception as e:
                print(f"Error saving anomaly: {e}")
    else:
        if bus_id in bus_anomalies:
            try:
                cursor.execute("""
                    UPDATE anomaly_logs 
                    SET status = 'resolved' 
                    WHERE bus_id = ? AND status = 'active'
                """, (bus_id,))
                conn.commit()
            except Exception as e:
                print(f"Error updating anomaly: {e}")
            del bus_anomalies[bus_id]
            if bus_id in anomaly_alerted:
                del anomaly_alerted[bus_id]
    
    return anomaly

def check_geofence(bus_id, lat, lon):
    """Check if bus is near college or stops"""
    alerts = []
    
    distance_to_college = calculate_distance(lat, lon, COLLEGE_LAT, COLLEGE_LON)
    if distance_to_college < GATE_RADIUS:
        alerts.append(f"Bus {bus_id} is near college campus")
    
    try:
        df = pd.read_excel(EXCEL_FILE, sheet_name="Stops")
        df['bus_id'] = df['bus_id'].astype(str)
        stops = df[df["bus_id"] == str(bus_id)]
        
        for _, stop in stops.iterrows():
            dist = calculate_distance(lat, lon, stop["latitude"], stop["longitude"])
            if dist < 0.3:
                alerts.append(f"Bus {bus_id} reached {stop['stop_name']}")
    except Exception as e:
        print(f"Error checking stops: {e}")
    
    return alerts

# ---------------- ROUTES ----------------

@app.route("/")
def home():
    return jsonify({
        "status": "running",
        "message": "College Transport System API",
        "features": [
            "Real-time bus tracking",
            "Face recognition attendance",
            "Emergency alerts",
            "Anomaly detection",
            "Geo-fencing",
            "Voice assistant",
            "Route history tracking",
            "ETA calculation"
        ]
    })

@app.route("/test")
def test():
    return "Server Running"

# ---------------- BUS MANAGEMENT ----------------

@app.route("/getBuses")
def get_buses():
    """Get all buses from Excel"""
    try:
        df = pd.read_excel(EXCEL_FILE, sheet_name="Buses")
        buses = df["bus_id"].astype(str).tolist()
        print(f"✅ Found buses: {buses}")
        return jsonify(buses)
    except Exception as e:
        print(f"Error getting buses: {e}")
        return jsonify(["BUS001", "BUS002", "BUS003"])

@app.route("/getStops/<bus_id>")
def get_stops(bus_id):
    """Get stops for a specific bus from Excel"""
    try:
        print(f"📡 Fetching stops for bus: {bus_id}")
        
        df = pd.read_excel(EXCEL_FILE, sheet_name="Stops")
        df['bus_id'] = df['bus_id'].astype(str)
        bus_id_str = str(bus_id)
        
        bus_stops = df[df["bus_id"] == bus_id_str]
        
        print(f"📊 Found {len(bus_stops)} stops in Excel for bus {bus_id}")
        print(f"📊 Available bus IDs in Excel: {df['bus_id'].unique().tolist()}")
        
        stops = bus_stops.to_dict(orient="records")
        
        if "sequence" in df.columns:
            stops = sorted(stops, key=lambda x: x.get("sequence", 999))
        
        return jsonify(stops)
        
    except Exception as e:
        print(f"❌ Error loading stops: {e}")
        return jsonify([]), 500

# ---------------- LOCATION TRACKING ----------------

@app.route("/sendLocation", methods=["POST"])
def send_location():
    """Receive location from driver and save to database"""
    try:
        data = request.json
        bus_id = data.get("bus_id")
        latitude = data.get("latitude", 0)
        longitude = data.get("longitude", 0)
        speed = data.get("speed", 0)
        
        if bus_id is None:
            return jsonify({"error": "bus_id required"}), 400
        
        bus_locations[bus_id] = {
            "latitude": latitude,
            "longitude": longitude,
            "speed": speed,
            "last_update": datetime.now().isoformat()
        }
        
        anomaly = detect_anomaly(bus_id, latitude, longitude, speed)
        geo_alerts = check_geofence(bus_id, latitude, longitude)
        
        current_time = datetime.now()
        cursor.execute("""
            INSERT INTO route_history (bus_id, latitude, longitude, speed, timestamp, date)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (
            bus_id,
            latitude,
            longitude,
            speed,
            current_time.strftime("%Y-%m-%d %H:%M:%S"),
            current_time.strftime("%Y-%m-%d")
        ))
        conn.commit()
        
        return jsonify({
            "status": "ok",
            "anomaly": anomaly,
            "geo_alerts": geo_alerts,
            "speed": round(speed, 2)
        })
        
    except Exception as e:
        print(f"Error sending location: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/getLocation/<bus_id>")
def get_location(bus_id):
    """Get current location of a bus"""
    try:
        if bus_id in bus_locations:
            loc = bus_locations[bus_id]
            distance = calculate_distance(loc["latitude"], loc["longitude"], COLLEGE_LAT, COLLEGE_LON)
            delay_status = predict_delay(distance, loc.get("speed", 30))
            eta = calculate_eta(distance, loc.get("speed", 30))
            
            response = {
                "latitude": loc["latitude"],
                "longitude": loc["longitude"],
                "speed": loc.get("speed", 0),
                "delay": delay_status,
                "eta": eta,
                "distance_to_college": round(distance, 2)
            }
            
            if bus_id in bus_anomalies:
                response["anomaly"] = bus_anomalies[bus_id]["anomaly"]
                response["anomaly_detected"] = True
            
            return jsonify(response)
        
        return jsonify({
            "latitude": 0,
            "longitude": 0,
            "speed": 0,
            "delay": "Unknown",
            "eta": "Unknown",
            "distance_to_college": 0
        })
        
    except Exception as e:
        print(f"Error getting location: {e}")
        return jsonify({"error": str(e)}), 500

# ---------------- STUDENT & PARENT ----------------

@app.route("/studentLogin", methods=["POST"])
def student_login():
    try:
        data = request.json
        reg_no = data.get("reg_no")
        
        if not reg_no:
            return jsonify({"status": "error", "message": "Register number required"})
        
        df = pd.read_excel(EXCEL_FILE, sheet_name="Students")
        df['reg_no'] = df['reg_no'].astype(str)
        student = df[df["reg_no"] == str(reg_no)]
        
        if student.empty:
            return jsonify({"status": "error", "message": "Student not found"})
        
        bus_id = str(student.iloc[0]["bus_id"])
        return jsonify({"status": "success", "bus_id": bus_id})
        
    except Exception as e:
        print(f"Error in student login: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route("/parentLogin", methods=["POST"])
def parent_login():
    try:
        data = request.json
        reg_no = data.get("reg_no")
        
        if not reg_no:
            return jsonify({"status": "error", "message": "Register number required"})
        
        df = pd.read_excel(EXCEL_FILE, sheet_name="Students")
        df['reg_no'] = df['reg_no'].astype(str)
        student = df[df["reg_no"] == str(reg_no)]
        
        if student.empty:
            return jsonify({"status": "error", "message": "Student not found"})
        
        bus_id = str(student.iloc[0]["bus_id"])
        student_name = student.iloc[0]["name"]
        
        return jsonify({
            "status": "success",
            "bus_id": bus_id,
            "student_id": reg_no,
            "student_name": student_name
        })
        
    except Exception as e:
        print(f"Error in parent login: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route("/parentData/<student_id>")
def parent_data(student_id):
    """Get all data for parent view"""
    try:
        df = pd.read_excel(EXCEL_FILE, sheet_name="Students")
        df['reg_no'] = df['reg_no'].astype(str)
        student = df[df["reg_no"] == str(student_id)]
        
        if student.empty:
            return jsonify({"error": "Student not found"}), 404
        
        bus_id = str(student.iloc[0]["bus_id"])
        student_name = student.iloc[0]["name"]
        
        response = {
            "bus_id": bus_id,
            "student_name": student_name,
            "latitude": 0,
            "longitude": 0,
            "speed": 0,
            "delay": "Unknown",
            "eta": "Unknown",
            "attendance": "Not Marked",
            "active_alert": None,
            "stops": []
        }
        
        if bus_id in bus_locations:
            loc = bus_locations[bus_id]
            response["latitude"] = loc["latitude"]
            response["longitude"] = loc["longitude"]
            response["speed"] = loc.get("speed", 0)
            distance = calculate_distance(loc["latitude"], loc["longitude"], COLLEGE_LAT, COLLEGE_LON)
            response["delay"] = predict_delay(distance, loc.get("speed", 30))
            response["eta"] = calculate_eta(distance, loc.get("speed", 30))
        
        today = datetime.now().strftime("%Y-%m-%d")
        cursor.execute("""
            SELECT status, time FROM attendance 
            WHERE student_id = ? AND date = ?
            ORDER BY id DESC LIMIT 1
        """, (student_id, today))
        
        row = cursor.fetchone()
        if row:
            response["attendance"] = row[0]
            response["attendance_time"] = row[1]
            response["attendance_date"] = today
        
        cursor.execute("""
            SELECT * FROM emergency_alerts 
            WHERE bus_id = ? AND status = 'active'
            ORDER BY id DESC LIMIT 1
        """, (bus_id,))
        
        row = cursor.fetchone()
        if row:
            response["active_alert"] = {
                "student": row[1],
                "location": row[5],
                "time": row[6]
            }
        
        # Get stops from Excel
        try:
            stops_df = pd.read_excel(EXCEL_FILE, sheet_name="Stops")
            stops_df['bus_id'] = stops_df['bus_id'].astype(str)
            stops = stops_df[stops_df["bus_id"] == bus_id]
            
            for _, stop in stops.iterrows():
                eta = "Unknown"
                if bus_id in bus_locations:
                    loc = bus_locations[bus_id]
                    dist = calculate_distance(loc["latitude"], loc["longitude"], 
                                              stop["latitude"], stop["longitude"])
                    eta = calculate_eta(dist, loc.get("speed", 30))
                
                response["stops"].append({
                    "name": stop["stop_name"],
                    "lat": stop["latitude"],
                    "lon": stop["longitude"],
                    "eta": eta
                })
        except Exception as e:
            print(f"Error getting stops: {e}")
        
        return jsonify(response)
        
    except Exception as e:
        print(f"Error in parent data: {e}")
        return jsonify({"error": str(e)}), 500

# ---------------- STUDENTS BY BUS ----------------

@app.route("/getStudentsByBus/<bus_id>")
def get_students_by_bus(bus_id):
    """Get all students assigned to a specific bus"""
    try:
        print(f"📚 Fetching students for bus: {bus_id}")
        
        df = pd.read_excel(EXCEL_FILE, sheet_name="Students")
        df['bus_id'] = df['bus_id'].astype(str)
        df['reg_no'] = df['reg_no'].astype(str)
        
        students = df[df["bus_id"] == str(bus_id)]
        
        print(f"✅ Found {len(students)} students for bus {bus_id}")
        
        result = students[["reg_no", "name"]].to_dict(orient="records")
        
        if not result:
            print(f"⚠️ No students found for bus {bus_id}")
            print(f"💡 Available bus IDs in Excel: {df['bus_id'].unique().tolist()}")
        
        return jsonify(result)
        
    except Exception as e:
        print(f"❌ Error getting students: {e}")
        return jsonify([]), 500

# ---------------- ATTENDANCE ----------------

@app.route("/markAttendance", methods=["POST"])
def mark_attendance():
    """Mark attendance for students"""
    try:
        data = request.json
        bus_id = data.get("bus_id")
        records = data.get("records", [])
        date = datetime.now().strftime("%Y-%m-%d")
        current_time = datetime.now().strftime("%H:%M:%S")
        
        marked_count = 0
        
        for record in records:
            reg_no = record.get("reg_no")
            present = record.get("present")
            
            if present:
                cursor.execute("""
                    INSERT INTO attendance (student_id, bus_id, date, status, time)
                    VALUES (?, ?, ?, ?, ?)
                """, (reg_no, bus_id, date, "Present", current_time))
                marked_count += 1
                print(f"✅ Marked attendance for {reg_no}")
        
        conn.commit()
        
        return jsonify({
            "status": "success", 
            "message": f"Attendance marked for {marked_count} students",
            "marked": marked_count
        })
        
    except Exception as e:
        print(f"Error marking attendance: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/getAttendance/<bus_id>")
def get_attendance(bus_id):
    """Get attendance records for a bus on a specific date"""
    try:
        date_filter = request.args.get("date", datetime.now().strftime("%Y-%m-%d"))
        
        cursor.execute("""
            SELECT student_id, status, time
            FROM attendance
            WHERE bus_id = ? AND date = ?
            ORDER BY id DESC
        """, (bus_id, date_filter))
        
        rows = cursor.fetchall()
        
        df = pd.read_excel(EXCEL_FILE, sheet_name="Students")
        df['bus_id'] = df['bus_id'].astype(str)
        df['reg_no'] = df['reg_no'].astype(str)
        bus_students = df[df["bus_id"] == str(bus_id)]
        
        records = []
        for row in rows:
            student = bus_students[bus_students["reg_no"] == row[0]]
            name = student.iloc[0]["name"] if not student.empty else row[0]
            
            records.append({
                "reg_no": row[0],
                "name": name,
                "present": row[1] == "Present",
                "time": row[2]
            })
        
        return jsonify({"records": records})
        
    except Exception as e:
        print(f"Error getting attendance: {e}")
        return jsonify({"records": []}), 500

# ---------------- EMERGENCY ALERTS ----------------

@app.route("/sendEmergency", methods=["POST"])
def send_emergency():
    """Send emergency alert from student"""
    try:
        data = request.json
        
        student_reg = data.get("student_reg")
        bus_id = data.get("bus_id")
        latitude = data.get("latitude", 0)
        longitude = data.get("longitude", 0)
        location_name = data.get("location_name", "Unknown")
        
        current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        print("\n" + "="*50)
        print("🚨 EMERGENCY ALERT!")
        print("="*50)
        print(f"   👤 Student: {student_reg}")
        print(f"   🚍 Bus: {bus_id}")
        print(f"   📍 Location: {location_name}")
        print(f"   ⏰ Time: {current_time}")
        print("="*50 + "\n")
        
        cursor.execute("""
            INSERT INTO emergency_alerts 
            (student_reg, bus_id, latitude, longitude, location_name, timestamp, status)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (student_reg, bus_id, latitude, longitude, location_name, current_time, "active"))
        conn.commit()
        
        return jsonify({
            "status": "success",
            "message": "Emergency alert sent to driver and admin",
            "alert_id": cursor.lastrowid
        })
        
    except Exception as e:
        print(f"Error sending emergency: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/getDriverAlerts/<bus_id>")
def get_driver_alerts(bus_id):
    """Get active alerts for a specific bus (driver view)"""
    try:
        cursor.execute("""
            SELECT * FROM emergency_alerts 
            WHERE bus_id = ? AND status = 'active'
            ORDER BY timestamp DESC
        """, (bus_id,))
        
        rows = cursor.fetchall()
        alerts = []
        
        for row in rows:
            alerts.append({
                "id": row[0],
                "student_reg": row[1],
                "bus_id": row[2],
                "latitude": row[3],
                "longitude": row[4],
                "location_name": row[5],
                "alert_time": row[6],
                "driver_acknowledged": row[8] == 1
            })
        
        return jsonify({"alerts": alerts})
        
    except Exception as e:
        print(f"Error getting driver alerts: {e}")
        return jsonify({"alerts": []}), 500

@app.route("/getAdminAlerts")
def get_admin_alerts():
    """Get all active alerts (admin view)"""
    try:
        cursor.execute("""
            SELECT * FROM emergency_alerts 
            WHERE status = 'active'
            ORDER BY timestamp DESC
        """)
        
        rows = cursor.fetchall()
        alerts = []
        
        for row in rows:
            alerts.append({
                "id": row[0],
                "student_reg": row[1],
                "bus_id": row[2],
                "latitude": row[3],
                "longitude": row[4],
                "location_name": row[5],
                "alert_time": row[6],
                "admin_acknowledged": row[9] == 1
            })
        
        return jsonify({"alerts": alerts})
        
    except Exception as e:
        print(f"Error getting admin alerts: {e}")
        return jsonify({"alerts": []}), 500

@app.route("/getAlertHistory")
def get_alert_history():
    """Get resolved alerts history"""
    try:
        cursor.execute("""
            SELECT * FROM emergency_alerts 
            WHERE status = 'resolved'
            ORDER BY timestamp DESC
            LIMIT 50
        """)
        
        rows = cursor.fetchall()
        alerts = []
        
        for row in rows:
            alerts.append({
                "id": row[0],
                "student_reg": row[1],
                "bus_id": row[2],
                "location_name": row[5],
                "alert_time": row[6]
            })
        
        return jsonify({"alerts": alerts})
        
    except Exception as e:
        print(f"Error getting alert history: {e}")
        return jsonify({"alerts": []}), 500

@app.route("/acknowledgeAlert", methods=["POST"])
def acknowledge_alert():
    """Acknowledge an emergency alert"""
    try:
        data = request.json
        alert_id = data.get("alert_id")
        user_type = data.get("user_type")
        
        if user_type == "driver":
            cursor.execute("""
                UPDATE emergency_alerts 
                SET acknowledged_by_driver = 1 
                WHERE id = ?
            """, (alert_id,))
        elif user_type == "admin":
            cursor.execute("""
                UPDATE emergency_alerts 
                SET acknowledged_by_admin = 1 
                WHERE id = ?
            """, (alert_id,))
        
        conn.commit()
        return jsonify({"status": "success"})
        
    except Exception as e:
        print(f"Error acknowledging alert: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/resolveAlert", methods=["POST"])
def resolve_alert():
    """Resolve an emergency alert"""
    try:
        data = request.json
        alert_id = data.get("alert_id")
        
        cursor.execute("""
            UPDATE emergency_alerts 
            SET status = 'resolved' 
            WHERE id = ?
        """, (alert_id,))
        conn.commit()
        
        return jsonify({"status": "success"})
        
    except Exception as e:
        print(f"Error resolving alert: {e}")
        return jsonify({"error": str(e)}), 500

# ---------------- ROUTE HISTORY ----------------

@app.route("/getRouteHistory/<bus_id>")
def get_route_history(bus_id):
    """Get route history for a specific bus"""
    try:
        date_filter = request.args.get("date", None)
        
        if date_filter:
            cursor.execute("""
                SELECT latitude, longitude, speed, timestamp
                FROM route_history
                WHERE bus_id = ? AND date = ?
                ORDER BY timestamp ASC
            """, (bus_id, date_filter))
        else:
            cursor.execute("""
                SELECT latitude, longitude, speed, timestamp
                FROM route_history
                WHERE bus_id = ?
                ORDER BY timestamp DESC
                LIMIT 500
            """, (bus_id,))
        
        rows = cursor.fetchall()
        data = []
        for row in rows:
            data.append({
                "lat": row[0],
                "lon": row[1],
                "speed": row[2],
                "time": row[3]
            })
        
        return jsonify({
            "bus_id": bus_id,
            "points": data,
            "count": len(data)
        })
        
    except Exception as e:
        print(f"❌ Route history error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/getRoutes/<bus_id>")
def get_routes(bus_id):
    """Get routes grouped by date"""
    try:
        date_filter = request.args.get("date", datetime.now().strftime("%Y-%m-%d"))
        
        cursor.execute("""
            SELECT 
                MIN(timestamp) as start_time,
                MAX(timestamp) as end_time,
                COUNT(*) as point_count,
                AVG(speed) as avg_speed,
                MAX(speed) as max_speed
            FROM route_history
            WHERE bus_id = ? AND date = ?
        """, (bus_id, date_filter))
        
        row = cursor.fetchone()
        
        routes = []
        if row and row[0]:
            routes.append({
                "id": f"{bus_id}_{date_filter}",
                "start_time": row[0],
                "end_time": row[1],
                "point_count": row[2],
                "avg_speed": round(row[3], 2) if row[3] else 0,
                "max_speed": round(row[4], 2) if row[4] else 0
            })
        
        return jsonify({"routes": routes})
        
    except Exception as e:
        print(f"❌ Get routes error: {e}")
        return jsonify({"routes": []}), 500

@app.route("/downloadRoute/<route_id>")
def download_route(route_id):
    """Download route as CSV or GeoJSON"""
    try:
        format = request.args.get("format", "csv")
        
        parts = route_id.split("_")
        if len(parts) >= 2:
            bus_id = parts[0]
            date_filter = parts[1]
        else:
            bus_id = route_id
            date_filter = None
        
        if date_filter:
            cursor.execute("""
                SELECT latitude, longitude, speed, timestamp
                FROM route_history
                WHERE bus_id = ? AND date = ?
                ORDER BY timestamp ASC
            """, (bus_id, date_filter))
        else:
            cursor.execute("""
                SELECT latitude, longitude, speed, timestamp
                FROM route_history
                WHERE bus_id = ?
                ORDER BY timestamp ASC
            """, (bus_id,))
        
        rows = cursor.fetchall()
        
        if not rows:
            return jsonify({"error": "No route data found"}), 404
        
        filename = f"{bus_id}_route_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        
        if format == "csv":
            filename += ".csv"
            with open(filename, "w", newline="") as file:
                writer = csv.writer(file)
                writer.writerow(["Latitude", "Longitude", "Speed (km/h)", "Timestamp"])
                writer.writerows(rows)
        elif format == "geojson":
            filename += ".geojson"
            features = []
            for row in rows:
                features.append({
                    "type": "Feature",
                    "geometry": {
                        "type": "Point",
                        "coordinates": [row[1], row[0]]
                    },
                    "properties": {
                        "speed": row[2],
                        "timestamp": row[3]
                    }
                })
            
            geojson = {
                "type": "FeatureCollection",
                "features": features
            }
            
            import json
            with open(filename, "w") as file:
                json.dump(geojson, file)
        
        return send_file(filename, as_attachment=True, download_name=filename)
        
    except Exception as e:
        print(f"❌ Download route error: {e}")
        return jsonify({"error": str(e)}), 500

# ---------------- BUS LOGS ----------------

@app.route("/getLogs")
def get_logs():
    """Get bus logs"""
    try:
        cursor.execute("SELECT * FROM bus_log ORDER BY id DESC LIMIT 100")
        rows = cursor.fetchall()
        logs = []
        for r in rows:
            logs.append({
                "id": r[0],
                "bus_id": r[1],
                "entry_time": r[2] if r[2] else "Not logged",
                "exit_time": r[3] if r[3] else "Not logged",
                "arrival_time": r[4] if r[4] else "Not logged"
            })
        return jsonify(logs)
    except Exception as e:
        print(f"Error getting logs: {e}")
        return jsonify([])

@app.route("/logBus", methods=["POST"])
def log_bus():
    """Log bus entry/exit"""
    try:
        data = request.json
        bus_id = data.get("bus_id")
        entry = data.get("entry_time")
        exit_time = data.get("exit_time")
        arrival = data.get("arrival_time")
        
        cursor.execute("""
            INSERT INTO bus_log(bus_id, entry_time, exit_time, arrival_time)
            VALUES(?,?,?,?)
        """, (bus_id, entry, exit_time, arrival))
        conn.commit()
        
        return jsonify({"status": "saved"})
        
    except Exception as e:
        print(f"Error logging bus: {e}")
        return jsonify({"error": str(e)}), 500

# ---------------- DASHBOARD ----------------

@app.route("/dashboard")
def dashboard():
    """Get dashboard data for admin"""
    try:
        active_buses = len(bus_locations)
        
        delayed = 0
        for bus_id, data in bus_locations.items():
            if data.get("speed", 0) < 10:
                delayed += 1
        
        try:
            df = pd.read_excel(EXCEL_FILE, sheet_name="Students")
            total_students = len(df)
        except:
            total_students = 0
        
        cursor.execute("SELECT COUNT(*) FROM emergency_alerts WHERE status = 'active'")
        emergency_count = cursor.fetchone()[0]
        
        return jsonify({
            "active_buses": active_buses,
            "delayed_buses": delayed,
            "students": total_students,
            "emergency": emergency_count
        })
        
    except Exception as e:
        print(f"Error getting dashboard: {e}")
        return jsonify({
            "active_buses": 0,
            "delayed_buses": 0,
            "students": 0,
            "emergency": 0
        })

@app.route("/busSummary/<bus_id>")
def bus_summary(bus_id):
    """Get summary for a specific bus"""
    try:
        df = pd.read_excel(EXCEL_FILE, sheet_name="Students")
        df['bus_id'] = df['bus_id'].astype(str)
        students_on_bus = len(df[df["bus_id"] == str(bus_id)])
        
        today = datetime.now().strftime("%Y-%m-%d")
        cursor.execute("""
            SELECT COUNT(*) FROM attendance 
            WHERE bus_id = ? AND date = ? AND status = 'Present'
        """, (bus_id, today))
        present_count = cursor.fetchone()[0]
        
        location = None
        if bus_id in bus_locations:
            loc = bus_locations[bus_id]
            location = {
                "lat": loc["latitude"],
                "lng": loc["longitude"],
                "speed": loc.get("speed", 0)
            }
        
        return jsonify({
            "bus_id": bus_id,
            "total_students": students_on_bus,
            "present_today": present_count,
            "location": location,
            "status": "active" if bus_id in bus_locations else "inactive"
        })
        
    except Exception as e:
        print(f"Error in bus summary: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/downloadReport")
def download_report():
    """Download full report"""
    try:
        cursor.execute("SELECT * FROM bus_log")
        rows = cursor.fetchall()
        
        filename = "bus_report.csv"
        with open(filename, "w", newline="") as file:
            writer = csv.writer(file)
            writer.writerow(["ID", "Bus ID", "Entry Time", "Exit Time", "Arrival Time"])
            writer.writerows(rows)
        
        return send_file(filename, as_attachment=True)
        
    except Exception as e:
        print(f"Error downloading report: {e}")
        return jsonify({"error": str(e)}), 500

# ---------------- ANOMALIES ----------------

@app.route("/getAnomalies")
def get_anomalies():
    """Get active anomalies"""
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
    return jsonify({"anomalies": anomalies_list, "count": len(anomalies_list)})

@app.route("/getAnomalyHistory")
def get_anomaly_history():
    """Get anomaly history"""
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
        
        return jsonify({"history": history, "count": len(history)})
        
    except Exception as e:
        print(f"Error getting anomaly history: {e}")
        return jsonify({"history": []}), 500

@app.route("/resolveAnomaly", methods=["POST"])
def resolve_anomaly():
    """Resolve an anomaly"""
    try:
        data = request.json
        bus_id = data.get("bus_id")
        
        if bus_id in bus_anomalies:
            del bus_anomalies[bus_id]
            
            cursor.execute("""
                UPDATE anomaly_logs 
                SET status = 'resolved' 
                WHERE bus_id = ? AND status = 'active'
            """, (bus_id,))
            conn.commit()
            
            return jsonify({"status": "success", "message": f"Anomaly resolved for bus {bus_id}"})
        
        return jsonify({"status": "error", "message": "No active anomaly found"})
        
    except Exception as e:
        print(f"Error resolving anomaly: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/reroute", methods=["POST"])
def reroute_bus():
    """Reroute a broken bus to a replacement bus"""
    try:
        data = request.json
        old_bus = data.get("old_bus")
        new_bus = data.get("new_bus")
        reason = data.get("reason", "Admin reroute")
        
        print(f"\n🚌 REROUTE: {old_bus} -> {new_bus}")
        print(f"   Reason: {reason}")
        
        try:
            df = pd.read_excel(EXCEL_FILE, sheet_name="Students")
            df['bus_id'] = df['bus_id'].astype(str)
            df.loc[df["bus_id"] == old_bus, "bus_id"] = new_bus
            df.to_excel(EXCEL_FILE, sheet_name="Students", index=False)
            print(f"   ✅ Updated {len(df[df['bus_id'] == new_bus])} students")
        except Exception as e:
            print(f"   ⚠️ Could not update Excel: {e}")
        
        return jsonify({"status": "success", "message": f"Rerouted {old_bus} to {new_bus}"})
        
    except Exception as e:
        print(f"Error rerouting bus: {e}")
        return jsonify({"error": str(e)}), 500

# ---------------- FACE ATTENDANCE ----------------

@app.route("/faceAttendance", methods=["POST"])
def face_attendance_api():
    """Face recognition attendance using lightweight image comparison"""
    print("📸 API HIT - Face Attendance")
    
    if 'image' not in request.files:
        return jsonify({"status": "failed", "message": "No image uploaded"})
    
    file = request.files['image']
    bus_id = request.form.get("bus_id", "Unknown")
    
    try:
        file_bytes = np.frombuffer(file.read(), np.uint8)
        img = cv2.imdecode(file_bytes, cv2.IMREAD_COLOR)
        
        if img is None:
            return jsonify({"status": "failed", "message": "Invalid image format"})
        
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        
        if not known_faces:
            return jsonify({"status": "failed", "message": "No student faces loaded. Add images to faces/ folder"})
        
        best_match = None
        best_score = float('inf')
        
        for student_id, known_img in known_faces.items():
            resized = cv2.resize(gray, (known_img.shape[1], known_img.shape[0]))
            diff = np.mean((resized.astype(float) - known_img.astype(float)) ** 2)
            
            if diff < best_score:
                best_score = diff
                best_match = student_id
        
        if best_score < 2000:
            current_time = datetime.now()
            date_str = current_time.strftime("%Y-%m-%d")
            time_str = current_time.strftime("%H:%M:%S")
            
            cursor.execute("""
                INSERT INTO attendance (student_id, bus_id, date, status, time)
                VALUES (?, ?, ?, ?, ?)
            """, (best_match, bus_id, date_str, "Present", time_str))
            conn.commit()
            
            cursor.execute("""
                INSERT INTO face_attendance (student_id, bus_id, time, status, date)
                VALUES (?, ?, ?, ?, ?)
            """, (best_match, bus_id, current_time.isoformat(), "Present", date_str))
            conn.commit()
            
            print(f"✅ Face attendance marked for {best_match} (score: {best_score:.2f})")
            
            return jsonify({
                "status": "success",
                "message": f"Attendance marked for {best_match}",
                "data": {
                    "student_id": best_match,
                    "bus_id": bus_id,
                    "time": current_time.isoformat()
                }
            })
        else:
            return jsonify({
                "status": "failed",
                "message": f"Face not recognized (score: {best_score:.2f})"
            })
            
    except Exception as e:
        print(f"❌ Face attendance error: {e}")
        return jsonify({"status": "error", "message": f"Error: {str(e)}"})

@app.route("/recognizeFace", methods=["POST"])
def recognize_face():
    """Recognize face from base64 image (compatibility)"""
    try:
        data = request.json
        image_data = data.get("image", "")
        
        if not image_data:
            return jsonify({"status": "error", "message": "No image data"})
        
        image_bytes = base64.b64decode(image_data)
        img = cv2.imdecode(np.frombuffer(image_bytes, np.uint8), cv2.IMREAD_COLOR)
        
        if img is None:
            return jsonify({"status": "error", "message": "Invalid image format"})
        
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        
        if not known_faces:
            return jsonify({"status": "error", "message": "No registered faces found"})
        
        best_match = None
        best_score = float('inf')
        
        for student_id, known_img in known_faces.items():
            resized = cv2.resize(gray, (known_img.shape[1], known_img.shape[0]))
            diff = np.mean((resized.astype(float) - known_img.astype(float)) ** 2)
            
            if diff < best_score:
                best_score = diff
                best_match = student_id
        
        if best_score < 2000:
            confidence = max(0, min(100, 100 - (best_score / 20)))
            print(f"✅ Face recognized: Student {best_match} (confidence: {confidence:.2f}%)")
            
            return jsonify({
                "status": "recognized",
                "reg_no": best_match,
                "name": best_match,
                "confidence": round(confidence, 2)
            })
        
        return jsonify({"status": "unknown", "message": "Face not recognized"})
        
    except Exception as e:
        print(f"❌ Face recognition error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

# ---------------- VOICE ASSISTANT ----------------

@app.route("/voiceCommand", methods=["POST"])
def voice_command():
    """Handle voice commands"""
    try:
        data = request.json
        command = data.get("command", "").lower()
        bus_id = data.get("bus_id")
        
        if "location" in command or "where" in command:
            if bus_id and bus_id in bus_locations:
                loc = bus_locations[bus_id]
                return jsonify({"response": f"Bus {bus_id} is at {loc['latitude']:.4f}, {loc['longitude']:.4f}"})
            else:
                return jsonify({"response": "Bus location not available"})
        
        elif "emergency" in command or "help" in command:
            return jsonify({"response": f"Emergency alert sent for bus {bus_id}"})
        
        elif "status" in command:
            if bus_id and bus_id in bus_locations:
                if bus_id in bus_anomalies:
                    return jsonify({"response": f"Bus {bus_id} has anomaly: {bus_anomalies[bus_id]['anomaly']}"})
                else:
                    return jsonify({"response": f"Bus {bus_id} is running normally"})
            else:
                return jsonify({"response": "Bus status unknown"})
        
        elif "average" in command or "speed" in command:
            avg_speed = sum(speed_records) / len(speed_records) if speed_records else 0
            return jsonify({"response": f"Average bus speed is {round(avg_speed, 2)} km/h"})
        
        elif "anomaly" in command:
            if bus_anomalies:
                return jsonify({"response": f"There are {len(bus_anomalies)} active anomalies"})
            else:
                return jsonify({"response": "No active anomalies detected"})
        
        elif "bus count" in command or "how many buses" in command:
            return jsonify({"response": f"There are {len(bus_locations)} buses currently active"})
        
        else:
            return jsonify({"response": "I didn't understand. Try: bus location, bus status, average speed, anomalies, emergency, or bus count"})
        
    except Exception as e:
        print(f"Error processing voice command: {e}")
        return jsonify({"response": "Sorry, there was an error processing your command"}), 500

# ---------------- LEGACY ENDPOINTS ----------------

@app.route("/boardBus", methods=["POST"])
def board_bus():
    try:
        data = request.json
        bus = data.get("bus_id")
        if bus not in bus_boarded:
            bus_boarded[bus] = 0
        bus_boarded[bus] += 1
        return jsonify({"count": bus_boarded[bus]})
    except Exception as e:
        print(f"Error boarding bus: {e}")
        return jsonify({"count": 0})

@app.route("/emergency", methods=["POST"])
def emergency():
    data = request.json
    print(f"Emergency from bus: {data.get('bus_id')}")
    return jsonify({"status": "alert sent"})

@app.route("/analytics")
def analytics():
    avg_speed = sum(speed_records) / len(speed_records) if speed_records else 0
    delay_count = delay_records.count("Delayed") + delay_records.count("Slight Delay")
    total = len(delay_records) if delay_records else 1
    delay_rate = (delay_count / total) * 100
    
    return jsonify({
        "average_speed": round(avg_speed, 2),
        "delay_rate": round(delay_rate, 2),
        "total_records": len(speed_records),
        "current_active_buses": len(bus_locations),
        "anomaly_count": len(bus_anomalies)
    })

# ---------------- DEBUG ENDPOINT ----------------

@app.route("/debugStops")
def debug_stops():
    """Debug endpoint to check Excel stops data"""
    try:
        df = pd.read_excel(EXCEL_FILE, sheet_name="Stops")
        
        return jsonify({
            "total_stops": len(df),
            "columns": df.columns.tolist(),
            "buses_with_stops": df['bus_id'].astype(str).unique().tolist(),
            "sample_data": df.head(10).to_dict(orient="records")
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ---------------- RUN SERVER ----------------

if __name__ == "__main__":
    print("\n" + "="*60)
    print("🚀 TRANSPORT SYSTEM SERVER STARTED")
    print("="*60)
    print(f"📊 Face Recognition: ✅ Lightweight Mode (OpenCV)")
    print(f"📁 Faces folder: {'faces/'}")
    print(f"📁 Excel file: {EXCEL_FILE}")
    print(f"🚨 Anomaly detection: Active (Speed limit: {OVERSPEED_LIMIT} km/h)")
    print(f"🚨 Emergency Alerts: Active")
    print(f"🗺️ Route History: Active")
    print(f"📍 College Location: {COLLEGE_LAT}, {COLLEGE_LON}")
    print("="*60)
    print("\n✅ Critical Endpoints:")
    print("   📍 /sendLocation - Update bus location")
    print("   📍 /getStops/<bus_id> - Get stops for bus (from Excel)")
    print("   👤 /getStudentsByBus/<bus_id> - Get students for bus")
    print("   👤 /faceAttendance - Face recognition attendance")
    print("   🚨 /sendEmergency - Send emergency alert")
    print("   📊 /dashboard - Dashboard data")
    print("   👨‍👩‍👧 /parentData/<student_id> - Parent view data")
    print("   🗺️ /getRoutes/<bus_id> - Get routes by date")
    print("   🔍 /debugStops - Debug stops data")
    print("="*60 + "\n")
    app.run(host="0.0.0.0", port=5000, debug=True)
