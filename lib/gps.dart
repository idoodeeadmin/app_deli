import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart' as geo;

// *** สำคัญ: ต้อง Import AddressModel จาก RegisterPage ***
import 'register.dart'; // import AddressModel ที่สร้างใน RegisterPage

class GPSandMapPage extends StatefulWidget {
  // รับรายการที่อยู่เดิมเข้ามาจาก RegisterPage
  final List<AddressModel> initialAddresses;
  // รับที่อยู่ที่จะแก้ไขเข้ามา (ถ้ามี)
  final AddressModel? addressToEdit;

  const GPSandMapPage({
    super.key,
    required this.initialAddresses,
    this.addressToEdit,
  });

  @override
  State<GPSandMapPage> createState() => _GPSandMapPageState();
}

class _GPSandMapPageState extends State<GPSandMapPage> {
  final MapController mapController = MapController();
  final TextEditingController _addressController = TextEditingController();

  LatLng? selectedLocation;
  LatLng currentLocation = const LatLng(
    16.1833,
    103.3000,
  ); // พิกัดเริ่มต้น: มหาสารคาม

  List<AddressModel> _currentAddresses = [];
  bool _isLocationLoading = false;

  @override
  void initState() {
    super.initState();
    _currentAddresses = List.from(widget.initialAddresses);

    // ตั้งค่าเริ่มต้นของแผนที่ตามที่อยู่เดิม หรือที่อยู่ที่จะแก้ไข
    if (widget.addressToEdit != null) {
      final editAddr = widget.addressToEdit!;
      currentLocation = LatLng(editAddr.lat, editAddr.lng);
      selectedLocation = currentLocation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        mapController.move(currentLocation, 15);
      });
    } else if (_currentAddresses.isNotEmpty) {
      final firstAddr = _currentAddresses.first;
      currentLocation = LatLng(firstAddr.lat, firstAddr.lng);
      selectedLocation = currentLocation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        mapController.move(currentLocation, 15);
      });
    } else {
      // ไม่มีที่อยู่เดิม ให้อยู่ที่พิกัดเริ่มต้น และเลือกเป็นตำแหน่งที่เลือกไว้
      selectedLocation = currentLocation;
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  // -----------------------------------------------------
  // ** ฟังก์ชัน 1: ค้นหาพิกัดจากที่อยู่ (Geocoding) **
  // -----------------------------------------------------
  Future<void> _searchAddress(String address) async {
    if (address.isEmpty) return;

    _showSnackbar('กำลังค้นหาพิกัดของ: $address');

    try {
      List<geo.Location> locations = await geo.locationFromAddress(address);

      if (locations.isNotEmpty) {
        geo.Location firstLocation = locations.first;
        LatLng newLocation = LatLng(
          firstLocation.latitude,
          firstLocation.longitude,
        );

        if (mounted) {
          setState(() {
            currentLocation = newLocation;
            selectedLocation = newLocation;
          });
          mapController.move(newLocation, 15);
          _showSnackbar('พบตำแหน่งที่อยู่แล้ว', isError: false);
        }
      } else {
        _showSnackbar('ไม่พบตำแหน่งของที่อยู่: "$address"', isError: true);
      }
    } catch (e) {
      log("Geocoding Error: $e");
      _showSnackbar(
        'ค้นหาไม่สำเร็จ! ตรวจสอบชื่อที่อยู่และอินเทอร์เน็ต',
        isError: true,
      );
    }
  }

  // -----------------------------------------------------
  // ** ฟังก์ชัน 2: ดึงตำแหน่งปัจจุบัน (GPS) **
  // -----------------------------------------------------
  Future<void> _getCurrentLocation() async {
    setState(() => _isLocationLoading = true);

    try {
      var position = await _determinePosition();

      final lat = position.latitude;
      final lng = position.longitude;

      // *** โค้ดส่วนนี้ถูกลบออกแล้วตามคำขอของคุณ:
      // if (lat < 5 || lat > 21 || lng < 97 || lng > 106) {
      //      throw Exception("Location outside boundary.");
      // }

      if (mounted) {
        LatLng newLocation = LatLng(lat, lng);
        setState(() {
          currentLocation = newLocation;
          selectedLocation = newLocation;
          _isLocationLoading = false;
        });
        mapController.move(currentLocation, 16);
        _showSnackbar('พบตำแหน่งปัจจุบันของคุณแล้ว!', isError: false);
      }
    } catch (e) {
      log("Location error: $e.");

      if (mounted) {
        setState(() {
          _isLocationLoading = false;
        });
      }

      _showSnackbar(
        'ไม่สามารถระบุตำแหน่งที่แม่นยำได้: ${e.toString()}',
        isError: true,
      );
    }
  }

  // -----------------------------------------------------
  // ** ฟังก์ชัน 3: Reverse Geocoding (แปลงพิกัดเป็นชื่อสถานที่) **
  // -----------------------------------------------------
  Future<String> _getAddressDetails(LatLng point) async {
    try {
      List<geo.Placemark> placemarks = await geo.placemarkFromCoordinates(
        point.latitude,
        point.longitude,
        localeIdentifier: 'th_TH', // ยังคงพยายามแสดงผลเป็นภาษาไทย
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        // สร้างที่อยู่แบบย่อที่มนุษย์อ่านเข้าใจ
        String address = [
          place.street,
          place.subLocality,
          place.locality,
          place.administrativeArea,
          place.postalCode,
        ].where((e) => e != null && e.isNotEmpty).join(', ');

        // ทำความสะอาดชื่อ
        address = address.replaceAll(RegExp(r'(^, )|(, , )|(, , )'), '');

        return address.isEmpty ? 'ไม่พบชื่อที่อยู่' : address;
      } else {
        return 'ไม่พบชื่อสถานที่';
      }
    } catch (e) {
      log("Reverse Geocoding Error: $e");
      return 'ไม่สามารถดึงข้อมูลที่อยู่ได้';
    }
  }

  // -----------------------------------------------------
  // ** ฟังก์ชัน 4: บันทึก/อัปเดต/ลบ ที่อยู่ **
  // -----------------------------------------------------
  void _addNewOrUpdateAddress(String addressName, String addressDetail) {
    if (selectedLocation == null) {
      _showSnackbar('กรุณาเลือกตำแหน่งบนแผนที่ก่อนบันทึก', isError: true);
      return;
    }

    if (addressName.isEmpty) {
      addressName = 'ที่อยู่ใหม่ #${_currentAddresses.length + 1}';
    }

    final newAddress = AddressModel(
      addressName: addressName,
      addressDetail: addressDetail,
      lat: selectedLocation!.latitude,
      lng: selectedLocation!.longitude,
    );

    setState(() {
      if (widget.addressToEdit != null) {
        final index = _currentAddresses.indexWhere(
          (addr) =>
              addr.lat == widget.addressToEdit!.lat &&
              addr.lng == widget.addressToEdit!.lng,
        );
        if (index != -1) {
          _currentAddresses[index] = newAddress;
          _showSnackbar(
            'อัปเดตที่อยู่ "${addressName}" เรียบร้อย!',
            isError: false,
          );
        } else {
          _currentAddresses.add(newAddress);
          _showSnackbar(
            'เพิ่มที่อยู่ "${addressName}" เรียบร้อย!',
            isError: false,
          );
        }
      } else {
        _currentAddresses.add(newAddress);
        _showSnackbar(
          'เพิ่มที่อยู่ "${addressName}" เรียบร้อย!',
          isError: false,
        );
      }
      _addressController.clear();
    });
    Navigator.pop(context, _currentAddresses);
  }

  void _removeAddress(AddressModel addrToRemove) {
    if (!mounted) return;

    final removedAddressName = addrToRemove.addressName;

    setState(() {
      _currentAddresses.removeWhere(
        (addr) => addr.lat == addrToRemove.lat && addr.lng == addrToRemove.lng,
      );

      if (_currentAddresses.isEmpty) {
        selectedLocation = currentLocation; // กลับไปที่พิกัดเริ่มต้น
        mapController.move(currentLocation, 12);
      } else {
        LatLng newPoint = LatLng(
          _currentAddresses.first.lat,
          _currentAddresses.first.lng,
        );
        selectedLocation = newPoint;
        currentLocation = newPoint;
        mapController.move(currentLocation, 15);
      }
    });
    _showSnackbar(
      'ลบที่อยู่ "$removedAddressName" เรียบร้อยแล้ว',
      isError: true,
    );
    Navigator.pop(context, _currentAddresses);
  }

  Future<void> _showSaveAddressDialog() async {
    if (selectedLocation == null) return;

    // ดึงชื่อสถานที่จริง
    final String initialAddressDetail = await _getAddressDetails(
      selectedLocation!,
    );

    String addressNameInput = widget.addressToEdit?.addressName ?? '';
    String addressDetailInput =
        widget.addressToEdit?.addressDetail ?? initialAddressDetail;

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            widget.addressToEdit != null ? 'แก้ไขที่อยู่' : 'บันทึกที่อยู่ใหม่',
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                const Text(
                  'รายละเอียดที่อยู่:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(addressDetailInput),
                Text(
                  'Lat/Lng: ${selectedLocation!.latitude.toStringAsFixed(6)}, ${selectedLocation!.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (value) => addressNameInput = value,
                  controller: TextEditingController(text: addressNameInput),
                  decoration: const InputDecoration(
                    labelText: 'ตั้งชื่อที่อยู่ (เช่น: บ้าน, ที่ทำงาน)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            // ปุ่มลบ
            if (widget.addressToEdit != null && _currentAddresses.length > 1)
              TextButton(
                child: const Text(
                  'ลบที่อยู่',
                  style: TextStyle(color: Colors.red),
                ),
                onPressed: () {
                  _removeAddress(widget.addressToEdit!);
                },
              ),
            TextButton(
              child: const Text('ยกเลิก'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: Text(
                widget.addressToEdit != null ? 'บันทึกการแก้ไข' : 'บันทึก',
              ),
              onPressed: () {
                _addNewOrUpdateAddress(addressNameInput, addressDetailInput);
              },
            ),
          ],
        );
      },
    );
  }

  // -----------------------------------------------------
  // ** ฟังก์ชัน 5: Snackbar **
  // -----------------------------------------------------
  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade400 : Colors.blue.shade400,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // -----------------------------------------------------
  // ** UI Build **
  // -----------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.addressToEdit != null
              ? 'แก้ไขที่อยู่: ${widget.addressToEdit!.addressName}'
              : 'เพิ่ม/จัดการตำแหน่งที่อยู่',
        ),
      ),
      body: Column(
        children: [
          // ส่วนแสดงรายการที่อยู่ของผู้ใช้ (ที่ถูกบันทึกแล้ว)
          Container(
            height: 60,
            color: Colors.grey.shade100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _currentAddresses.length,
              itemBuilder: (context, index) {
                AddressModel addr = _currentAddresses[index];

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4.0,
                    vertical: 8.0,
                  ),
                  child: ActionChip(
                    label: Text(addr.addressName),
                    avatar: const Icon(Icons.location_on, size: 18),
                    onPressed: () {
                      LatLng point = LatLng(addr.lat, addr.lng);
                      setState(() {
                        selectedLocation = point;
                      });
                      mapController.move(point, 15);
                      _showSnackbar('แสดงตำแหน่ง ${addr.addressName}');
                    },
                    backgroundColor: Colors.blue.shade50,
                  ),
                );
              },
            ),
          ),

          // ส่วนค้นหา/กรอกที่อยู่ใหม่ และปุ่มบันทึก
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addressController,
                    decoration: InputDecoration(
                      labelText: 'ค้นหาที่อยู่ใหม่ (Geocoding)',
                      hintText: 'เช่น: 123 ถนนสุขุมวิท',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () =>
                            _searchAddress(_addressController.text),
                      ),
                    ),
                    onSubmitted: (value) => _searchAddress(value),
                  ),
                ),
                const SizedBox(width: 8),
                // ปุ่มบันทึกตำแหน่งที่เลือกปัจจุบัน
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: selectedLocation == null
                        ? null
                        : _showSaveAddressDialog,
                    icon: Icon(
                      widget.addressToEdit != null ? Icons.edit : Icons.save,
                      size: 18,
                    ),
                    label: Text(
                      widget.addressToEdit != null ? 'แก้ไข' : 'บันทึก',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // แผนที่
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: mapController,
                  options: MapOptions(
                    initialCenter: currentLocation,
                    initialZoom: 15.2,
                    onTap: (tapPosition, point) {
                      log("Tapped: $point");
                      setState(() => selectedLocation = point);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.thunderforest.com/atlas/{z}/{x}/{y}.png?apikey=d86df7ea170b4418aa639716f46faed3',
                      userAgentPackageName: 'com.example.delivery_tracking_app',
                    ),
                    if (selectedLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: selectedLocation!,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.red,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),

                // *** ปุ่มตำแหน่งปัจจุบัน (Current Location Button) ***
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: FloatingActionButton.extended(
                    heroTag: 'currentLocation',
                    onPressed: _isLocationLoading ? null : _getCurrentLocation,
                    label: Text(
                      _isLocationLoading ? 'กำลังค้นหา...' : 'ตำแหน่งปัจจุบัน',
                    ),
                    icon: _isLocationLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : const Icon(Icons.my_location),
                    backgroundColor: _isLocationLoading
                        ? Colors.grey
                        : Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // ปุ่มยืนยัน (ส่งรายการที่อยู่ทั้งหมดกลับไป)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: _currentAddresses.isEmpty
                  ? null
                  : () {
                      // ส่งรายการที่อยู่ทั้งหมดกลับไปที่ RegisterPage
                      Navigator.pop(context, _currentAddresses);
                    },
              icon: const Icon(Icons.arrow_back),
              label: Text(
                "กลับไปหน้าลงทะเบียน (${_currentAddresses.length} แห่งถูกบันทึก)",
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 45),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------
// ** ฟังก์ชันดึงตำแหน่งปัจจุบัน (Geolocator) **
// -----------------------------------------------------
Future<Position> _determinePosition() async {
  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return Future.error('Location services are disabled.');
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return Future.error('Location permissions are denied');
    }
  }

  if (permission == LocationPermission.deniedForever) {
    return Future.error('Location permissions are permanently denied.');
  }

  return await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  ).timeout(const Duration(seconds: 15));
}
