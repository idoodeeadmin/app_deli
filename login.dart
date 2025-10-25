import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'config/api_endpoints.dart';
import 'register.dart';
import 'RiderHome.dart';
import 'home.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  int selectedRole = 0; // 0 = user, 1 = rider
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _isLoading = false;
  String _error = '';

  @override
  void dispose() {
    phoneController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginUser() async {
    if (_isLoading) return;

    // ตรวจสอบฟิลด์
    if (phoneController.text.isEmpty || passwordController.text.isEmpty) {
      setState(() {
        _error = 'กรุณากรอกเบอร์โทรศัพท์และรหัสผ่าน';
      });
      _showSnackBar(_error);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = '';
    });
    FocusScope.of(context).unfocus();

    final String apiUrl = '${ApiEndpoints.baseUrl}/login';
    final stopwatch = Stopwatch()..start(); // วัดเวลา

    try {
      final response = await http
          .post(
            Uri.parse(apiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': phoneController.text,
              'password': passwordController.text,
              'role': selectedRole,
            }),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('การเชื่อมต่อเซิร์ฟเวอร์หมดเวลา');
            },
          );

      debugPrint('Login response time: ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('Login response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        _showSnackBar('เข้าสู่ระบบสำเร็จ: ${responseData['message']}');

        final int userId = responseData['userId'];
        final String name = responseData['name'] ?? 'ผู้ใช้';

        if (selectedRole == 0) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => HomeScreen(
                phone: phoneController.text,
                userId: userId,
                userName: name,
              ),
            ),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => RiderHome(
                phone: phoneController.text,
                userId: userId,
                userName: name,
              ),
            ),
          );
        }
      } else {
        final responseData = jsonDecode(response.body);
        setState(() {
          _error = responseData['message'] ?? 'เข้าสู่ระบบไม่สำเร็จ';
        });
        _showSnackBar(_error, isError: true);
      }
    } catch (e) {
      setState(() {
        _error = 'เกิดข้อผิดพลาด: $e';
      });
      _showSnackBar(_error, isError: true);
      debugPrint('Login error: $e');
    } finally {
      setState(() => _isLoading = false);
      stopwatch.stop();
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildInputField(
    TextEditingController controller,
    String label, {
    bool isPassword = false,
    TextInputType type = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        SizedBox(
          height: 35,
          child: TextField(
            controller: controller,
            obscureText: isPassword,
            keyboardType: type,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey[300],
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 4,
                horizontal: 8,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[300],
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black, width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      Image.asset(
                        "lib/assets/zing_z.webp",
                        width: 250,
                        height: 200,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.error),
                      ),
                      const Text(
                        "เข้าสู่ระบบ",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => setState(() => selectedRole = 0),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selectedRole == 0
                              ? Colors.black
                              : Colors.white,
                          foregroundColor: selectedRole == 0
                              ? Colors.white
                              : Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          minimumSize: const Size(0, 30),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person, size: 12),
                            SizedBox(width: 6),
                            Text("ผู้ใช้", style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => setState(() => selectedRole = 1),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selectedRole == 1
                              ? Colors.black
                              : Colors.white,
                          foregroundColor: selectedRole == 1
                              ? Colors.white
                              : Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          minimumSize: const Size(0, 30),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.directions_car, size: 12),
                            SizedBox(width: 6),
                            Text("ไรเดอร์", style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildInputField(
                  phoneController,
                  "หมายเลขโทรศัพท์",
                  type: TextInputType.phone,
                ),
                const SizedBox(height: 10),
                _buildInputField(
                  passwordController,
                  "รหัสผ่าน",
                  isPassword: true,
                ),
                if (_error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _error,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 30,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _loginUser,
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
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "เข้าสู่ระบบ",
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 125,
                    height: 30,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RegisterPage(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[900],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: const Text(
                        "สมัครสมาชิก",
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
