// lib/screens/rider_home.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'login.dart';
import 'work.dart';
import '../config/api_endpoints.dart';
import '../config/orders_model.dart';

class RiderHome extends StatefulWidget {
  final String phone;
  final int userId;
  final String userName;

  const RiderHome({
    super.key,
    required this.phone,
    required this.userId,
    required this.userName,
  });

  @override
  State<RiderHome> createState() => _RiderHomeState();
}

class _RiderHomeState extends State<RiderHome> {
  bool _isLoading = true;
  String _error = '';
  List<OrderModel> _orders = [];
  Timer? _pollingTimer;
  int _previousOrderCount = 0;

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      _loadOrders(refresh: true);
    });
  }

  Future<void> _loadOrders({bool refresh = false}) async {
    if (!refresh && mounted) setState(() => _isLoading = true);
    try {
      final response = await http
          .get(Uri.parse('${ApiEndpoints.baseUrl}/get-orders/available'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 && mounted) {
        final List<dynamic> ordersJson = json.decode(response.body);
        final fetchedOrders = ordersJson
            .map((e) => OrderModel.fromJson(e))
            .toList();

        // Debug: แสดงข้อมูลดิบ
        debugPrint('Fetched ${fetchedOrders.length} orders from API');
        for (var o in fetchedOrders) {
          debugPrint(
            'Order ${o.id}: riderId = ${o.riderId}, status = ${o.status}',
          );
        }

        // แก้บัค: กรองงานที่ยังไม่มี rider (รองรับทั้ง null และ 0)
        final availableOrders = fetchedOrders
            .where((o) => o.riderId == 0)
            .toList();

        debugPrint('Available orders: ${availableOrders.length}');

        if (mounted) {
          setState(() {
            _orders = availableOrders;
            _error = '';
            _isLoading = false;
          });

          // แจ้งเตือนเมื่อมีงานใหม่
          if (_orders.length > _previousOrderCount && _previousOrderCount > 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'มีงานใหม่ ${_orders.length - _previousOrderCount} รายการ!',
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          _previousOrderCount = _orders.length;
        }
      } else {
        throw Exception('โหลดออเดอร์ล้มเหลว: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Load orders error: $e');
      if (mounted) {
        setState(() {
          _error = 'เกิดข้อผิดพลาด: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _acceptOrder(OrderModel order) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiEndpoints.baseUrl}/accept-order'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'orderId': order.id, 'riderId': widget.userId}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 && mounted) {
        final updatedOrder = OrderModel.fromJson(json.decode(response.body));
        setState(() {
          _orders.removeWhere((o) => o.id == order.id);
          _previousOrderCount = _orders.length;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('รับงานสำเร็จ!'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                WorkPage(riderId: widget.userId, order: updatedOrder),
          ),
        );
      } else {
        throw Exception('รับงานล้มเหลว: ${response.body}');
      }
    } catch (e) {
      debugPrint('Accept order error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('รับงานล้มเหลว: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _loadOrders(refresh: true),
        backgroundColor: Colors.orange,
        child: const Icon(Icons.refresh, color: Colors.white),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_error, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _loadOrders(refresh: true),
                      child: const Text('ลองใหม่'),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () => _loadOrders(refresh: true),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'รายการที่รอรับ',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_orders.length} งาน',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_orders.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.only(top: 50),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.inventory_2_outlined,
                                    size: 64,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'ไม่มีออเดอร์ที่รอรับ',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ..._orders.map((order) => _buildOrderCard(order)),
                      ],
                    ),
                  ),
                ),
              ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildBottomNavItem(Icons.send, 'ส่งสินค้า', isActive: false),
            _buildBottomNavItem(Icons.inventory, 'รับสินค้า', isActive: true),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'สวัสดี, ไรเดอร์ ${widget.userName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.phone,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.place, size: 24),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginPage()),
              ),
              icon: const Icon(Icons.exit_to_app, size: 24),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOrderCard(OrderModel order) {
    String getDisplayAddress(
      String name,
      String detail,
      double lat,
      double lng,
    ) {
      if (detail.isNotEmpty) return '$name - $detail';
      if (name.isNotEmpty) return name;
      if (lat != 0.0 || lng != 0.0)
        return 'พิกัด: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
      return 'ไม่ระบุที่อยู่';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ส่งให้: ${order.receiverName}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Phone: ${order.receiverPhone}',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
              ElevatedButton(
                onPressed: () => _acceptOrder(order),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black54,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'รับงาน',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'สินค้า: ${order.productDetails.isEmpty ? "ไม่มีรายละเอียด" : order.productDetails}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: order.statusButtonColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              order.statusText,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: order.productImageUrl.startsWith('http')
                    ? CachedNetworkImage(
                        imageUrl: order.productImageUrl,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            const CircularProgressIndicator(),
                        errorWidget: (_, __, ___) => Image.asset(
                          'assets/default_product.png',
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Image.asset(
                        order.productImageUrl,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAddressRow(
                      Icons.location_on,
                      Colors.green,
                      'จุดรับ:',
                      getDisplayAddress(
                        order.senderAddress.addressName,
                        order.senderAddress.addressDetail,
                        order.senderAddress.lat,
                        order.senderAddress.lng,
                      ),
                    ),
                    const SizedBox(height: 5),
                    _buildAddressRow(
                      Icons.location_on,
                      Colors.red,
                      'จุดส่ง:',
                      getDisplayAddress(
                        order.receiverAddress.addressName,
                        order.receiverAddress.addressDetail,
                        order.receiverAddress.lat,
                        order.receiverAddress.lng,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'เลขออเดอร์: ${order.id.toString().padLeft(5, '0')}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressRow(
    IconData icon,
    Color color,
    String label,
    String text,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 5),
        Expanded(
          child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _buildBottomNavItem(
    IconData icon,
    String label, {
    bool isActive = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24, color: isActive ? Colors.black : Colors.grey),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? Colors.black : Colors.grey,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
