// lib/screens/work.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../config/api_endpoints.dart';
import '../config/orders_model.dart';

class WorkPage extends StatefulWidget {
  final int riderId;
  final OrderModel order;

  const WorkPage({super.key, required this.riderId, required this.order});

  @override
  State<WorkPage> createState() => _WorkPageState();
}

class _WorkPageState extends State<WorkPage>
    with SingleTickerProviderStateMixin {
  // ตัวแปรหลัก
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStreamSubscription;
  WebSocketChannel? _webSocketChannel;
  LatLng? _currentRiderPosition;
  late OrderModel _order;
  File? _orderImage;
  final ImagePicker _picker = ImagePicker();

  // Timer สำหรับ location tracking
  Timer? _locationBroadcastTimer;
  Timer? _httpBackupTimer;

  // UI State
  bool _isUploading = false;
  bool _gpsLoading = true;
  bool _gpsError = false;
  bool _isFallbackPosition = false;
  double _currentZoom = 13.0;

  // ระยะห่าง 20 เมตร
  bool _canTakePickupPhoto = false;
  bool _canTakeDeliveryPhoto = false;
  bool _canUploadPhoto = false;

  // Animation
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _order = widget.order;

    // Animation setup
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.repeat();

    // เริ่ม WebSocket และ GPS
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectWebSocket();
      _initializeGPS();
    });
  }

  @override
  void dispose() {
    _locationBroadcastTimer?.cancel();
    _httpBackupTimer?.cancel();
    _positionStreamSubscription?.cancel();
    _webSocketChannel?.sink.close();
    _animationController.dispose();
    super.dispose();
  }

  // WebSocket Connection
  void _connectWebSocket() async {
    try {
      final wsUrl = ApiEndpoints.riderWebSocketUrl(widget.riderId);
      debugPrint('Connecting WebSocket: $wsUrl');

      _webSocketChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _webSocketChannel!.stream.listen(
        (message) => debugPrint('WebSocket received: $message'),
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _webSocketChannel = null;
          if (mounted) setState(() {});
          _reconnectWebSocket();
        },
        onDone: () {
          debugPrint('WebSocket closed');
          _webSocketChannel = null;
          if (mounted) setState(() {});
          _reconnectWebSocket();
        },
        cancelOnError: true,
      );

      debugPrint('WebSocket connected');
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('WebSocket failed: $e');
      _webSocketChannel = null;
      if (mounted) setState(() {});
      _reconnectWebSocket();
    }
  }

  void _reconnectWebSocket() {
    if (!mounted) return;
    Future.delayed(const Duration(seconds: 5), () {
      if (_webSocketChannel == null) {
        _connectWebSocket();
      }
    });
  }

  // ส่ง location ทุก 5 วินาที
  void _startLocationBroadcast() {
    _locationBroadcastTimer?.cancel();
    _locationBroadcastTimer = Timer.periodic(const Duration(seconds: 5), (
      timer,
    ) {
      if (_currentRiderPosition == null || _webSocketChannel == null) return;
      final locationData = {
        'latitude': _currentRiderPosition!.latitude,
        'longitude': _currentRiderPosition!.longitude,
      };
      try {
        _webSocketChannel!.sink.add(json.encode(locationData));
        debugPrint('WebSocket sent: ${json.encode(locationData)}');
      } catch (e) {
        debugPrint('WebSocket send error: $e');
        _reconnectWebSocket();
      }
    });
  }

  // HTTP Backup ทุก 15 วินาที
  void _startHttpBackup() {
    _httpBackupTimer?.cancel();
    _httpBackupTimer = Timer.periodic(const Duration(seconds: 15), (
      timer,
    ) async {
      if (_currentRiderPosition == null) return;
      await _sendLocationToDatabase();
    });
  }

  Future<void> _sendLocationToDatabase() async {
    try {
      final response = await http
          .post(
            Uri.parse(ApiEndpoints.updateRiderLocation),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'riderId': widget.riderId,
              'latitude': _currentRiderPosition!.latitude,
              'longitude': _currentRiderPosition!.longitude,
            }),
          )
          .timeout(const Duration(seconds: 5));
      debugPrint('HTTP Backup: ${response.statusCode}');
    } catch (e) {
      debugPrint('HTTP Backup error: $e');
    }
  }

  // คำนวณระยะห่าง
  double _calculateDistance(LatLng from, LatLng to) {
    return Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
  }

  // อัปเดตสถานะระยะใกล้
  void _updateProximityStatus() {
    if (_currentRiderPosition == null) return;

    final pickupPoint = LatLng(
      _order.senderAddress.lat,
      _order.senderAddress.lng,
    );
    final deliveryPoint = LatLng(
      _order.receiverAddress.lat,
      _order.receiverAddress.lng,
    );

    final pickupDistance = _calculateDistance(
      _currentRiderPosition!,
      pickupPoint,
    );
    final deliveryDistance = _calculateDistance(
      _currentRiderPosition!,
      deliveryPoint,
    );

    final canTakePickup = pickupDistance <= 20.0 && _order.status == 2;
    final canTakeDelivery = deliveryDistance <= 20.0 && _order.status == 3;
    final canUpload =
        _orderImage != null &&
        ((_order.status == 2 && canTakePickup) ||
            (_order.status == 3 && canTakeDelivery));

    if (mounted) {
      setState(() {
        _canTakePickupPhoto = canTakePickup;
        _canTakeDeliveryPhoto = canTakeDelivery;
        _canUploadPhoto = canUpload;
      });
    }

    // แจ้งเตือนเมื่อเข้าใกล้
    if (canTakePickup && !_canTakePickupPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('คุณอยู่ใกล้จุดรับสินค้าแล้ว! ถ่ายรูปได้เลย'),
          backgroundColor: Colors.green,
        ),
      );
    }
    if (canTakeDelivery && !_canTakeDeliveryPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('คุณถึงจุดส่งแล้ว! ถ่ายรูปส่งสินค้าได้เลย'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // GPS Initialization
  Future<void> _initializeGPS() async {
    if (!mounted) return;
    setState(() => _gpsLoading = true);

    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final isLocationServiceEnabled =
            await Geolocator.isLocationServiceEnabled();
        if (!isLocationServiceEnabled) {
          if (attempt == 3) {
            _useFallbackPosition();
            _showGpsDisabledDialog();
            return;
          }
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }

        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) {
            if (attempt == 3) {
              _useFallbackPosition();
              _showGpsPermissionDialog();
              return;
            }
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }
          if (permission == LocationPermission.deniedForever) {
            _useFallbackPosition();
            _showGpsPermissionDialog();
            return;
          }
        }

        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        ).timeout(const Duration(seconds: 8));

        if (_isValidThailandPosition(position)) {
          if (mounted) {
            setState(() {
              _currentRiderPosition = LatLng(
                position.latitude,
                position.longitude,
              );
              _gpsLoading = false;
              _gpsError = false;
              _isFallbackPosition = false;
            });
            _updateProximityStatus(); // เรียกครั้งแรก
            _startLocationBroadcast();
            _startRealTimeTracking();
            _startHttpBackup();
            _fitMapToBounds();
          }
          return;
        }
      } catch (e) {
        debugPrint('GPS Attempt $attempt failed: $e');
      }
    }

    _useFallbackPosition();
  }

  bool _isValidThailandPosition(Position position) {
    return position.latitude >= 5.6 &&
        position.latitude <= 20.4 &&
        position.longitude >= 97.3 &&
        position.longitude <= 105.6;
  }

  void _useFallbackPosition() {
    if (!mounted) return;
    setState(() {
      _currentRiderPosition = const LatLng(16.18879290, 103.29831317);
      _gpsLoading = false;
      _gpsError = false;
      _isFallbackPosition = true;
    });
    _updateProximityStatus(); // เรียกแม้ใช้ fallback
    _startLocationBroadcast();
    _startRealTimeTracking();
    _startHttpBackup();
    _fitMapToBounds();
  }

  void _startRealTimeTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5, // อัปเดตทุก 5 เมตร
          ),
        ).listen(
          (Position position) {
            if (!_isValidThailandPosition(position) || !mounted) return;
            _currentRiderPosition = LatLng(
              position.latitude,
              position.longitude,
            );
            _isFallbackPosition = false;

            if (mounted) setState(() {});
            _updateProximityStatus(); // อัปเดตทุกครั้งที่มีตำแหน่งใหม่

            if (_mapController.camera.center.latitude !=
                    _currentRiderPosition!.latitude ||
                _mapController.camera.center.longitude !=
                    _currentRiderPosition!.longitude) {
              _mapController.move(_currentRiderPosition!, 16);
            }
          },
          onError: (e) {
            debugPrint('GPS stream error: $e');
            if (mounted) setState(() => _gpsError = true);
          },
        );
  }

  void _showGpsDisabledDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('GPS ปิดอยู่'),
        content: const Text('กรุณาเปิด Location Service'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openLocationSettings();
            },
            child: const Text('ตั้งค่า', style: TextStyle(color: Colors.green)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _useFallbackPosition();
            },
            child: const Text(
              'ใช้ตำแหน่งเริ่มต้น',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  void _showGpsPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('ต้องเปิด GPS'),
        content: const Text('กรุณาให้สิทธิ์ Location "While Using"'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openAppSettings();
            },
            child: const Text('ตั้งค่า', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
  }

  void _fitMapToBounds() {
    final points = <LatLng>[];
    if (_currentRiderPosition != null) points.add(_currentRiderPosition!);
    if (_order.senderAddress.lat != 0 && _order.senderAddress.lng != 0) {
      points.add(LatLng(_order.senderAddress.lat, _order.senderAddress.lng));
    }
    if (_order.receiverAddress.lat != 0 && _order.receiverAddress.lng != 0) {
      points.add(
        LatLng(_order.receiverAddress.lat, _order.receiverAddress.lng),
      );
    }

    if (points.isEmpty) {
      _mapController.move(const LatLng(16.18879290, 103.29831317), 13);
      return;
    }

    try {
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80)),
      );
    } catch (e) {
      _mapController.move(points.first, 13);
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 800,
      );
      if (pickedFile != null && mounted) {
        setState(() => _orderImage = File(pickedFile.path));
        _updateProximityStatus(); // อัปเดตปุ่มอัปโหลด
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _uploadPickupImage() async {
    if (_orderImage == null) return;
    if (mounted) setState(() => _isUploading = true);

    try {
      var request =
          http.MultipartRequest(
              'POST',
              Uri.parse(ApiEndpoints.uploadPickupImage),
            )
            ..fields['orderId'] = _order.id.toString()
            ..fields['riderId'] = widget.riderId.toString()
            ..files.add(
              await http.MultipartFile.fromPath(
                'productImage',
                _orderImage!.path,
              ),
            );

      final response = await request.send().timeout(
        const Duration(seconds: 10),
      );
      final responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final updatedOrder = OrderModel.fromJson(json.decode(responseData));
        if (mounted) {
          setState(() {
            _order = updatedOrder;
            _orderImage = null;
            _isUploading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('รับสินค้าเรียบร้อย'),
              backgroundColor: Colors.green,
            ),
          );
          _fitMapToBounds();
        }
      } else {
        throw Exception('อัปโหลดล้มเหลว: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _uploadDeliveryImage() async {
    if (_orderImage == null) return;
    if (mounted) setState(() => _isUploading = true);

    try {
      var request =
          http.MultipartRequest(
              'POST',
              Uri.parse(ApiEndpoints.uploadDeliveryImage),
            )
            ..fields['orderId'] = _order.id.toString()
            ..fields['riderId'] = widget.riderId.toString()
            ..files.add(
              await http.MultipartFile.fromPath(
                'productImage',
                _orderImage!.path,
              ),
            );

      final response = await request.send().timeout(
        const Duration(seconds: 10),
      );
      final responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final updatedOrder = OrderModel.fromJson(json.decode(responseData));
        if (mounted) {
          setState(() {
            _order = updatedOrder;
            _orderImage = null;
            _isUploading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ส่งสินค้าเรียบร้อย'),
              backgroundColor: Colors.green,
            ),
          );
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.pop(context);
          });
        }
      } else {
        throw Exception('อัปโหลดล้มเหลว: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPickup = _order.status == 2;
    final riderPos =
        _currentRiderPosition ?? const LatLng(16.18879290, 103.29831317);
    final isWebSocketConnected = _webSocketChannel != null;

    return PopScope(
      canPop: _order.status == 4,
      onPopInvoked: (didPop) {
        if (!didPop && _order.status != 4) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('งานยังไม่เสร็จ'),
              content: const Text('กรุณาดำเนินการส่งงานให้สำเร็จก่อนออก'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'ตกลง',
                    style: TextStyle(color: Colors.green),
                  ),
                ),
              ],
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('งาน: ${_order.receiverName}'),
          backgroundColor: _order.status >= 3 ? Colors.orange : Colors.green,
          automaticallyImplyLeading: false,
          actions: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: isWebSocketConnected ? Colors.green : Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wifi, size: 16, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    isWebSocketConnected ? 'Live' : 'Offline',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.my_location,
                color: _gpsError ? Colors.grey : Colors.white,
              ),
              onPressed: _gpsError || _gpsLoading
                  ? null
                  : () {
                      _mapController.move(riderPos, 16);
                      _currentZoom = 16;
                    },
              tooltip: 'ตำแหน่งปัจจุบัน',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fitMapToBounds,
              tooltip: 'รีเซ็ตมุมมอง',
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: _gpsLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _gpsError
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.location_off,
                            size: 64,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'ไม่สามารถดึงตำแหน่ง GPS ได้',
                            style: TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isFallbackPosition
                                ? 'ใช้ตำแหน่งเริ่มต้น'
                                : 'กรุณาตรวจสอบ GPS',
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _initializeGPS,
                            child: const Text('ลองใหม่'),
                          ),
                        ],
                      ),
                    )
                  : FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: riderPos,
                        initialZoom: _currentZoom,
                        minZoom: 5,
                        maxZoom: 18,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.delivery_app',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: riderPos,
                              width: 60,
                              height: 60,
                              child: AnimatedBuilder(
                                animation: _pulseAnimation,
                                builder: (context, child) {
                                  return Transform.scale(
                                    scale: _pulseAnimation.value,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.9),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.blue.withOpacity(0.4),
                                            blurRadius: 12,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.directions_bike,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (_order.senderAddress.lat != 0 &&
                                _order.senderAddress.lng != 0)
                              Marker(
                                point: LatLng(
                                  _order.senderAddress.lat,
                                  _order.senderAddress.lng,
                                ),
                                width: 50,
                                height: 50,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: _order.status >= 3
                                        ? Colors.green
                                        : Colors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.storefront,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                            if (_order.receiverAddress.lat != 0 &&
                                _order.receiverAddress.lng != 0)
                              Marker(
                                point: LatLng(
                                  _order.receiverAddress.lat,
                                  _order.receiverAddress.lng,
                                ),
                                width: 50,
                                height: 50,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.9),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.home,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
            ),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isPickup
                                      ? 'รับจาก: ${_order.senderAddress.addressName}'
                                      : 'ส่งให้: ${_order.receiverName}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  _order.productDetails,
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _order.statusButtonColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _order.statusText,
                              style: TextStyle(
                                color: _order.statusButtonTextColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _orderImage != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    _orderImage!,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : (_order.status >= 3 &&
                                        _order.pickupImageUrl != null
                                    ? _buildImageWidget(
                                        _order.pickupImageUrl!,
                                        'รับแล้ว',
                                      )
                                    : (_order.status == 4 &&
                                              _order.deliveryImageUrl != null
                                          ? _buildImageWidget(
                                              _order.deliveryImageUrl!,
                                              'ส่งแล้ว',
                                            )
                                          : _buildImageWidget(
                                              _order.productImageUrl,
                                              'สินค้า',
                                            ))),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'รหัส: ${_order.id.toString().padLeft(5, '0')}',
                                ),
                                Text(
                                  isPickup
                                      ? 'ระยะจุดรับ: ${_calculateDistance(riderPos, LatLng(_order.senderAddress.lat, _order.senderAddress.lng)).toStringAsFixed(1)} ม.'
                                      : 'ระยะจุดส่ง: ${_calculateDistance(riderPos, LatLng(_order.receiverAddress.lat, _order.receiverAddress.lng)).toStringAsFixed(1)} ม.',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: (_canTakePickupPhoto || _canTakeDeliveryPhoto)
                        ? _pickImage
                        : null,
                    icon: const Icon(Icons.camera_alt, size: 20),
                    label: Text(
                      _order.status == 2
                          ? (_canTakePickupPhoto
                                ? 'ถ่ายรูปรับ'
                                : 'เข้าใกล้จุดรับก่อน')
                          : (_canTakeDeliveryPhoto
                                ? 'ถ่ายรูปส่ง'
                                : 'เข้าใกล้จุดส่งก่อน'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          (_canTakePickupPhoto || _canTakeDeliveryPhoto)
                          ? Colors.orange
                          : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _canUploadPhoto
                        ? (_order.status == 2
                              ? _uploadPickupImage
                              : _uploadDeliveryImage)
                        : null,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.upload, size: 20),
                    label: Text(_isUploading ? 'กำลังส่ง...' : 'อัปโหลด'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _canUploadPhoto
                          ? Colors.green
                          : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: _order.status == 4
            ? FloatingActionButton.extended(
                onPressed: () {
                  _locationBroadcastTimer?.cancel();
                  _httpBackupTimer?.cancel();
                  _webSocketChannel?.sink.close();
                  Navigator.pop(context);
                },
                backgroundColor: Colors.green,
                icon: const Icon(Icons.check),
                label: const Text('เสร็จสิ้น'),
              )
            : null,
      ),
    );
  }

  Widget _buildImageWidget(String imageUrl, String label) {
    if (imageUrl.isEmpty || imageUrl == 'assets/default_product.png') {
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image, color: Colors.grey.shade400, size: 28),
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ],
        ),
      );
    }

    final displayUrl = imageUrl.startsWith('http')
        ? imageUrl
        : '${ApiEndpoints.baseUrl}/$imageUrl';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: displayUrl,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              color: Colors.grey.shade200,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_not_supported, color: Colors.grey, size: 28),
                  Text(
                    label,
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
