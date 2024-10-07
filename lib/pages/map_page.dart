import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:convert';

class DeviceInfo {
  final String id;
  final LatLng location;
  DateTime lastActivity;
  bool isActive;

  DeviceInfo({
    required this.id,
    required this.location,
    required this.lastActivity,
    this.isActive = true,
  });
}

class MapPage extends StatefulWidget {
  const MapPage({Key? key}) : super(key: key);

  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const LatLng _defaultCenter = LatLng(-6.2735128, 106.6646446);
  final Map<String, DeviceInfo> _devices = {};
  int _activeDevices = 0;

  GoogleMapController? _mapController;
  Timer? _dataFetchTimer;
  Timer? _deviceStatusTimer;
  BitmapDescriptor? _activeMarkerIcon;
  BitmapDescriptor? _inactiveMarkerIcon;

  static const Duration _activityThreshold = Duration(seconds: 11);

  final Map<String, LatLng> _manualCoordinates = {
    'id-18-test': LatLng(-6.273461, 106.666460),
    'id-19-test': LatLng(-6.273821, 106.666095),
    'id-20-test': LatLng(-6.274412, 106.665484),
  };

  @override
  void initState() {
    super.initState();
    _createMarkerIcons();
    _startDataFetchTimer();
    _startDeviceStatusTimer();
  }

  @override
  void dispose() {
    _dataFetchTimer?.cancel();
    _deviceStatusTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _createMarkerIcons() async {
    _activeMarkerIcon = await _createCustomMarkerBitmap(Colors.red);
    _inactiveMarkerIcon = await _createCustomMarkerBitmap(Colors.blue);
    setState(() {});
  }

  Future<BitmapDescriptor> _createCustomMarkerBitmap(Color color) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    final paint = Paint()..color = color;

    canvas.drawCircle(Offset(24, 24), 12, paint);

    final centerDotPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(24, 24), 4, centerDotPaint);

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(48, 48);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  void _startDataFetchTimer() {
    _dataFetchTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _fetchDataFromServer();
    });
  }

  void _startDeviceStatusTimer() {
    _deviceStatusTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _updateDeviceStatuses();
    });
  }

  void _updateDeviceStatuses() {
    final now = DateTime.now();
    bool statusChanged = false;

    _devices.forEach((id, device) {
      if (now.difference(device.lastActivity) > _activityThreshold) {
        if (device.isActive) {
          device.isActive = false;
          statusChanged = true;
          print("Device $id is now inactive");
        }
      }
    });

    if (statusChanged) {
      setState(() {
        _activeDevices =
            _devices.values.where((device) => device.isActive).length;
      });
      _fitBounds();
    }
  }

  Future<void> _fetchDataFromServer() async {
    try {
      final response =
          await http.get(Uri.parse('http://202.157.187.108:3000/data'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _updateDeviceInfo(data);
      } else {
        print('Failed to fetch data: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching data: $e');
    }
  }

  void _updateDeviceInfo(List<dynamic> data) {
    bool dataUpdated = false;
    for (var item in data) {
      if (item is Map<String, dynamic>) {
        final String deviceId = item['end_device_ids']['device_id'];
        if (_manualCoordinates.containsKey(deviceId)) {
          final LatLng location = _manualCoordinates[deviceId]!;
          final DateTime timestamp = DateTime.parse(item['received_at']);

          if (_devices.containsKey(deviceId)) {
            _devices[deviceId]!.lastActivity = timestamp;
            _devices[deviceId]!.isActive = true;
          } else {
            _devices[deviceId] = DeviceInfo(
              id: deviceId,
              location: location,
              lastActivity: timestamp,
              isActive: true,
            );
          }

          dataUpdated = true;
        }
      }
    }

    if (dataUpdated) {
      setState(() {
        _activeDevices =
            _devices.values.where((device) => device.isActive).length;
      });
      _fitBounds();
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

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50.0));
  }

  void _resetMapToDefault() {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: _defaultCenter, zoom: 10),
      ),
    );
  }

  Set<Marker> _createMarkers() {
    return _devices.values.map((device) {
      return Marker(
        markerId: MarkerId(device.id),
        position: device.location,
        icon: device.isActive
            ? _activeMarkerIcon ?? BitmapDescriptor.defaultMarker
            : _inactiveMarkerIcon ?? BitmapDescriptor.defaultMarker,
        infoWindow: InfoWindow(
          title: device.id,
          snippet: device.isActive ? 'Active' : 'Inactive',
          onTap: () => _showInfoDialog(device),
        ),
      );
    }).toSet();
  }

  void _showInfoDialog(DeviceInfo device) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(device.id),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(device.isActive
                  ? 'Device is currently active.'
                  : 'Device is currently inactive.'),
              SizedBox(height: 8),
              Text('Last activity: ${device.lastActivity.toString()}'),
              SizedBox(height: 8),
              Text(
                  'Location: ${device.location.latitude}, ${device.location.longitude}'),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: Text('View Location'),
              onPressed: () {
                Navigator.of(context).pop();
                _mapController?.animateCamera(
                    CameraUpdate.newLatLngZoom(device.location, 18));
              },
            ),
            TextButton(
              child: Text('Close'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition:
                CameraPosition(target: _defaultCenter, zoom: 10),
            markers: _createMarkers(),
          ),
          Positioned(
            top: 50,
            left: 10,
            child: Container(
              padding: EdgeInsets.all(8),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Last updated: ${DateTime.now()}'),
                  Text('Active devices: $_activeDevices'),
                  Text('Total devices: ${_devices.length}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
