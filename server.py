from flask import Flask, request, jsonify, send_file
import pandas as pd
import sqlite3
import csv
import math

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

conn.commit()

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


# ---------------- GET BUSES ----------------

@app.route("/getBuses")
def get_buses():
    return["BUS1","BUS2"]


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


# ---------------- SAVE BUS LOCATION ----------------

bus_locations = {}

@app.route("/sendLocation", methods=["POST"])
def send_location():

    data = request.json

    bus_id = data["bus_id"]
    latitude = data["latitude"]
    longitude = data["longitude"]

    bus_locations[bus_id] = {
        "latitude": latitude,
        "longitude": longitude
    }

    distance = calculate_distance(latitude, longitude, COLLEGE_LAT, COLLEGE_LON)

    if distance < GATE_RADIUS:
        print("Bus reached college:", bus_id)

    return jsonify({"status":"ok"})


# ---------------- GET LOCATION ----------------

@app.route("/getLocation/<bus_id>")
def get_location(bus_id):

    if bus_id in bus_locations:

        lat = bus_locations[bus_id]["latitude"]
        lng = bus_locations[bus_id]["longitude"]

        distance = 2
        speed = 30

        delay_status = predict_delay(distance, speed)

        return jsonify({
            "latitude": lat,
            "longitude": lng,
            "delay": delay_status
        })

    return jsonify({
        "latitude":0,
        "longitude":0,
        "delay":"Unknown"
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

    return jsonify({
        "active_buses": active_buses,
        "delayed_buses": delayed_buses,
        "students": total_students,
        "emergency": emergency_count
    })


# ---------------- RUN SERVER ----------------

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
