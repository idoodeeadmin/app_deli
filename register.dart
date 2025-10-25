import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/api_endpoints.dart';
import 'login.dart';
import 'gps.dart';

// ------------------------------------------------------------------
// *** Model สำหรับจัดเก็บข้อมูลที่อยู่ (ใช้ร่วมกัน) ***
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
    'addressName': addressName,
    'addressDetail': addressDetail,
    'lat': lat.toString(),
    'lng': lng.toString(),
  };
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  int selectedRole = 0; // 0 = user, 1 = rider

  // Controllers
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  final vehicleRegController = TextEditingController();

  File? profileImage;
  File? vehicleImage;
  List<AddressModel> userAddresses = [];
  bool _isLoading = false;
  String _error = '';

  @override
  void dispose() {
    phoneController.dispose();
    passwordController.dispose();
    nameController.dispose();
    vehicleRegController.dispose();
    super.dispose();
  }

  // ================= Image Picker =================
  Future<void> _pickImage(bool isProfile) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        if (isProfile) {
          profileImage = File(picked.path);
        } else {
          vehicleImage = File(picked.path);
        }
      });
    }
  }

  // ================= Address Picker =================
  Future<void> _pickAddressFromMap({AddressModel? addressToEdit}) async {
    final List<AddressModel>? updatedAddresses = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GPSandMapPage(
          initialAddresses: userAddresses,
          addressToEdit: addressToEdit,
        ),
      ),
    );

    if (updatedAddresses != null) {
      setState(() {
        userAddresses = updatedAddresses;
      });
      _showSnackbar(
        'รายการที่อยู่ถูกอัปเดตแล้ว! (${userAddresses.length} แห่ง)',
      );
    }
  }

  // ================= Snackbar =================
  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ================= API Registration =================
  Future<void> _handleRegistration() async {
    if (!_formKey.currentState!.validate()) {
      _showSnackbar('กรุณากรอกข้อมูลให้ครบถ้วน', isError: true);
      return;
    }
    if (profileImage == null) {
      _showSnackbar('กรุณาอัปโหลดรูปโปรไฟล์', isError: true);
      return;
    }
    if (selectedRole == 0 && userAddresses.isEmpty) {
      _showSnackbar('กรุณาเพิ่มที่อยู่หลักสำหรับผู้ใช้', isError: true);
      return;
    }
    if (selectedRole == 1 &&
        (vehicleImage == null || vehicleRegController.text.isEmpty)) {
      _showSnackbar('กรุณาอัปโหลดรูปยานพาหนะและกรอกทะเบียนรถ', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiEndpoints.baseUrl}/register'),
      );

      request.fields['phone'] = phoneController.text;
      request.fields['password'] = passwordController.text;
      request.fields['name'] = nameController.text;
      request.fields['role'] = selectedRole.toString();

      if (selectedRole == 1) {
        request.fields['vehicle_reg'] = vehicleRegController.text;
      } else {
        final addressListForJson = userAddresses
            .map((addr) => addr.toJson())
            .toList();
        request.fields['addresses'] = json.encode(addressListForJson);
      }

      request.files.add(
        await http.MultipartFile.fromPath('profileImage', profileImage!.path),
      );
      if (selectedRole == 1 && vehicleImage != null) {
        request.files.add(
          await http.MultipartFile.fromPath('vehicleImage', vehicleImage!.path),
        );
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      debugPrint(
        'Register response: ${response.statusCode} - ${response.body}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _showSnackbar('สมัครสมาชิกสำเร็จ! กรุณาล็อกอิน');
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      } else {
        final data = json.decode(response.body);
        setState(() {
          _error = data['message'] ?? 'สมัครสมาชิกไม่สำเร็จ: ${response.body}';
        });
        _showSnackbar(_error, isError: true);
      }
    } catch (e) {
      setState(() {
        _error = 'เกิดข้อผิดพลาด: $e';
      });
      _showSnackbar(_error, isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ================= Widgets =================
  Widget _buildInputField(
    TextEditingController controller,
    String label, {
    bool isPassword = false,
    TextInputType type = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          obscureText: isPassword,
          keyboardType: type,
          validator:
              validator ??
              (value) =>
                  value == null || value.isEmpty ? 'กรุณากรอกข้อมูล' : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey[300],
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 4,
              horizontal: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Colors.red, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Colors.red, width: 1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleButton(
    String label,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: isSelected ? Colors.black : Colors.white,
          foregroundColor: isSelected ? Colors.white : Colors.black,
          minimumSize: const Size(0, 40),
          side: BorderSide(
            color: isSelected ? Colors.transparent : Colors.black,
            width: 1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }

  Widget _buildDottedImageUpload(String label, File? file, bool isProfile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 5),
        GestureDetector(
          onTap: () => _pickImage(isProfile),
          child: DottedBorder(
            color: Colors.grey,
            strokeWidth: 1,
            dashPattern: const [6, 3],
            borderType: BorderType.RRect,
            radius: const Radius.circular(8),
            child: Container(
              height: 120,
              width: double.infinity,
              color: Colors.grey[100],
              child: file != null
                  ? Image.file(file, fit: BoxFit.cover)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.camera_alt, size: 30, color: Colors.grey),
                        SizedBox(height: 8),
                        Text(
                          "อัปโหลดรูปภาพ",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddressSelectionList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "ที่อยู่ (จุดรับสินค้า)",
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 5),
        ...userAddresses.map((addr) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: SizedBox(
              height: 35,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _pickAddressFromMap(addressToEdit: addr),
                icon: const Icon(Icons.location_on, size: 16),
                label: Text(addr.addressName, overflow: TextOverflow.ellipsis),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
        SizedBox(
          height: 35,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _pickAddressFromMap,
            icon: const Icon(Icons.add, size: 16),
            label: Text(
              userAddresses.isEmpty ? 'เพิ่มที่อยู่หลัก' : 'เพิ่มที่อยู่ใหม่',
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.grey[300],
              foregroundColor: Colors.black,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (userAddresses.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              'ที่อยู่ทั้งหมด: ${userAddresses.length} แห่ง',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInputField(
            phoneController,
            "หมายเลขโทรศัพท์",
            type: TextInputType.phone,
            validator: (v) {
              if (v == null ||
                  v.isEmpty ||
                  v.length != 10 ||
                  !v.startsWith('0')) {
                return 'กรุณาใส่เบอร์โทรศัพท์ 10 หลักที่ขึ้นต้นด้วย 0';
              }
              return null;
            },
          ),
          const SizedBox(height: 15),
          _buildInputField(
            passwordController,
            "รหัสผ่าน",
            isPassword: true,
            validator: (v) {
              if (v == null || v.isEmpty || v.length < 6) {
                return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
              }
              return null;
            },
          ),
          const SizedBox(height: 15),
          _buildInputField(nameController, "ชื่อ-นามสกุล"),
          const SizedBox(height: 15),
          _buildDottedImageUpload("รูปโปรไฟล์", profileImage, true),
          const SizedBox(height: 15),
          if (selectedRole == 0) ...[
            _buildAddressSelectionList(),
            const SizedBox(height: 30),
          ] else ...[
            _buildInputField(
              vehicleRegController,
              "ทะเบียนรถ",
              validator: (v) =>
                  v == null || v.isEmpty ? 'กรุณากรอกทะเบียนรถ' : null,
            ),
            const SizedBox(height: 15),
            _buildDottedImageUpload("รูปยานพาหนะ", vehicleImage, false),
            const SizedBox(height: 30),
          ],
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_error, style: const TextStyle(color: Colors.red)),
            ),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleRegistration,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  : const Text(
                      "สมัครสมาชิก",
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[300],
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 25),
                    child: Text(
                      "สมัครสมาชิก",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    _buildRoleButton(
                      'ผู้ใช้',
                      Icons.person,
                      selectedRole == 0,
                      () => setState(() => selectedRole = 0),
                    ),
                    const SizedBox(width: 12),
                    _buildRoleButton(
                      'ไรเดอร์',
                      Icons.local_shipping,
                      selectedRole == 1,
                      () => setState(() => selectedRole = 1),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildForm(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
