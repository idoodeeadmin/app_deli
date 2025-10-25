class AddressModel {
  final String addressName;
  final String addressDetail;
  final double lat;
  final double lng;

  AddressModel({
    required this.addressName,
    required this.addressDetail,
    required this.lat,
    required this.lng,
  });

  Map<String, dynamic> toJson() => {
    'address_name': addressName,
    'address_detail': addressDetail,
    'latitude': lat,
    'longitude': lng,
  };
}
