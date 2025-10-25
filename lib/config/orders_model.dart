// lib/models/order_model.dart
import 'package:flutter/material.dart';

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
}

class OrderModel {
  final int id;
  final String receiverName;
  final String receiverPhone;
  final String productDetails;
  String productImageUrl;
  String? pickupImageUrl;
  String? deliveryImageUrl;
  int status;
  final AddressModel senderAddress;
  final AddressModel receiverAddress;
  final int riderId; // ใช้ใน AllWorkMapScreen, RiderHome
  final String? riderName;

  OrderModel({
    required this.id,
    required this.receiverName,
    required this.receiverPhone,
    required this.productDetails,
    required this.productImageUrl,
    this.pickupImageUrl,
    this.deliveryImageUrl,
    this.status = 1,
    required this.senderAddress,
    required this.receiverAddress,
    this.riderId = 0,
    this.riderName,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    String imageUrl = json['product_image_url']?.toString() ?? '';
    if (imageUrl.isEmpty) imageUrl = 'assets/default_product.png';

    AddressModel senderAddr;
    if (json['senderAddress'] != null) {
      senderAddr = AddressModel.fromJson(json['senderAddress']);
    } else {
      senderAddr = AddressModel(
        id: int.tryParse(json['senderAddressId']?.toString() ?? '') ?? 0,
        addressName: json['senderAddressName']?.toString() ?? '',
        addressDetail: json['senderAddressDetail']?.toString() ?? '',
        lat: double.tryParse(json['senderLat']?.toString() ?? '0.0') ?? 0.0,
        lng: double.tryParse(json['senderLng']?.toString() ?? '0.0') ?? 0.0,
      );
    }

    AddressModel receiverAddr;
    if (json['receiverAddress'] != null) {
      receiverAddr = AddressModel.fromJson(json['receiverAddress']);
    } else {
      receiverAddr = AddressModel(
        id: int.tryParse(json['receiverAddressId']?.toString() ?? '') ?? 0,
        addressName: json['receiverAddressName']?.toString() ?? '',
        addressDetail: json['receiverAddressDetail']?.toString() ?? '',
        lat: double.tryParse(json['receiverLat']?.toString() ?? '0.0') ?? 0.0,
        lng: double.tryParse(json['receiverLng']?.toString() ?? '0.0') ?? 0.0,
      );
    }

    return OrderModel(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      receiverName: json['receiverName']?.toString() ?? 'ไม่ระบุชื่อ',
      receiverPhone: json['receiverPhone']?.toString() ?? '',
      productDetails: json['product_details']?.toString() ?? '',
      productImageUrl: imageUrl,
      pickupImageUrl: json['pickup_image_url']?.toString(),
      deliveryImageUrl: json['delivery_image_url']?.toString(),
      status: int.tryParse(json['status']?.toString() ?? '1') ?? 1,
      senderAddress: senderAddr,
      receiverAddress: receiverAddr,
      riderId: int.tryParse(json['rider_id']?.toString() ?? '') ?? 0,
      riderName: json['rider_name']?.toString(),
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
