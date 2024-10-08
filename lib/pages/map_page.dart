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
  BitmapDescriptor? _gatewayMarkerIcon;

  static const Duration _inactivityThreshold = Duration(minutes: 1);
  static const Duration _deactivationDuration = Duration(minutes: 5);

  final Map<String, LatLng> _manualCoordinates = {
    'id-1': LatLng(-8.679444, 115.260556),
    'id-2': LatLng(-8.679722, 115.261389),
    'Gateway 1': LatLng(-8.679722, 115.261667),
    'id-3': LatLng(-8.679444, 115.262222),
    'id-4': LatLng(-8.678611, 115.262500),
    'id-5': LatLng(-8.677222, 115.262500),
    'id-6': LatLng(-8.676389, 115.262222),
    'id-7': LatLng(-8.675556, 115.261944),
    'id-8': LatLng(-8.675556, 115.260833),
    'Gateway 2': LatLng(-8.675833, 115.260833),
    'id-9': LatLng(-8.676111, 115.260833),
    'id-10': LatLng(-8.677222, 115.260556),
    'id-11': LatLng(-8.677222, 115.260000),
    'id-12': LatLng(-8.678056, 115.261944),
    'id-13': LatLng(-8.678056, 115.260556),
    'id-14': LatLng(-8.678056, 115.259722),
    'id-15': LatLng(-8.676389, 115.261944),
    'id-16': LatLng(-8.676667, 115.261111),
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
    _gatewayMarkerIcon = await _createCustomMarkerBitmap(Colors.purple);
    setState(() {});
  }

  Future<BitmapDescriptor> _createCustomMarkerBitmap(Color color) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    final paint = Paint()..color = color;

    canvas.drawCircle(Offset(12, 12), 12, paint);

    final centerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(12, 12), 6, centerPaint);

    canvas.drawCircle(Offset(12, 12), 4, paint);

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(24, 24);
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
          if (_devices.containsKey(deviceId) &&
              !deviceId.toLowerCase().contains('gateway')) {
            final DeviceInfo device = _devices[deviceId]!;

            if (!device.isActive) {
              device.isActive = true;
              device.lastActivity = now;
              statusChanged = true;
              print("Device $deviceId activated at ${now}");

              // Show alert when device becomes active
              _showDeviceActivationAlert(device);

              Timer(_deactivationDuration, () {
                setState(() {
                  device.isActive = false;
                  print("Device $deviceId deactivated after 5 minutes.");
                  _updateActiveDeviceCount();
                });
              });
            } else {
              device.lastActivity = now;
            }
          }
        }
      }
    }

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
        device.isActive = false;
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
        device.isActive = false;
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
      if (device.id.toLowerCase().contains('gateway')) {
        return Marker(
          markerId: MarkerId(device.id),
          position: device.location,
          icon: _gatewayMarkerIcon!,
          onTap: () => _showDeviceInfo(device),
        );
      } else {
        return Marker(
          markerId: MarkerId(device.id),
          position: device.location,
          icon: device.isActive ? _activeMarkerIcon! : _inactiveMarkerIcon!,
          onTap: () => _showDeviceInfo(device),
        );
      }
    }).toSet();
  }

  void _showDeviceActivationAlert(DeviceInfo device) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('DANGER ALERT',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 50),
              SizedBox(height: 10),
              Text('Device ${device.id} is ACTIVE!',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  'Location: ${device.location.latitude}, ${device.location.longitude}'),
            ],
          ),
          backgroundColor: Colors.yellow,
          actions: [
            TextButton(
              child: Text('View on Map', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop();
                _mapController?.animateCamera(
                  CameraUpdate.newLatLngZoom(device.location, 18),
                );
              },
            ),
            TextButton(
              child: Text('Dismiss', style: TextStyle(color: Colors.black)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showDeviceInfo(DeviceInfo device) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        bool isGateway = device.id.toLowerCase().contains('gateway');
        return Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isGateway ? 'Gateway ${device.id}' : 'Device ${device.id}',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              if (!isGateway) ...[
                _buildInfoRow(
                    'Status', device.isActive ? 'Active' : 'Inactive'),
                _buildInfoRow(
                    'Last Activity',
                    DateFormat('yyyy-MM-dd – kk:mm:ss')
                        .format(device.lastActivity)),
              ],
              _buildInfoRow('Location',
                  '${device.location.latitude}, ${device.location.longitude}'),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLngZoom(device.location, 18),
                  );
                },
                child: Text('Zoom to ${isGateway ? 'Gateway' : 'Device'}'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: isGateway ? Colors.purple : Colors.blue,
                  minimumSize: Size(double.infinity, 50),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text(value, style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            mapType: MapType.satellite,
            markers: _createMarkers(),
            initialCameraPosition: CameraPosition(
              target: _defaultCenter,
              zoom: 15,
            ),
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            right: 10,
            child: Card(
              color: Colors.white.withOpacity(0.8),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Device Tracker',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Active Devices: $_activeDevices',
                          style: TextStyle(fontSize: 14),
                        ),
                        Text(
                          'Last Update: ${DateFormat('yyyy-MM-dd – kk:mm:ss').format(_lastUpdateTime)}',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh),
                      onPressed: _resetAllDevices,
                      tooltip: 'Reset all devices',
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 10,
            bottom: 90,
            child: FloatingActionButton(
              onPressed: _fitBounds,
              child: Icon(Icons.center_focus_strong),
              tooltip: 'Fit all markers',
              backgroundColor: Colors.white,
              foregroundColor: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }
}
