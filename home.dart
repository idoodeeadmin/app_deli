import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dotted_border/dotted_border.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as path;
import 'login.dart'; // Assumed to exist
import 'rider_tracking.dart'; // Assumed to exist
import '../config/api_endpoints.dart'; // Assumed to exist
import 'receive.dart'; // Assumed to exist
import 'allworksender.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rider App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const LoginPage(),
    );
  }
}

// ===========================
// DATA MODELS
// ===========================
class AddressModel {
  final int id;
  final String addressName;
  final String addressDetail;
  final double lat;
  final double lng;

  AddressModel({
    required this.id,
    required this.addressName,
    required this.addressDetail,
    required this.lat,
    required this.lng,
  });

  factory AddressModel.fromJson(Map<String, dynamic> json) {
    return AddressModel(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      addressName: json['address_name']?.toString() ?? '',
      addressDetail: json['address_detail']?.toString() ?? '',
      lat: double.tryParse(json['latitude']?.toString() ?? '') ?? 0.0,
      lng: double.tryParse(json['longitude']?.toString() ?? '') ?? 0.0,
    );
  }

  @override
  String toString() => addressName;
}

class OrderModel {
  final int id;
  final int? riderId;
  final String? riderName;
  final String receiverName;
  final String receiverPhone;
  final String productDetails;
  String productImageUrl;
  String? pickupImageUrl;
  String? deliveryImageUrl;
  int status;
  final AddressModel senderAddress;
  final AddressModel receiverAddress;

  OrderModel({
    required this.id,
    required this.riderId,
    required this.receiverName,
    required this.riderName,
    required this.receiverPhone,
    required this.productDetails,
    required this.productImageUrl,
    this.pickupImageUrl,
    this.deliveryImageUrl,
    this.status = 1,
    required this.senderAddress,
    required this.receiverAddress,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    String imageUrl = json['product_image_url']?.toString() ?? '';
    if (imageUrl.isEmpty) {
      imageUrl = 'assets/default_product.png';
    }
    final productDetails = json['product_details']?.toString() ?? '';

    debugPrint(
      'Order ${json['id']}: product_details=$productDetails, image_url=$imageUrl',
    );
    return OrderModel(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      riderId: json['rider_id'],
      riderName: json['riderName'] ?? json['rider_name'] ?? null,
      receiverName: json['receiverName']?.toString() ?? 'ไม่ระบุชื่อ',
      receiverPhone: json['receiverPhone']?.toString() ?? '',
      productDetails: productDetails,
      productImageUrl: imageUrl,
      pickupImageUrl: json['pickup_image_url']?.toString(),
      deliveryImageUrl: json['delivery_image_url']?.toString(),
      status: int.tryParse(json['status']?.toString() ?? '') ?? 1,
      senderAddress: json['senderAddress'] != null
          ? AddressModel.fromJson(json['senderAddress'])
          : AddressModel(
              id: 0,
              addressName: 'ไม่ระบุ',
              addressDetail: 'ไม่มีข้อมูล',
              lat: 0,
              lng: 0,
            ),
      receiverAddress: json['receiverAddress'] != null
          ? AddressModel.fromJson(json['receiverAddress'])
          : AddressModel(
              id: 0,
              addressName: 'ไม่ระบุ',
              addressDetail: 'ไม่มีข้อมูล',
              lat: 0,
              lng: 0,
            ),
    );
  }

  String get statusText {
    switch (status) {
      case 1:
        return 'รอไรเดอร์มารับสินค้า';
      case 2:
        return 'ไรเดอร์รับงาน (กำลังเดินทางมารับสินค้า)';
      case 3:
        return 'ไรเดอร์รับสินค้าแล้วและกำลังเดินทางไปส่ง';
      case 4:
        return 'ไรเดอร์นำส่งสินค้าแล้ว';
      default:
        return 'ไม่ทราบสถานะ';
    }
  }

  Color get statusButtonColor {
    switch (status) {
      case 1:
        return const Color(0xFFFFFBE9);
      case 2:
        return const Color(0xFFF0FFEE);
      case 3:
        return const Color(0xFFF7E9FF);
      case 4:
        return Colors.grey.shade300;
      default:
        return Colors.grey.shade100;
    }
  }

  Color get statusButtonTextColor {
    switch (status) {
      case 1:
        return const Color(0xFF966810);
      case 2:
        return const Color(0xFF22A422);
      case 3:
        return const Color(0xFF8329B4);
      case 4:
        return Colors.black;
      default:
        return Colors.black;
    }
  }
}

// ===========================
// HOME SCREEN
// ===========================
class HomeScreen extends StatefulWidget {
  final String phone;
  final int userId;
  final String userName;

  const HomeScreen({
    super.key,
    required this.phone,
    required this.userId,
    required this.userName,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      SenderHome(
        phone: widget.phone,
        userId: widget.userId,
        userName: widget.userName,
      ),
      ReceiveScreen(
        phone: widget.phone,
        userId: widget.userId,
        userName: widget.userName,
      ),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildBottomNavBar() {
    return BottomAppBar(
      color: Colors.white,
      elevation: 4,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavBarItem(
            icon: Icons.send_outlined,
            label: 'ส่งสินค้า',
            isActive: _selectedIndex == 0,
            onTap: () => _onItemTapped(0),
          ),
          _NavBarItem(
            icon: Icons.history,
            label: 'รับสินค้า',
            isActive: _selectedIndex == 1,
            onTap: () => _onItemTapped(1),
          ),
        ],
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.isActive,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? Colors.black : Colors.grey;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class SenderHome extends StatefulWidget {
  final String phone;
  final int userId;
  final String userName;

  const SenderHome({
    Key? key,
    required this.phone,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  _SenderHomeState createState() => _SenderHomeState();
}

class _SenderHomeState extends State<SenderHome> {
  bool _isLoading = true;
  String _error = '';
  List<AddressModel> _senderAddresses = [];
  List<OrderModel> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool refresh = false}) async {
    if (!refresh) setState(() => _isLoading = true);
    try {
      final addrResponse = await http
          .get(Uri.parse('${ApiEndpoints.getAddresses}/${widget.userId}'))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('การโหลดที่อยู่หมดเวลา'),
          );
      if (addrResponse.statusCode != 200) {
        throw Exception(
          'ไม่สามารถโหลดที่อยู่ได้: ${addrResponse.statusCode} - ${addrResponse.body}',
        );
      }
      final List<dynamic> addrJson = json.decode(addrResponse.body);

      final ordersResponse = await http
          .get(Uri.parse('${ApiEndpoints.getOrdersSender}/${widget.userId}'))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('การโหลดออเดอร์หมดเวลา'),
          );
      debugPrint('Orders response: ${ordersResponse.body}');
      if (ordersResponse.statusCode != 200) {
        throw Exception(
          'ไม่สามารถโหลดออเดอร์ได้: ${ordersResponse.statusCode} - ${ordersResponse.body}',
        );
      }
      final List<dynamic> ordersJson = json.decode(ordersResponse.body);
      final fetchedOrders = ordersJson
          .map((e) => OrderModel.fromJson(e))
          .toList();
      debugPrint(
        'Fetched sender orders: ${fetchedOrders.map((o) => 'ID=${o.id}, status=${o.status}, riderId=${o.riderId}').join('\n')}',
      );

      setState(() {
        _senderAddresses = addrJson
            .map((e) => AddressModel.fromJson(e))
            .toList();
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

  void _navigateToRiderTracking(OrderModel order) {
    if (order.status >= 2 && order.riderId != null) {
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
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ยังไม่มีไรเดอร์รับงานออเดอร์นี้'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showAddOrderDialog() async {
    if (_senderAddresses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('คุณต้องมีที่อยู่ผู้ส่งอย่างน้อย 1 ที่อยู่'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddOrderDialog(
        senderId: widget.userId,
        senderAddresses: _senderAddresses,
      ),
    );
    if (success == true) _loadData(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(_error, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadData,
                    child: const Text('ลองใหม่'),
                  ),
                ],
              ),
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
                        .map(
                          (order) => _OrderCard(
                            key: ValueKey(order.id),
                            order: order,
                            onTap: () => _navigateToRiderTracking(order),
                          ),
                        )
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
          Icons.map,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AllWorkSenderMapScreen(userId: widget.userId),
              ),
            );
          },
        ),
        _buildCircleIcon(Icons.location_on_outlined),
        _buildCircleIcon(
          Icons.logout,
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const TextField(
        decoration: InputDecoration(
          hintText: 'ค้นหาออเดอร์...',
          border: InputBorder.none,
          prefixIcon: Icon(Icons.search, color: Colors.grey),
          prefixIconConstraints: BoxConstraints(minWidth: 30),
          suffixIcon: Icon(Icons.filter_list, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'รายการออเดอร์ของคุณ',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        GestureDetector(
          onTap: _showAddOrderDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF8329B4),
              borderRadius: BorderRadius.circular(25),
            ),
            child: const Text(
              '+ สร้างออเดอร์ใหม่',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderModel order;
  final VoidCallback? onTap;

  const _OrderCard({Key? key, required this.order, this.onTap})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.1),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Colors.grey.shade50],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ส่งให้: ${order.receiverName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            order.receiverPhone,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
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
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'สินค้า',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildImageWidget(
                                  order.productImageUrl,
                                  'สินค้า',
                                ),
                                if (order.status >= 3 &&
                                    order.pickupImageUrl != null &&
                                    order.pickupImageUrl!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12),
                                    child: _buildImageWidget(
                                      order.pickupImageUrl!,
                                      'รับ',
                                    ),
                                  ),
                                if (order.status == 4 &&
                                    order.deliveryImageUrl != null &&
                                    order.deliveryImageUrl!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12),
                                    child: _buildImageWidget(
                                      order.deliveryImageUrl!,
                                      'ส่ง',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'รหัส: #${order.id.toString().padLeft(5, '0')}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF8329B4),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (order.status == 1 || order.status == 2) ...[
                            _buildLocationRow(
                              Icons.storefront_outlined,
                              'รับที่',
                              order.senderAddress.addressDetail,
                            ),
                            const SizedBox(height: 8),
                            _buildLocationRow(
                              Icons.location_on_outlined,
                              'ส่งที่',
                              order.receiverAddress.addressDetail,
                            ),
                          ] else ...[
                            _buildStatusLocationRow(order.status),
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
      ),
    );
  }

  Widget _buildImageWidget(String imageUrl, String label) {
    final displayUrl = imageUrl.startsWith('http')
        ? imageUrl
        : '${ApiEndpoints.baseUrl}/$imageUrl';

    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
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
                  size: 28,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLocationRow(IconData icon, String title, String detail) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: Colors.blue),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail.isEmpty ? 'ไม่มีข้อมูล' : detail,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusLocationRow(int status) {
    IconData icon;
    Color iconColor;
    String text;

    switch (status) {
      case 3:
        icon = Icons.directions_bike;
        iconColor = const Color(0xFF8329B4);
        text = 'ไรเดอร์กำลังส่งสินค้า';
        break;
      case 4:
        icon = Icons.check_circle;
        iconColor = Colors.green;
        text = 'ส่งสินค้าเรียบร้อยแล้ว';
        break;
      default:
        icon = Icons.info;
        iconColor = Colors.grey;
        text = 'กำลังประมวลผล';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: iconColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: iconColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddOrderDialog extends StatefulWidget {
  final int senderId;
  final List<AddressModel> senderAddresses;

  const _AddOrderDialog({
    required this.senderId,
    required this.senderAddresses,
  });

  @override
  State<_AddOrderDialog> createState() => _AddOrderDialogState();
}

class _AddOrderDialogState extends State<_AddOrderDialog> {
  AddressModel? _selectedSenderAddress;
  final _receiverPhoneController = TextEditingController();
  final _detailsController = TextEditingController();
  bool _isSearchingReceiver = false;
  bool _receiverFound = false;
  String _receiverSearchError = '';
  List<AddressModel> _receiverAddresses = [];
  AddressModel? _selectedReceiverAddress;
  File? _productImage;
  final ImagePicker _picker = ImagePicker();
  bool _isCreatingOrder = false;

  @override
  void initState() {
    super.initState();
    if (widget.senderAddresses.isNotEmpty) {
      _selectedSenderAddress = widget.senderAddresses.first;
    }
  }

  @override
  void dispose() {
    _receiverPhoneController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 800,
      );
      if (pickedFile != null) {
        final file = File(pickedFile.path);
        final fileSizeMB = await file.length() / (1024 * 1024); // ขนาดเป็น MB
        final mimeType = lookupMimeType(pickedFile.path);
        if (fileSizeMB > 10) {
          _showErrorSnackbar('ไฟล์ภาพต้องมีขนาดไม่เกิน 10MB');
          return;
        }
        if (mimeType == null ||
            !['image/jpeg', 'image/png'].contains(mimeType)) {
          _showErrorSnackbar('กรุณาเลือกไฟล์ .jpg หรือ .png เท่านั้น');
          return;
        }
        setState(() {
          _productImage = file;
          debugPrint(
            'Image picked: ${pickedFile.path}, MIME: $mimeType, Size: ${fileSizeMB.toStringAsFixed(2)} MB',
          );
        });
      } else {
        debugPrint('No image selected');
      }
    } catch (e) {
      debugPrint('Image picker error: $e');
      _showErrorSnackbar('เกิดข้อผิดพลาดในการเลือกภาพ: $e');
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _searchReceiverByPhone() async {
    if (_receiverPhoneController.text.isEmpty) {
      _showErrorSnackbar('กรุณากรอกเบอร์โทรผู้รับ');
      return;
    }
    setState(() {
      _isSearchingReceiver = true;
      _receiverFound = false;
      _receiverSearchError = '';
      _receiverAddresses = [];
      _selectedReceiverAddress = null;
    });

    try {
      final uri = Uri.parse(
        '${ApiEndpoints.searchUserAddresses}?phone=${Uri.encodeComponent(_receiverPhoneController.text)}',
      );
      final response = await http
          .get(uri)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('การค้นหาหมดเวลา'),
          );
      debugPrint(
        'Search receiver response: ${response.statusCode} - ${response.body}',
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> addressesJson = data['addresses'];
        if (addressesJson.isEmpty) {
          setState(() {
            _receiverSearchError = 'ผู้รับนี้ยังไม่มีที่อยู่ที่บันทึกไว้';
            _isSearchingReceiver = false;
          });
          return;
        }
        final fetchedAddresses = addressesJson
            .map((e) => AddressModel.fromJson(e))
            .toList();
        setState(() {
          _receiverAddresses = fetchedAddresses;
          _selectedReceiverAddress = fetchedAddresses.first;
          _receiverFound = true;
          _isSearchingReceiver = false;
        });
      } else if (response.statusCode == 404) {
        setState(() {
          _receiverSearchError = 'ไม่พบผู้รับ (เบอร์โทรไม่ถูกต้อง)';
          _isSearchingReceiver = false;
        });
      } else {
        throw Exception(
          'ข้อผิดพลาดจากเซิร์ฟเวอร์: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Search receiver error: $e');
      setState(() {
        _receiverSearchError = 'ค้นหาล้มเหลว: $e';
        _isSearchingReceiver = false;
      });
    }
  }

  Future<bool> _submitCreateOrder() async {
    if (_selectedSenderAddress == null) {
      _showErrorSnackbar('กรุณาเลือกที่อยู่ผู้ส่ง');
      return false;
    }
    if (_selectedReceiverAddress == null) {
      _showErrorSnackbar('กรุณาค้นหาและเลือกที่อยู่ผู้รับ');
      return false;
    }
    if (_detailsController.text.isEmpty) {
      _showErrorSnackbar('กรุณากรอกรายละเอียดสินค้า');
      return false;
    }
    if (_productImage == null) {
      _showErrorSnackbar('กรุณาเลือกหรือถ่ายรูปสินค้า');
      return false;
    }

    setState(() => _isCreatingOrder = true);

    const maxRetries = 3;
    int attempt = 0;

    while (attempt < maxRetries) {
      try {
        final uri = Uri.parse(ApiEndpoints.createOrder);
        var request = http.MultipartRequest('POST', uri);

        // Add fields
        request.fields['senderId'] = widget.senderId.toString();
        request.fields['senderAddressId'] = _selectedSenderAddress!.id
            .toString();
        request.fields['receiverPhone'] = _receiverPhoneController.text;
        request.fields['receiverAddressId'] = _selectedReceiverAddress!.id
            .toString();
        request.fields['productDetails'] = _detailsController.text;
        request.fields['status'] = '1';

        // Add file
        final fileName = path.basename(_productImage!.path);
        final fileBytes = await _productImage!.readAsBytes();
        final fileSizeMB = fileBytes.length / (1024 * 1024); // ขนาดเป็น MB
        final mimeType = lookupMimeType(_productImage!.path) ?? 'image/jpeg';

        if (fileSizeMB > 10) {
          _showErrorSnackbar('ไฟล์ภาพต้องมีขนาดไม่เกิน 10MB');
          setState(() => _isCreatingOrder = false);
          return false;
        }

        debugPrint(
          'Attempt ${attempt + 1}: Uploading file: $fileName, size: ${fileBytes.length} bytes (${fileSizeMB.toStringAsFixed(2)} MB), MIME type: $mimeType',
        );

        request.files.add(
          http.MultipartFile(
            'productImage',
            http.ByteStream.fromBytes(fileBytes),
            fileBytes.length,
            filename: fileName,
            contentType: MediaType.parse(mimeType),
          ),
        );

        // Log request details
        debugPrint('Sending create order request:');
        debugPrint('URI: $uri');
        debugPrint('Fields: ${request.fields}');
        debugPrint('File: $fileName (MIME: $mimeType)');
        debugPrint('Headers: ${request.headers}');

        // Send request with timeout
        final streamedResponse = await request.send().timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            debugPrint('Upload timeout on attempt ${attempt + 1}');
            throw Exception('การอัปโหลดหมดเวลา');
          },
        );

        final response = await http.Response.fromStream(streamedResponse);

        debugPrint(
          'Create order response (attempt ${attempt + 1}): ${response.statusCode} - ${response.body}',
        );

        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('สร้างออเดอร์สำเร็จ!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true);
          return true;
        } else {
          try {
            final errorJson = json.decode(response.body);
            final message = errorJson['message'] ?? 'ไม่สามารถสร้างออเดอร์ได้';
            debugPrint('Backend error message: $message');
            if (message.contains('ต้องอัปโหลดรูปภาพสินค้า')) {
              _showErrorSnackbar('กรุณาตรวจสอบรูปภาพและลองใหม่');
              return false;
            }
            throw Exception(message);
          } catch (_) {
            throw Exception('ไม่สามารถสร้างออเดอร์ได้: ${response.body}');
          }
        }
      } catch (e) {
        attempt++;
        debugPrint('Create order error on attempt $attempt: $e');
        if (attempt >= maxRetries) {
          _showErrorSnackbar('เกิดข้อผิดพลาด: $e');
          setState(() => _isCreatingOrder = false);
          return false;
        }
        await Future.delayed(
          Duration(seconds: 2 * attempt),
        ); // Exponential backoff
      }
    }
    setState(() => _isCreatingOrder = false);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'เพิ่มออเดอร์สินค้าใหม่',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                _buildDropdownField(
                  'ที่อยู่ผู้ส่ง',
                  _selectedSenderAddress,
                  widget.senderAddresses,
                  (val) => setState(() => _selectedSenderAddress = val),
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  'เบอร์โทรผู้รับ',
                  _receiverPhoneController,
                  suffix: _isSearchingReceiver
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: _searchReceiverByPhone,
                        ),
                  keyboardType: TextInputType.phone,
                ),
                if (_receiverSearchError.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _receiverSearchError,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 16),
                if (_receiverFound)
                  _buildDropdownField(
                    'ที่อยู่ผู้รับ',
                    _selectedReceiverAddress,
                    _receiverAddresses,
                    (val) => setState(() => _selectedReceiverAddress = val),
                  ),
                const SizedBox(height: 16),
                _buildTextField(
                  'รายละเอียดสินค้า',
                  _detailsController,
                  maxLines: 3,
                  hint: 'กรอกรายละเอียด...',
                ),
                const SizedBox(height: 16),
                _buildPhotoUploadButton(),
                const SizedBox(height: 24),
                _buildActionButtons(),
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.grey),
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    Widget? suffix,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey[100],
            suffixIcon: suffix,
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField(
    String label,
    AddressModel? value,
    List<AddressModel> items,
    ValueChanged<AddressModel?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        DropdownButtonFormField<AddressModel>(
          value: value,
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(e.addressName, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: onChanged,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF0FFEE),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoUploadButton() {
    return GestureDetector(
      onTap: _pickImage,
      child: DottedBorder(
        borderType: BorderType.RRect,
        radius: const Radius.circular(12),
        color: Colors.grey.shade500,
        strokeWidth: 1,
        dashPattern: const [6, 6],
        child: Container(
          width: double.infinity,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: _productImage != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.file(
                    _productImage!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: 120,
                  ),
                )
              : Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.camera_alt_outlined,
                        color: Colors.grey.shade800,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'ถ่ายรูปหรือเลือกภาพสินค้า',
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _isCreatingOrder ? null : () => _submitCreateOrder(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _isCreatingOrder
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : const Text('เพิ่มออเดอร์'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: _isCreatingOrder
                ? null
                : () => Navigator.of(context).pop(false),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black,
              side: BorderSide(color: Colors.grey.shade400),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('ยกเลิก'),
          ),
        ),
      ],
    );
  }
}
