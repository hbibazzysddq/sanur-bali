import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:convert';
import 'package:intl/intl.dart';

class DeviceInfo {
  final String id;
  final LatLng location;
  DateTime lastActivity;
  bool isActive;

  DeviceInfo({
    required this.id,
    required this.location,
    required this.lastActivity,
    this.isActive = false,
  });
}

class MapPage extends StatefulWidget {
  const MapPage({Key? key}) : super(key: key);

  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const LatLng _defaultCenter = LatLng(-8.6776782, 115.2611143);
  final Map<String, DeviceInfo> _devices = {};
  int _activeDevices = 0;
  DateTime _lastUpdateTime = DateTime.now();

  GoogleMapController? _mapController;
  Timer? _dataFetchTimer;
  Timer? _inactivityCheckTimer;
  BitmapDescriptor? _activeMarkerIcon;
  BitmapDescriptor? _inactiveMarkerIcon;

  static const Duration _inactivityThreshold = Duration(minutes: 2);
  static const Duration _deactivationDuration = Duration(minutes: 2);

  final Map<String, LatLng> _manualCoordinates = {
    'id-18-test': LatLng(-8.679664, 115.260628),
    'id-19-test': LatLng(-8.679740, 115.261846),
    'id-20-test': LatLng(-8.675548, 115.261195),
  };

  @override
  void initState() {
    super.initState();
    _createMarkerIcons();
    _initializeDevices();
    _startDataFetchTimer();
    _startInactivityCheckTimer();
  }

  void _initializeDevices() {
    _manualCoordinates.forEach((id, location) {
      _devices[id] = DeviceInfo(
        id: id,
        location: location,
        lastActivity: DateTime.now().subtract(Duration(seconds: 5)),
        isActive: false,
      );
    });
    _updateActiveDeviceCount();
  }

  @override
  void dispose() {
    _dataFetchTimer?.cancel();
    _inactivityCheckTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _createMarkerIcons() async {
    _activeMarkerIcon = await _createCustomMarkerBitmap(Colors.red);
    _inactiveMarkerIcon = await _createCustomMarkerBitmap(Colors.green);
    setState(() {});
  }

  Future<BitmapDescriptor> _createCustomMarkerBitmap(Color color) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    final paint = Paint()..color = color;

    canvas.drawCircle(Offset(12, 12), 12, paint); // Lingkaran luar

    final centerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(12, 12), 6, centerPaint); // Lingkaran tengah

    canvas.drawCircle(Offset(12, 12), 4, paint); // Lingkaran dalam

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(24, 24); // Ubah ukuran gambar marker
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  void _startDataFetchTimer() {
    _dataFetchTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _fetchDataFromServer();
    });
  }

  void _startInactivityCheckTimer() {
    _inactivityCheckTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _checkDeviceInactivity();
    });
  }

  void _updateActiveDeviceCount() {
    setState(() {
      _activeDevices =
          _devices.values.where((device) => device.isActive).length;
    });
    print("Active devices count: $_activeDevices");
    _devices.forEach((id, device) {
      print(
          "Device $id - Active: ${device.isActive}, Last activity: ${device.lastActivity}");
    });
  }

  Future<void> _fetchDataFromServer() async {
    try {
      final response =
          await http.get(Uri.parse('http://202.157.187.108:3000/data'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print("Received data: $data");
        _updateDeviceInfo(data);
        setState(() {
          _lastUpdateTime = DateTime.now();
        });
        print("Data processed at $_lastUpdateTime");
      } else {
        print('Failed to fetch data: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching data: $e');
    }
  }

  void _updateDeviceInfo(dynamic data) {
    final now = DateTime.now();
    bool statusChanged = false;

    if (data is List && data.isNotEmpty) {
      for (var item in data) {
        if (item is Map<String, dynamic>) {
          final String deviceId = item['end_device_ids']['device_id'];
          if (_devices.containsKey(deviceId)) {
            final DeviceInfo device = _devices[deviceId]!;

            // Hanya perbarui waktu aktivitas terakhir jika perangkat aktif
            if (!device.isActive) {
              device.isActive = true; // Aktifkan perangkat
              device.lastActivity = now; // Update waktu aktivitas terakhir
              statusChanged = true;
              print("Device $deviceId activated at ${now}");

              // Set a timer to deactivate the device after 5 minutes
              Timer(_deactivationDuration, () {
                setState(() {
                  device.isActive = false; // Deactivate the device
                  print("Device $deviceId deactivated after 5 minutes.");
                  _updateActiveDeviceCount();
                });
              });
            } else {
              // Jika perangkat sudah aktif, cukup perbarui waktu aktivitas terakhir
              device.lastActivity = now; // Perbarui waktu aktivitas terakhir
            }
          }
        }
      }
    }

    // Periksa semua perangkat aktif yang ada
    _checkDeviceInactivity();

    if (statusChanged) {
      _updateActiveDeviceCount();
    }
  }

  void _checkDeviceInactivity() {
    final now = DateTime.now();
    bool statusChanged = false;

    _devices.forEach((id, device) {
      if (device.isActive &&
          now.difference(device.lastActivity) > _inactivityThreshold) {
        device.isActive =
            false; // Matikan perangkat jika tidak aktif selama threshold
        statusChanged = true;
        print(
            "Device $id deactivated due to inactivity. Last activity: ${device.lastActivity}");
      }
    });

    if (statusChanged) {
      _updateActiveDeviceCount();
    }
  }

  void _resetAllDevices() {
    setState(() {
      _devices.forEach((id, device) {
        device.isActive = false; // Matikan perangkat
        // Biarkan waktu aktivitas terakhir tetap
        print("Device $id has been reset to inactive");
      });
      _updateActiveDeviceCount();
      _lastUpdateTime = DateTime.now();
    });
  }

  void _resetMapToDefault() {
    if (_mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(_defaultCenter));
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _fitBounds();
  }

  void _fitBounds() {
    if (_devices.isEmpty || _mapController == null) {
      _resetMapToDefault();
      return;
    }

    double minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;

    _devices.values.forEach((device) {
      minLat =
          minLat < device.location.latitude ? minLat : device.location.latitude;
      maxLat =
          maxLat > device.location.latitude ? maxLat : device.location.latitude;
      minLng = minLng < device.location.longitude
          ? minLng
          : device.location.longitude;
      maxLng = maxLng > device.location.longitude
          ? maxLng
          : device.location.longitude;
    });

    LatLngBounds bounds = LatLngBounds(
      northeast: LatLng(maxLat, maxLng),
      southwest: LatLng(minLat, minLng),
    );

    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  Set<Marker> _createMarkers() {
    return _devices.values.map((device) {
      return Marker(
        markerId: MarkerId(device.id),
        position: device.location,
        icon: device.isActive ? _activeMarkerIcon! : _inactiveMarkerIcon!,
        infoWindow: InfoWindow(
          title: device.id,
          snippet:
              'Last activity: ${DateFormat('yyyy-MM-dd – kk:mm:ss').format(device.lastActivity)}',
          onTap: () {
            _showInfoDialog(device);
          },
        ),
      );
    }).toSet();
  }

  Future<void> _showInfoDialog(DeviceInfo device) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Device Info - ${device.id}'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Status: ${device.isActive ? 'Active' : 'Inactive'}'),
                Text('Last Activity: ${device.lastActivity}'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Device Tracker'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _resetAllDevices,
          ),
        ],
      ),
      body: GoogleMap(
        onMapCreated: _onMapCreated,
        mapType: MapType.satellite,
        markers: _createMarkers(),
        initialCameraPosition: CameraPosition(
          target: _defaultCenter,
          zoom: 15,
        ),
      ),
    );
  }
}
