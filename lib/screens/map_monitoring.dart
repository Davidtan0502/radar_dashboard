import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:radar_dashboard/components/section_header.dart';
import 'package:radar_dashboard/services/cache_manager.dart';
import 'package:radar_dashboard/services/performance_monitor.dart';

class MapMonitoring extends StatefulWidget {
  const MapMonitoring({super.key});

  @override
  State<MapMonitoring> createState() => _MapMonitoringState();
}

class _MapMonitoringState extends State<MapMonitoring> {
  final LatLng _initialPosition = const LatLng(14.5995, 120.9842);
  final Set<Marker> _markers = {};
  late GoogleMapController _mapController;
  final _perfMonitor = PerformanceMonitor();
  final _cacheManager = DashboardCacheManager();
  final _geocodingCache = <String, LatLng>{};
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    _perfMonitor.startTrace('map_initialization');
    try {
      await _loadCachedData();
      await _fetchAndGeocodeIncidents();
      _perfMonitor.stopTrace('map_initialization');
    } catch (e) {
      _perfMonitor.logEvent('map_init_error', {'error': e.toString()});
      setState(() {
        _errorMessage = 'Failed to load map data: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadCachedData() async {
    try {
      final cachedMarkers = await _cacheManager.getData<List<dynamic>>(
        key: 'cached_markers',
        fetchData: () async => [],
        cacheDuration: const Duration(hours: 1),
      );
      
      if (cachedMarkers.isNotEmpty) {
        setState(() {
          _markers.addAll(cachedMarkers.cast<Marker>());
        });
      }
    } catch (e) {
      debugPrint('Cache load error: $e');
    }
  }

  Future<void> _fetchAndGeocodeIncidents() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('incidents')
          .where('address', isNotEqualTo: null)
          .limit(100)
          .get();

      debugPrint('Found ${querySnapshot.docs.length} incidents');
      
      for (final doc in querySnapshot.docs) {
        try {
          final data = doc.data();
          debugPrint('Processing incident: ${doc.id}');
          
          final position = await _getPositionFromDoc(data);
          if (position != null) {
            final marker = await _createMarker(doc.id, data, position);
            setState(() {
              _markers.add(marker);
            });
          }
        } catch (e) {
          debugPrint('Error processing doc ${doc.id}: $e');
        }
      }

      await _cacheManager.saveData(
        key: 'cached_markers',
        data: _markers.toList(),
        duration: const Duration(minutes: 30),
      );
    } catch (e) {
      debugPrint('Fetch error: $e');
      rethrow;
    }
  }

  Future<LatLng?> _getPositionFromDoc(Map<String, dynamic> data) async {
    final address = data['address'] as String? ?? '';
    
    // First try to use existing coordinates
    if (data['latitude'] != null && data['longitude'] != null) {
      return LatLng(
        (data['latitude'] as num).toDouble(),
        (data['longitude'] as num).toDouble(),
      );
    }
    
    // Fall back to geocoding
    return await _getCachedGeocode(address);
  }

  Future<Marker> _createMarker(String id, Map<String, dynamic> data, LatLng position) async {
    final incidentType = data['incidentType'] as String? ?? 'Incident';
    final status = data['status'] as String? ?? 'Unknown';
    final timestamp = data['timestamp'] as String? ?? '';
    
    return Marker(
      markerId: MarkerId(id),
      position: position,
      infoWindow: InfoWindow(
        title: incidentType,
        snippet: 'Status: $status\n${data['address']}\n$timestamp',
      ),
      icon: await _getCustomMarkerIcon(
        data['severity'] as String? ?? 'medium',
        status.toLowerCase(),
      ),
    );
  }

  Future<BitmapDescriptor> _getCustomMarkerIcon(String severity, String status) async {
    const size = 120.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
    
    final color = _getColorForStatus(status) ?? _getColorForSeverity(severity);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    // Draw pin shape
    canvas.drawCircle(Offset(size / 2, size / 3), size / 4, paint);
    canvas.drawPath(
      Path()
        ..moveTo(size / 2, size / 3 * 2)
        ..lineTo(size / 2 - size / 6, size)
        ..lineTo(size / 2 + size / 6, size)
        ..close(),
      paint,
    );
    
    // Add status/severity indicator
    final text = status == 'pending' ? 'P' : severity[0].toUpperCase();
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(size / 2 - textPainter.width / 2, size / 3 - textPainter.height / 2),
    );
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  Color _getColorForSeverity(String severity) {
    switch (severity.toLowerCase()) {
      case 'high': return Colors.red;
      case 'medium': return Colors.orange;
      case 'low': return Colors.green;
      default: return Colors.purple;
    }
  }

  Color? _getColorForStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return Colors.grey;
      case 'resolved': return Colors.blue;
      case 'in-progress': return Colors.yellow;
      default: return null;
    }
  }

  Future<LatLng?> _getCachedGeocode(String address) async {
    if (_geocodingCache.containsKey(address)) {
      return _geocodingCache[address];
    }

    try {
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        final position = LatLng(locations.first.latitude, locations.first.longitude);
        _geocodingCache[address] = position;
        return position;
      }
    } catch (e) {
      debugPrint('Geocoding error for $address: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: SectionHeader(
              icon: Icons.map_outlined,
              title: 'MAP MONITORING',
            ),
          ),
          Expanded(
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage.isNotEmpty
                ? Center(child: Text(_errorMessage))
                : ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _initialPosition,
                        zoom: 12,
                      ),
                      mapType: MapType.normal,
                      myLocationEnabled: true,
                      markers: _markers,
                      onMapCreated: (controller) {
                        _mapController = controller;
                        _perfMonitor.logEvent('map_ready');
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _perfMonitor.uploadMetrics();
    super.dispose();
  }
}