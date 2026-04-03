#Smart Transportation Management System

📌 Overview

The Smart Transportation Management System is a real-time mobile application designed to improve student safety, transport monitoring, and communication between drivers, parents, students, and administrators.

This system provides live GPS tracking, attendance management, and an SOS emergency alert system to ensure a secure and efficient transportation experience.


🚀 Features

🚌 Driver Module

- 📍 Real-time GPS tracking
- 📋 Manual attendance marking
- 🚨 SOS emergency alert system
- ⚠️ Speed monitoring & anomaly detection

👨‍🎓 Student Module

- 📍 Live bus tracking
- ⏱️ Estimated Time of Arrival (ETA)
- 🚨 Emergency alert button
- 📍 Stop-based tracking

👨‍👩‍👧 Parent Module

- 📍 Live bus location tracking
- 📋 Attendance notifications
- 🚨 Emergency alerts
- ⏱️ Arrival notifications

👨‍💼 Admin Module

- 📊 Dashboard with active/delayed buses
- 🚌 Bus-wise student monitoring
- 📋 Attendance summary
- 🚨 Emergency alert management
- 🔁 Route management & history


🏗️ System Architecture

Driver App → API → Backend Server → Database → Parent / Student / Admin

- APIs act as a bridge between frontend and backend
- Real-time data is continuously updated and shared across modules

  
🛠️ Technologies Used

- 📱 Frontend: Flutter
- 🖥️ Backend: Python (Flask)
- 🗄️ Database: SQLite
- 📊 Dataset: Excel (bus, stops, students)
- 🌐 Deployment: Render
- 💻 Version Control: GitHub



📡 API Endpoints

API| Description
"/sendLocation"| Send live GPS location
"/getLocation"| Fetch bus location
"/markAttendance"| Store attendance
"/sendEmergency"| Send SOS alert
"/parentData"| Fetch parent data
"/getBuses"| Get bus list from Excel
"/getStops/<bus_id>"| Get stops for a bus



🧠 Database Design

The system uses:

- SQLite database for dynamic data
- Excel file for static dataset

Tables:

- "attendance"
- "emergency_alerts"
- "route_history"
- "bus_log"
- "bus_stops"



⚙️ How to Run the Project

🔹 Backend (Flask)

1. Install dependencies:
   pip install -r requirements.txt
2. Run server:
   python server.py



🔹 Frontend (Flutter)

1. Install dependencies:
   flutter pub get
2. Run app:
   flutter run



📂 Project Structure

transport-management-system/
│
├── student_bus_app/       # Flutter app
├── server.py              # Backend server
├── requirements.txt       # Python dependencies
├── transport_data.xlsx    # Dataset (buses, stops, students)
├── README.md              # Project documentation



🔒 Safety Features

- 🚨 SOS emergency alert system
- 📍 Real-time tracking
- ⚠️ Speed monitoring
- 📡 Live communication between modules



📈 Advantages

- Improves student safety
- Real-time monitoring
- Efficient transport management
- Better communication between users



🚧 Limitations

- Requires internet connection
- GPS accuracy depends on device
- Backend must be running



🚀 Future Enhancements

- 🔔 Push notifications (Firebase)
- 📞 Emergency calling system
- 🧠 AI-based route prediction
- 📍 Offline tracking support
- 🎥 CCTV integration



🎯 Conclusion

This project provides a smart and secure transportation solution by integrating real-time tracking, attendance management, and emergency handling, ensuring safety and efficiency for students and administrators.



👨‍💻 Author

Developed by Kamaleeswari V
📧 Feel free to connect and give feedback!
