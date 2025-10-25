import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import '../config/api_endpoints.dart';
import 'home.dart';

class RiderTrackingScreen extends StatefulWidget {
  final OrderModel order;
  final int userId;
  final String userName;
  final String phone;

  const RiderTrackingScreen({
    super.key,
    required this.order,
    required this.userId,
    required this.userName,
    required this.phone,
  });

  @override
  State<RiderTrackingScreen> createState() => _RiderTrackingScreenState();
}

class _RiderTrackingScreenState extends State<RiderTrackingScreen>
    with SingleTickerProviderStateMixin {
  late final MapController _mapController;
  WebSocketChannel? _channel;
  LatLng? _riderLocation;
  bool _isLoading = true;
  bool _hasError = false;
  bool _mapIsReady = false;
  String _errorMessage = '';
  late AnimationController _animationController;
  late Animation<double> _animation;

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

    _fetchInitialRiderLocation();
    _connectWebSocket();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _animationController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _fetchInitialRiderLocation() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiEndpoints.baseUrl}/get-rider-location/${widget.order.riderId}',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['latitude'] != null && data['longitude'] != null) {
          final lat = double.parse(data['latitude'].toString());
          final lng = double.parse(data['longitude'].toString());

          if (mounted) {
            setState(() {
              _riderLocation = LatLng(lat, lng);
              _isLoading = false;
              _hasError = false;
            });

            // รอ map ready ก่อน move
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _mapIsReady && _riderLocation != null) {
                _safeMoveToLocation(_riderLocation!);
              }
            });
          }
        } else {
          _setError('ไม่พบตำแหน่งไรเดอร์');
        }
      } else {
        _setError('ไม่สามารถโหลดตำแหน่งไรเดอร์ได้');
      }
    } catch (e) {
      _setError('เกิดข้อผิดพลาดในการโหลด: $e');
    }
  }

  void _connectWebSocket() {
    try {
      final wsUrl = 'ws://10.0.2.2:3001/${widget.order.riderId}';
      debugPrint('Connecting WebSocket: $wsUrl');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _channel!.stream.listen(
        (message) {
          try {
            final data = json.decode(message);
            final lat = double.parse(data['latitude'].toString());
            final lng = double.parse(data['longitude'].toString());
            final newLocation = LatLng(lat, lng);

            if (mounted) {
              setState(() {
                _riderLocation = newLocation;
                _isLoading = false;
                _hasError = false;
              });

              // ใช้ PostFrameCallback เพื่อหลีกเลี่ยง setState ใน build
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _mapIsReady && _riderLocation != null) {
                  _safeMoveToLocation(_riderLocation!);
                }
              });
              debugPrint('Rider location updated: $lat, $lng');
            }
          } catch (e) {
            debugPrint('WebSocket message parse error: $e');
          }
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          if (mounted) {
            setState(() {
              _hasError = true;
              _isLoading = false;
            });
          }
        },
        onDone: () {
          debugPrint('WebSocket closed - Reconnecting...');
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) _connectWebSocket();
          });
        },
      );

      debugPrint('WebSocket connected successfully');
    } catch (e) {
      debugPrint('WebSocket connection failed: $e');
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _connectWebSocket();
      });
    }
  }

  void _safeMoveToLocation(LatLng location) {
    try {
      if (_mapIsReady) {
        _mapController.move(location, 15.0);
      }
    } catch (e) {
      debugPrint('Map move error: $e');
    }
  }

  void _setError(String message) {
    if (mounted) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF8329B4),
        foregroundColor: Colors.white,
        title: const Text(
          'ติดตามไรเดอร์',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Center(
              child: Text(
                'ออเดอร์ #${widget.order.id.toString().padLeft(5, '0')}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
          ? _buildErrorWidget()
          : Column(
              children: [
                _buildOrderInfo(),
                Expanded(
                  child: Stack(
                    children: [
                      // ใช้ Builder เพื่อหลีกเลี่ยง setState ใน build
                      Builder(
                        builder: (context) {
                          // ตรวจสอบ map ready หลัง build เสร็จ
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && !_mapIsReady) {
                              setState(() => _mapIsReady = true);
                              if (_riderLocation != null) {
                                _safeMoveToLocation(_riderLocation!);
                              }
                            }
                          });
                          return _buildMap();
                        },
                      ),
                      // Map Status Indicator
                      if (!_mapIsReady)
                        Positioned(
                          top: 20,
                          left: 20,
                          child: Material(
                            color: Colors.blue,
                            borderRadius: const BorderRadius.all(
                              Radius.circular(20),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'กำลังโหลดแผนที่...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      // Connection Status
                      Positioned(
                        top: 20,
                        right: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _channel != null ? Colors.green : Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _channel != null ? Icons.wifi : Icons.wifi_off,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _channel != null ? 'Live' : 'Offline',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _hasError = false;
                });
                _fetchInitialRiderLocation();
                _connectWebSocket();
              },
              child: const Text('ลองใหม่'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderInfo() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusRow(),
          const SizedBox(height: 16),
          _buildImageRow(),
          const SizedBox(height: 16),
          _buildLocationRow(
            'จุดรับสินค้า',
            widget.order.senderAddress.addressDetail,
          ),
          const SizedBox(height: 12),
          _buildLocationRow(
            'จุดส่งสินค้า',
            widget.order.receiverAddress.addressDetail,
          ),
          if (_riderLocation != null) ...[
            const SizedBox(height: 12),
            _buildRiderLocationRow(),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ส่งให้: ${widget.order.receiverName}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                widget.order.receiverPhone,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: widget.order.statusButtonColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            widget.order.statusText,
            style: TextStyle(
              color: widget.order.statusButtonTextColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageRow() {
    List<Widget> images = [];
    if (widget.order.productImageUrl.isNotEmpty) {
      images.add(_buildImageWidget(widget.order.productImageUrl, 'สินค้า'));
    }
    if (widget.order.pickupImageUrl != null &&
        widget.order.pickupImageUrl!.isNotEmpty) {
      images.add(_buildImageWidget(widget.order.pickupImageUrl!, 'รับสินค้า'));
    }
    if (widget.order.deliveryImageUrl != null &&
        widget.order.deliveryImageUrl!.isNotEmpty) {
      images.add(
        _buildImageWidget(widget.order.deliveryImageUrl!, 'ส่งสินค้า'),
      );
    }
    return Wrap(spacing: 12, runSpacing: 12, children: images);
  }

  Widget _buildImageWidget(String imageUrl, String label) {
    final displayUrl = imageUrl.startsWith('http')
        ? imageUrl
        : '${ApiEndpoints.baseUrl}/$imageUrl';

    return Column(
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: displayUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Colors.grey.shade200,
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey.shade200,
                child: const Icon(
                  Icons.image_not_supported,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLocationRow(String label, String addressDetail) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(Icons.location_pin, color: Colors.red, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                addressDetail.isEmpty || addressDetail == 'ไม่มีข้อมูล'
                    ? '$label ไม่พร้อมใช้งาน'
                    : addressDetail,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRiderLocationRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(6),
          ),
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Transform.scale(
                scale: 0.8 + 0.4 * _animation.value,
                child: Icon(
                  Icons.directions_bike,
                  color: Colors.blue,
                  size: 18,
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ตำแหน่งไรเดอร์ปัจจุบัน',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                _riderLocation != null
                    ? 'กำลังเคลื่อนที่ (${_riderLocation!.latitude.toStringAsFixed(4)}, ${_riderLocation!.longitude.toStringAsFixed(4)})'
                    : 'กำลังค้นหาตำแหน่ง...',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMap() {
    final centerPoint =
        _riderLocation ??
        (widget.order.senderAddress.lat != 0 &&
                widget.order.senderAddress.lng != 0
            ? LatLng(
                widget.order.senderAddress.lat,
                widget.order.senderAddress.lng,
              )
            : const LatLng(16.18879290, 103.29831317));

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: centerPoint,
        initialZoom: 14.0,
        minZoom: 5,
        maxZoom: 18,
      ),
      children: [
        // 🔥 แก้ปัญหา Access Blocked - ใช้ Thunderforest (ฟรี!)
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.example.app',
        ),
        // 🔥 หรือใช้ CartoDB (ฟรี + เร็ว!)
        /*
      TileLayer(
        urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
        subdomains: const ['a', 'b', 'c', 'd'],
        userAgentPackageName: 'com.example.app',
      ),
      */
        MarkerLayer(
          markers: [
            // Rider marker
            if (_riderLocation != null)
              Marker(
                point: _riderLocation!,
                width: 50,
                height: 50,
                child: AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 0.8 + 0.4 * _animation.value,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.3),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.directions_bike,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    );
                  },
                ),
              ),
            // Pickup marker
            if (widget.order.senderAddress.lat != 0 &&
                widget.order.senderAddress.lng != 0)
              Marker(
                point: LatLng(
                  widget.order.senderAddress.lat,
                  widget.order.senderAddress.lng,
                ),
                width: 40,
                height: 40,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.storefront,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            // Delivery marker
            if (widget.order.receiverAddress.lat != 0 &&
                widget.order.receiverAddress.lng != 0)
              Marker(
                point: LatLng(
                  widget.order.receiverAddress.lat,
                  widget.order.receiverAddress.lng,
                ),
                width: 40,
                height: 40,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.home, color: Colors.white, size: 18),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
