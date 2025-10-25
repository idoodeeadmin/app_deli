import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/api_endpoints.dart';
import 'home.dart'; // นำเข้า OrderModel และ AddressModel
import 'login.dart'; // นำเข้า LoginPage
import 'rider_tracking.dart'; // เพิ่ม import สำหรับ RiderTrackingScreen
import 'allwork.dart';

class ReceiveScreen extends StatefulWidget {
  final String phone;
  final int userId;
  final String userName;

  const ReceiveScreen({
    Key? key,
    required this.phone,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  _ReceiveScreenState createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  bool _isLoading = true;
  String _error = '';
  List<OrderModel> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool refresh = false}) async {
    if (!refresh) setState(() => _isLoading = true);
    try {
      final ordersResponse = await http
          .get(Uri.parse('${ApiEndpoints.getOrdersReceiver}/${widget.userId}'))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('การโหลดออเดอร์หมดเวลา'),
          );
      debugPrint('Orders response (receiver): ${ordersResponse.body}');
      if (ordersResponse.statusCode != 200) {
        throw Exception(
          'ไม่สามารถโหลดออเดอร์ได้: ${ordersResponse.statusCode} - ${ordersResponse.body}',
        );
      }
      final List<dynamic> ordersJson = json.decode(ordersResponse.body);
      final fetchedOrders = ordersJson.map((e) {
        debugPrint(
          'Parsing order ID=${e['id']}: senderAddress=${e['senderAddress']}, receiverAddress=${e['receiverAddress']}',
        );
        return OrderModel.fromJson(e);
      }).toList();
      debugPrint(
        'Fetched receiver orders: ${fetchedOrders.map((o) => 'ID=${o.id}, status=${o.status}, senderAddress=${o.senderAddress.addressDetail}, receiverAddress=${o.receiverAddress.addressDetail}, product=${o.productImageUrl}, pickup=${o.pickupImageUrl}, delivery=${o.deliveryImageUrl}').join('\n')}',
      );

      setState(() {
        _orders = fetchedOrders;
        _error = '';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'เกิดข้อผิดพลาด: $e';
        _isLoading = false;
      });
      debugPrint('Load data error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Text(_error, style: const TextStyle(color: Colors.red)),
            )
          : RefreshIndicator(
              onRefresh: () => _loadData(refresh: true),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildSearchField(),
                    const SizedBox(height: 20),
                    _buildHeader(),
                    const SizedBox(height: 20),
                    ..._orders
                        .map((order) => _OrderCard(order: order))
                        .toList(),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFFF3F3F3),
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'สวัสดี, คุณ ${widget.userName}',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            widget.phone,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
      actions: [
        _buildCircleIcon(
          Icons.map_outlined, // 🔥 Map กลาง
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AllWorkMapScreen(userId: widget.userId),
              ),
            );
          },
        ),
        _buildCircleIcon(Icons.location_on_outlined), // 🔥 Location ขวา
        _buildCircleIcon(
          Icons.logout, // 🔥 Logout สุดขวา
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LoginPage()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCircleIcon(IconData icon, {VoidCallback? onPressed}) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(icon, size: 20, color: Colors.black),
          onPressed: onPressed,
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const TextField(
        decoration: InputDecoration(
          hintText: 'ค้นหา',
          border: InputBorder.none,
          prefixIcon: Icon(Icons.search, color: Colors.grey),
          prefixIconConstraints: BoxConstraints(minWidth: 30),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'รายการที่รับ',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _OrderCard({required OrderModel order}) {
    Widget imagesSection = Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'สินค้า',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _buildProductImageWidget(order),
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
        if (order.status >= 3 &&
            order.pickupImageUrl != null &&
            order.pickupImageUrl!.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'รับ',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildPickupImageWidget(order),
                ),
              ),
            ],
          ),
        const SizedBox(width: 8),
        if (order.status == 4 &&
            order.deliveryImageUrl != null &&
            order.deliveryImageUrl!.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ส่ง',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildDeliveryImageWidget(order),
                ),
              ),
            ],
          ),
      ],
    );

    // ห่อ Card ด้วย GestureDetector เพื่อให้กดได้เมื่อมี riderId และ status >= 2
    return GestureDetector(
      onTap: order.riderId != null && order.status >= 2
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RiderTrackingScreen(
                    order: order,
                    userId: widget.userId,
                    userName: widget.userName,
                    phone: widget.phone,
                  ),
                ),
              );
            }
          : null, // ไม่ให้กดได้ถ้าไม่มี riderId หรือ status < 2
      child: Card(
        margin: const EdgeInsets.only(bottom: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: order.riderId != null && order.status >= 2
            ? Colors.white
            : Colors
                  .grey
                  .shade200, // เปลี่ยนสีพื้นหลังเพื่อบอกว่าไม่สามารถกดได้
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ส่งให้: ${order.receiverName}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        order.receiverPhone,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: order.statusButtonColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      order.statusText,
                      style: TextStyle(
                        color: order.statusButtonTextColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'สินค้า: ${order.productDetails.isEmpty ? "ไม่มีรายละเอียด" : order.productDetails}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'รหัสออเดอร์: ${order.id.toString().padLeft(5, '0')}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: imagesSection,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (order.status == 1 || order.status == 2) ...[
                          _buildLocation(
                            Icons.storefront_outlined,
                            order.senderAddress.addressDetail.isEmpty ||
                                    order.senderAddress.addressDetail ==
                                        'ไม่มีข้อมูล'
                                ? 'ที่อยู่ผู้ส่งไม่พร้อมใช้งาน'
                                : order.senderAddress.addressDetail,
                          ),
                          const SizedBox(height: 4),
                          _buildLocation(
                            Icons.location_on_outlined,
                            order.receiverAddress.addressDetail.isEmpty ||
                                    order.receiverAddress.addressDetail ==
                                        'ไม่มีข้อมูล'
                                ? 'ที่อยู่ผู้รับไม่พร้อมใช้งาน'
                                : order.receiverAddress.addressDetail,
                          ),
                        ],
                        if (order.status == 3) ...[
                          _buildLocation(
                            Icons.location_on,
                            'ไรเดอร์รับสินค้าแล้ว กำลังเดินทางไปส่ง',
                            iconColor: const Color(0xFF8329B4),
                            textColor: const Color(0xFF8329B4),
                          ),
                        ],
                        if (order.status == 4) ...[
                          _buildLocation(
                            Icons.location_on,
                            'ไรเดอร์นำส่งสินค้าแล้ว',
                            iconColor: const Color(0xFF717171),
                            textColor: const Color(0xFF717171),
                          ),
                        ],
                        if (order.riderId != null && order.status >= 2) ...[
                          const SizedBox(height: 4),
                          _buildLocation(
                            Icons.directions_bike,
                            'ติดตามตำแหน่งไรเดอร์',
                            iconColor: Colors.blue,
                            textColor: Colors.blue,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductImageWidget(OrderModel order) {
    if (order.productImageUrl.isEmpty ||
        !order.productImageUrl.startsWith('http')) {
      debugPrint('Using default image for order ${order.id}');
      return Image.asset(
        'assets/default_product.png',
        fit: BoxFit.cover,
        width: 60,
        height: 60,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Asset image load error: $error');
          return Container(
            width: 60,
            height: 60,
            color: Colors.grey.shade300,
            child: const Icon(Icons.image_not_supported, color: Colors.grey),
          );
        },
      );
    } else {
      return CachedNetworkImage(
        imageUrl: order.productImageUrl,
        fit: BoxFit.cover,
        width: 60,
        height: 60,
        placeholder: (context, url) =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorWidget: (context, url, error) {
          debugPrint('Network image load error: $error, URL: $url');
          return Image.asset(
            'assets/default_product.png',
            fit: BoxFit.cover,
            width: 60,
            height: 60,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('Asset image load error: $error');
              return Container(
                width: 60,
                height: 60,
                color: Colors.grey.shade300,
                child: const Icon(
                  Icons.image_not_supported,
                  color: Colors.grey,
                ),
              );
            },
          );
        },
      );
    }
  }

  Widget _buildPickupImageWidget(OrderModel order) {
    if (order.pickupImageUrl == null ||
        order.pickupImageUrl!.isEmpty ||
        !order.pickupImageUrl!.startsWith('http')) {
      debugPrint('Using default pickup image for order ${order.id}');
      return Image.asset(
        'assets/default_product.png',
        fit: BoxFit.cover,
        width: 60,
        height: 60,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Asset pickup image load error: $error');
          return Container(
            width: 60,
            height: 60,
            color: Colors.grey.shade300,
            child: const Icon(Icons.image_not_supported, color: Colors.grey),
          );
        },
      );
    } else {
      return CachedNetworkImage(
        imageUrl: order.pickupImageUrl!,
        fit: BoxFit.cover,
        width: 60,
        height: 60,
        placeholder: (context, url) => const SizedBox(
          width: 60,
          height: 60,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        errorWidget: (context, url, error) {
          debugPrint('Pickup image load error: $error, URL: $url');
          return Image.asset(
            'assets/default_product.png',
            fit: BoxFit.cover,
            width: 60,
            height: 60,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('Asset pickup image load error: $error');
              return Container(
                width: 60,
                height: 60,
                color: Colors.grey.shade300,
                child: const Icon(
                  Icons.image_not_supported,
                  color: Colors.grey,
                ),
              );
            },
          );
        },
      );
    }
  }

  Widget _buildDeliveryImageWidget(OrderModel order) {
    if (order.deliveryImageUrl == null ||
        order.deliveryImageUrl!.isEmpty ||
        !order.deliveryImageUrl!.startsWith('http')) {
      debugPrint('Using default delivery image for order ${order.id}');
      return Image.asset(
        'assets/default_product.png',
        fit: BoxFit.cover,
        width: 60,
        height: 60,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Asset delivery image load error: $error');
          return Container(
            width: 60,
            height: 60,
            color: Colors.grey.shade300,
            child: const Icon(Icons.image_not_supported, color: Colors.grey),
          );
        },
      );
    } else {
      return CachedNetworkImage(
        imageUrl: order.deliveryImageUrl!,
        fit: BoxFit.cover,
        width: 60,
        height: 60,
        placeholder: (context, url) => const SizedBox(
          width: 60,
          height: 60,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        errorWidget: (context, url, error) {
          debugPrint('Delivery image load error: $error, URL: $url');
          return Image.asset(
            'assets/default_product.png',
            fit: BoxFit.cover,
            width: 60,
            height: 60,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('Asset delivery image load error: $error');
              return Container(
                width: 60,
                height: 60,
                color: Colors.grey.shade300,
                child: const Icon(
                  Icons.image_not_supported,
                  color: Colors.grey,
                ),
              );
            },
          );
        },
      );
    }
  }

  Widget _buildLocation(
    IconData icon,
    String text, {
    Color iconColor = Colors.grey,
    Color textColor = Colors.black,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: textColor, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
