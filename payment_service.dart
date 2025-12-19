import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class PaymentService {
  final storage = const FlutterSecureStorage();

  String get serverBaseUrl {
    if (Platform.isAndroid) {
      return "http://10.0.2.2:8881";
    } else {
      return "http://localhost:8881";
    }
  }

  // ============================================
  // CREATE PAYMENT INTENT
  // ============================================
  Future<Map<String, dynamic>> createPaymentIntent({
    required int orderId,
    required double amount,
    required String paymentMethod, // 'gcash', 'paymongo', 'paypal'
  }) async {
    try {
      final token = await storage.read(key: 'jwt');

      final response = await http.post(
        Uri.parse('$serverBaseUrl/api/payments/create-intent'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: json.encode({
          'order_id': orderId,
          'amount': amount,
          'payment_method': paymentMethod,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to create payment intent');
      }
    } catch (e) {
      throw Exception('Error creating payment: $e');
    }
  }

  // ============================================
  // PROCESS GCASH PAYMENT
  // ============================================
  Future<Map<String, dynamic>> processGCashPayment({
    required int orderId,
    required double amount,
    required String phoneNumber,
  }) async {
    try {
      final token = await storage.read(key: 'jwt');

      final response = await http.post(
        Uri.parse('$serverBaseUrl/api/payments/gcash'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: json.encode({
          'order_id': orderId,
          'amount': amount,
          'phone_number': phoneNumber,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'GCash payment failed');
      }
    } catch (e) {
      throw Exception('Error processing GCash payment: $e');
    }
  }

  // ============================================
  // PROCESS PAYMONGO CARD PAYMENT
  // ============================================
  Future<Map<String, dynamic>> processCardPayment({
    required int orderId,
    required double amount,
    required String cardNumber,
    required String expiryMonth,
    required String expiryYear,
    required String cvc,
    required String cardholderName,
  }) async {
    try {
      final token = await storage.read(key: 'jwt');

      final response = await http.post(
        Uri.parse('$serverBaseUrl/api/payments/card'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: json.encode({
          'order_id': orderId,
          'amount': amount,
          'card_number': cardNumber,
          'exp_month': expiryMonth,
          'exp_year': expiryYear,
          'cvc': cvc,
          'cardholder_name': cardholderName,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Card payment failed');
      }
    } catch (e) {
      throw Exception('Error processing card payment: $e');
    }
  }

  // ============================================
  // VERIFY PAYMENT
  // ============================================
  Future<Map<String, dynamic>> verifyPayment(String paymentIntentId) async {
    try {
      final token = await storage.read(key: 'jwt');

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/payments/verify/$paymentIntentId'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to verify payment');
      }
    } catch (e) {
      throw Exception('Error verifying payment: $e');
    }
  }

  // ============================================
  // GET PAYMENT HISTORY
  // ============================================
  Future<List<Map<String, dynamic>>> getPaymentHistory() async {
    try {
      final token = await storage.read(key: 'jwt');

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/payments/history'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['payments']);
      } else {
        throw Exception('Failed to fetch payment history');
      }
    } catch (e) {
      throw Exception('Error fetching payment history: $e');
    }
  }

  // ============================================
  // GET ESCROW STATUS
  // ============================================
  Future<Map<String, dynamic>> getEscrowStatus(int orderId) async {
    try {
      final token = await storage.read(key: 'jwt');

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/payments/escrow/$orderId'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to get escrow status');
      }
    } catch (e) {
      throw Exception('Error getting escrow status: $e');
    }
  }

  // ============================================
  // REQUEST REFUND
  // ============================================
  Future<Map<String, dynamic>> requestRefund({
    required int orderId,
    required String reason,
  }) async {
    try {
      final token = await storage.read(key: 'jwt');

      final response = await http.post(
        Uri.parse('$serverBaseUrl/api/payments/refund'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: json.encode({
          'order_id': orderId,
          'reason': reason,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Refund request failed');
      }
    } catch (e) {
      throw Exception('Error requesting refund: $e');
    }
  }

  // ============================================
  // DOWNLOAD RECEIPT
  // ============================================
  Future<Map<String, dynamic>> downloadReceipt(int paymentId) async {
    try {
      final token = await storage.read(key: 'jwt');

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/payments/receipt/$paymentId'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to download receipt');
      }
    } catch (e) {
      throw Exception('Error downloading receipt: $e');
    }
  }
}
