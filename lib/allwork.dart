// lib/screens/allwork.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:collection/collection.dart';
import '../config/api_endpoints.dart';
import 'config/orders_model.dart';

class AllWorkMapScreen extends StatefulWidget {
  final int userId;
  const AllWorkMapScreen({super.key, required this.userId});

  @override
  State<AllWorkMapScreen> createState() => _AllWorkMapScreenState();
}

class _AllWorkMapScreenState extends State<AllWorkMapScreen>
    with SingleTickerProviderStateMixin {
  late MapController _mapController;
  bool _isLoading = true;
  List<OrderModel> _allOrders = [];
  Map<int, LatLng> _riderLocations = {};
  late AnimationController _animationController;
  late Animation<double> _animation;
  Timer? _locationTimer;
  bool _isFitting = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _animationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.repeat(reverse: true);
    _loadAllOrders();
    _startLocationUpdateTimer();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadAllOrders() async {
    try {
      if (mounted) setState(() => _isLoading = true);
      final response = await http
          .get(
            Uri.parse(
              '${ApiEndpoints.baseUrl}/get-orders-receiver?userId=${widget.userId}',
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 && response.body.isNotEmpty && mounted) {
        final List<dynamic> jsonList = json.decode(response.body);
        final orders = jsonList.map((j) => OrderModel.fromJson(j)).toList();

        setState(() {
          _allOrders = orders;
          _isLoading = false;
        });

        if (_allOrders.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _fitAllMarkers();
          });
          _updateRiderLocations();
        }
      }
    } catch (e) {
      debugPrint('Load orders error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: $e')));
      }
    }
  }

  void _startLocationUpdateTimer() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updateRiderLocations();
    });
  }

  Future<void> _updateRiderLocations() async {
    if (_allOrders.isEmpty || !mounted) return;

    final activeRiderIds = _allOrders
        .where((o) => o.riderId != 0 && (o.status == 2 || o.status == 3))
        .map((o) => o.riderId)
        .toSet();

    if (activeRiderIds.isEmpty) {
      if (_riderLocations.isNotEmpty && mounted) {
        setState(() => _riderLocations.clear());
      }
      return;
    }

    final futures = activeRiderIds.map(_fetchRiderLocation).toList();
    final results = await Future.wait(futures, eagerError: false);

    final newLocations = <int, LatLng>{};
    for (var r in results) {
      if (r != null) {
        newLocations[r['id'] as int] = LatLng(
          r['lat'] as double,
          r['lng'] as double,
        );
      }
    }

    if (!mounted || MapEquality().equals(_riderLocations, newLocations)) return;

    setState(() => _riderLocations = newLocations);
  }

  Future<Map<String, dynamic>?> _fetchRiderLocation(int riderId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiEndpoints.baseUrl}/get-rider-location/$riderId'))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final data = json.decode(response.body);
        final lat = double.tryParse(data['latitude']?.toString() ?? '');
        final lng = double.tryParse(data['longitude']?.toString() ?? '');
        if (lat != null && lng != null) {
          return {'id': riderId, 'lat': lat, 'lng': lng};
        }
      }
    } catch (_) {}
    return null;
  }

  void _fitAllMarkers() {
    if (_isFitting || _riderLocations.isEmpty) return;
    final points = _riderLocations.values.toList();
    if (points.isEmpty) return;

    _isFitting = true;
    double minLat = points.first.latitude, maxLat = minLat;
    double minLng = points.first.longitude, maxLng = minLng;

    for (var p in points.skip(1)) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final bounds = LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80)),
    );

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _isFitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'งานส่งทั้งหมด',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF8329B4),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllOrders,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatsHeader(),
          _buildLegendRow(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _riderLocations.isEmpty
                ? const Center(child: Text('ไม่มีไรเดอร์ออนไลน์'))
                : Stack(children: [_buildMap(), _buildLiveCount()]),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader() {
    final activeRiders = _allOrders
        .where((o) => o.riderId != 0 && (o.status == 2 || o.status == 3))
        .length;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatCard('ทั้งหมด', _allOrders.length, Icons.local_shipping),
          _buildStatCard('กำลังส่ง', activeRiders, Icons.directions_bike),
          _buildStatCard(
            'ส่งแล้ว',
            _allOrders.where((o) => o.status == 4).length,
            Icons.check_circle,
          ),
        ],
      ),
    );
  }

  Widget _buildLegendRow() => Container(
    color: Colors.white,
    padding: const EdgeInsets.all(12),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: const Center(child: Text('ไรเดอร์', style: TextStyle(fontSize: 12))),
  );

  Widget _buildLiveCount() => Positioned(
    top: 20,
    right: 20,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade600,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Live: ${_riderLocations.length} คน',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );

  Widget _buildStatCard(String title, int count, IconData icon) => Column(
    children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.blue),
      ),
      const SizedBox(height: 8),
      Text(
        '$count',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      Text(title, style: const TextStyle(color: Colors.grey)),
    ],
  );

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(
        initialCenter: LatLng(16.1887929, 103.29831317),
        initialZoom: 10.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
        ),
        PolylineLayer(
          polylines: _allOrders
              .where((o) => o.status == 3 && o.riderId != 0)
              .map(
                (o) => Polyline(
                  points: [
                    LatLng(o.senderAddress.lat, o.senderAddress.lng),
                    LatLng(o.receiverAddress.lat, o.receiverAddress.lng),
                  ],
                  color: Colors.purple.withOpacity(0.7),
                  strokeWidth: 3.0,
                  isDotted: true,
                ),
              )
              .toList(),
        ),
        MarkerLayer(markers: _buildRiderMarkers()),
      ],
    );
  }

  List<Marker> _buildRiderMarkers() {
    return _riderLocations.entries.map((e) {
      final orders = _allOrders
          .where((o) => o.riderId == e.key && (o.status == 2 || o.status == 3))
          .toList();
      return Marker(
        point: e.value,
        width: 80,
        height: 90,
        child: GestureDetector(
          onTap: () => _showRiderPopup(e.key, orders),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _animation,
                builder: (_, __) => Transform.scale(
                  scale: 0.8 + 0.4 * _animation.value,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.4),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.directions_bike,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _getRiderName(e.key) ?? 'Rider',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              if (orders.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${orders.length} งาน',
                    style: const TextStyle(color: Colors.white, fontSize: 9),
                  ),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }

  String? _getRiderName(int riderId) {
    try {
      return _allOrders.firstWhere((o) => o.riderId == riderId).riderName;
    } catch (_) {
      return 'R${riderId.toString().padLeft(2, '0')}';
    }
  }

  void _showRiderPopup(int riderId, List<OrderModel> orders) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.directions_bike, color: Colors.blue),
            const SizedBox(width: 8),
            Text('ไรเดอร์ ${_getRiderName(riderId) ?? ''}'),
          ],
        ),
        content: orders.isEmpty
            ? const Text('ไม่มีงาน')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('กำลังส่ง: ${orders.length} งาน'),
                  ...orders.map(
                    (o) =>
                        Text('• #${o.id} → ${o.receiverAddress.addressName}'),
                  ),
                ],
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }
}
