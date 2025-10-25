class ApiEndpoints {
  static const String baseUrl = 'https://delivery-app-xlnl.onrender.com';
  static const String login = '$baseUrl/login';
  static const String register = '$baseUrl/register';
  static const String getAddresses = '$baseUrl/get-addresses';
  static const String updateOrderStatus = '$baseUrl/update-order-status';
  static const String uploadPickupImage = '$baseUrl/upload-pickup-image';
  static const String uploadDeliveryImage = '$baseUrl/upload-delivery-image';
  static const String getOrdersSender = '$baseUrl/get-orders/sender';
  static const String getOrdersReceiver = '$baseUrl/get-orders/receiver';
  static const String getOrdersAvailable = '$baseUrl/get-orders/available';
  static const String acceptOrder = '$baseUrl/accept-order';
  static const String uploadOrderImage = '$baseUrl/upload-order-image';
  static const String searchUserAddresses = '$baseUrl/search-user-addresses';
  static const String createOrder = '$baseUrl/create-order';
  static const String getRiderLocation = '$baseUrl/get-rider-location';
  static const String updateRiderLocation = '$baseUrl/update-rider-location';
  static const String getOrder = '$baseUrl/get-order';
  static const String getUsers = '$baseUrl/users';

  // เปลี่ยนเป็น Render WebSocket (ใช้ wss://)
  static const String webSocketUrl = 'wss://delivery-app-xlnl.onrender.com/ws';

  static String riderWebSocketUrl(int riderId) => '$webSocketUrl/$riderId';
}
