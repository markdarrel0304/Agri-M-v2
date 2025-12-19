import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class PaymentPage extends StatefulWidget {
  final int orderId;
  final double amount;
  final String productName;

  const PaymentPage({
    Key? key,
    required this.orderId,
    required this.amount,
    required this.productName,
  }) : super(key: key);

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final storage = const FlutterSecureStorage();
  String _selectedMethod = 'gcash'; // gcash, card, cod, bank
  bool _isProcessing = false;

  // GCash fields
  final _phoneController = TextEditingController();
  final _gcashPinController = TextEditingController();

  // Card fields
  final _cardNumberController = TextEditingController();
  final _cardNameController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvcController = TextEditingController();

  // Bank Transfer fields
  final _accountNumberController = TextEditingController();
  final _accountNameController = TextEditingController();
  String _selectedBank = 'BDO';

  final _formKey = GlobalKey<FormState>();

  String get serverUrl =>
      Platform.isAndroid ? "http://10.0.2.2:8881" : "http://localhost:8881";

  @override
  void dispose() {
    _phoneController.dispose();
    _gcashPinController.dispose();
    _cardNumberController.dispose();
    _cardNameController.dispose();
    _expiryController.dispose();
    _cvcController.dispose();
    _accountNumberController.dispose();
    _accountNameController.dispose();
    super.dispose();
  }

  String _formatCardNumber(String value) {
    value = value.replaceAll(' ', '');
    String formatted = '';
    for (int i = 0; i < value.length; i++) {
      if (i > 0 && i % 4 == 0) formatted += ' ';
      formatted += value[i];
    }
    return formatted;
  }

  String _formatExpiry(String value) {
    value = value.replaceAll('/', '');
    if (value.length >= 2) {
      return '${value.substring(0, 2)}/${value.substring(2)}';
    }
    return value;
  }

  Future<void> _processPayment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isProcessing = true);

    try {
      final token = await storage.read(key: 'jwt');

      if (token == null) {
        throw Exception('Authentication token not found. Please login again.');
      }

      // Prepare payment data based on method
      Map<String, dynamic> paymentData = {
        'order_id': widget.orderId,
        'amount': widget.amount,
        'payment_method': _selectedMethod,
      };

      // Add method-specific data
      if (_selectedMethod == 'gcash') {
        paymentData['phone_number'] = _phoneController.text;
        paymentData['reference_number'] =
            'GCASH-${DateTime.now().millisecondsSinceEpoch}';
      } else if (_selectedMethod == 'card') {
        paymentData['card_last4'] =
            _cardNumberController.text.replaceAll(' ', '').substring(12);
        paymentData['cardholder_name'] = _cardNameController.text;
        paymentData['reference_number'] =
            'CARD-${DateTime.now().millisecondsSinceEpoch}';
      } else if (_selectedMethod == 'bank') {
        paymentData['bank_name'] = _selectedBank;
        paymentData['account_number'] = _accountNumberController.text;
        paymentData['account_name'] = _accountNameController.text;
        paymentData['reference_number'] =
            'BANK-${DateTime.now().millisecondsSinceEpoch}';
      } else if (_selectedMethod == 'cod') {
        paymentData['reference_number'] =
            'COD-${DateTime.now().millisecondsSinceEpoch}';
      }

      print('🔵 Sending payment request to: $serverUrl/api/payments/process');
      print('🔵 Payment data: ${json.encode(paymentData)}');

      final response = await http.post(
        Uri.parse('$serverUrl/api/payments/process'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: json.encode(paymentData),
      );

      print('🔵 Response status: ${response.statusCode}');
      print('🔵 Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);

        if (mounted) {
          _showSuccessDialog(data);
        }
      } else {
        // Enhanced error handling
        String errorMessage = 'Failed to create payment';

        try {
          final error = json.decode(response.body);
          errorMessage = error['error'] ?? error['message'] ?? errorMessage;

          // Log specific error details
          print('❌ Error details: $error');
        } catch (e) {
          // If response is not JSON
          errorMessage = response.body.isNotEmpty
              ? response.body
              : 'Server returned status ${response.statusCode}';
          print('❌ Raw error: ${response.body}');
        }

        if (mounted) {
          _showErrorDialog('Payment Failed', errorMessage);
        }
      }
    } catch (e, stackTrace) {
      print('❌ Exception during payment: $e');
      print('❌ Stack trace: $stackTrace');

      if (mounted) {
        _showErrorDialog(
            'Error',
            'Failed to process payment: ${e.toString()}\n\nPlease check:\n'
                '• Your internet connection\n'
                '• Backend server is running\n'
                '• Order ID ${widget.orderId} is valid');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showSuccessDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle,
                  color: Colors.green.shade700, size: 64),
            ),
            const SizedBox(height: 16),
            Text(
              'Payment Successful!',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Funds Secured in Escrow',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your payment of ${NumberFormat.currency(symbol: '₱').format(widget.amount)} is now held securely. It will be released to the seller after you confirm delivery.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (data['reference_number'] != null) ...[
              Text(
                'Reference Number',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              Text(
                data['reference_number'],
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(true);
            },
            child: Text(
              'Done',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.error, color: Colors.red.shade700, size: 32),
            const SizedBox(width: 12),
            Expanded(child: Text(title)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 20, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Troubleshooting',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. Check backend console for errors\n'
                      '2. Verify database connection\n'
                      '3. Ensure order exists and is confirmed\n'
                      '4. Check payment API endpoint is implemented',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Retry payment
              _processPayment();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment'),
        backgroundColor: isDark ? Colors.green.shade900 : Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Order Summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.green.shade900.withOpacity(0.3)
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        isDark ? Colors.green.shade700 : Colors.green.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order Summary',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            widget.productName,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Amount',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          NumberFormat.currency(symbol: '₱')
                              .format(widget.amount),
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Payment Method Selection
              Text(
                'Select Payment Method',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              _buildPaymentMethodCard(
                'gcash',
                'GCash',
                Icons.phone_android,
                'Mobile wallet payment',
              ),
              const SizedBox(height: 12),

              _buildPaymentMethodCard(
                'card',
                'Credit/Debit Card',
                Icons.credit_card,
                'Pay with card',
              ),
              const SizedBox(height: 12),

              _buildPaymentMethodCard(
                'bank',
                'Bank Transfer',
                Icons.account_balance,
                'Direct bank transfer',
              ),
              const SizedBox(height: 12),

              _buildPaymentMethodCard(
                'cod',
                'Cash on Delivery',
                Icons.local_shipping,
                'Pay when you receive',
              ),

              const SizedBox(height: 24),

              // Payment Form
              if (_selectedMethod == 'gcash') _buildGCashForm(),
              if (_selectedMethod == 'card') _buildCardForm(),
              if (_selectedMethod == 'bank') _buildBankForm(),
              if (_selectedMethod == 'cod') _buildCODInfo(),

              const SizedBox(height: 32),

              // Pay Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _processPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isProcessing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _selectedMethod == 'cod'
                              ? 'Confirm Order'
                              : 'Pay ${NumberFormat.currency(symbol: '₱').format(widget.amount)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 16),

              // Security Note
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.shade900.withOpacity(0.3)
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '🛡️ Your payment is secured with escrow protection. Funds will only be released after delivery confirmation.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.blue.shade200
                              : Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodCard(
    String value,
    String title,
    IconData icon,
    String subtitle,
  ) {
    final isSelected = _selectedMethod == value;
    return InkWell(
      onTap: () => setState(() => _selectedMethod = value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.green.shade700 : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? Colors.green.shade50 : Colors.white,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? Colors.green.shade700 : Colors.grey,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.green.shade700 : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: Colors.green.shade700),
          ],
        ),
      ),
    );
  }

  Widget _buildGCashForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GCash Details',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _phoneController,
          decoration: const InputDecoration(
            labelText: 'Mobile Number',
            hintText: '09XXXXXXXXX',
            prefixIcon: Icon(Icons.phone),
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.phone,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter mobile number';
            }
            if (!value.startsWith('09') || value.length != 11) {
              return 'Invalid mobile number';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _gcashPinController,
          decoration: const InputDecoration(
            labelText: 'GCash PIN',
            hintText: '••••',
            prefixIcon: Icon(Icons.lock),
            border: OutlineInputBorder(),
          ),
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter PIN';
            }
            if (value.length != 4) {
              return 'PIN must be 4 digits';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildCardForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Card Details',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _cardNumberController,
          decoration: const InputDecoration(
            labelText: 'Card Number',
            hintText: '4111 1111 1111 1111',
            prefixIcon: Icon(Icons.credit_card),
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(16),
          ],
          onChanged: (value) {
            final formatted = _formatCardNumber(value);
            _cardNumberController.value = TextEditingValue(
              text: formatted,
              selection: TextSelection.collapsed(offset: formatted.length),
            );
          },
          validator: (value) {
            if (value == null || value.replaceAll(' ', '').length != 16) {
              return 'Invalid card number';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _cardNameController,
          decoration: const InputDecoration(
            labelText: 'Cardholder Name',
            hintText: 'JUAN DELA CRUZ',
            prefixIcon: Icon(Icons.person),
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter name';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _expiryController,
                decoration: const InputDecoration(
                  labelText: 'Expiry',
                  hintText: 'MM/YY',
                  prefixIcon: Icon(Icons.calendar_today),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                onChanged: (value) {
                  final formatted = _formatExpiry(value);
                  _expiryController.value = TextEditingValue(
                    text: formatted,
                    selection:
                        TextSelection.collapsed(offset: formatted.length),
                  );
                },
                validator: (value) {
                  if (value == null || value.length != 5) {
                    return 'Invalid';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _cvcController,
                decoration: const InputDecoration(
                  labelText: 'CVC',
                  hintText: '123',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                obscureText: true,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                validator: (value) {
                  if (value == null || value.length != 3) {
                    return 'Invalid';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBankForm() {
    final banks = ['BDO', 'BPI', 'Metrobank', 'UnionBank', 'Landbank', 'PNB'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bank Transfer Details',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _selectedBank,
          decoration: const InputDecoration(
            labelText: 'Select Bank',
            prefixIcon: Icon(Icons.account_balance),
            border: OutlineInputBorder(),
          ),
          items: banks.map((bank) {
            return DropdownMenuItem(value: bank, child: Text(bank));
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedBank = value!;
            });
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _accountNumberController,
          decoration: const InputDecoration(
            labelText: 'Account Number',
            prefixIcon: Icon(Icons.numbers),
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter account number';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _accountNameController,
          decoration: const InputDecoration(
            labelText: 'Account Name',
            prefixIcon: Icon(Icons.person),
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter account name';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildCODInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.info, color: Colors.orange.shade700, size: 32),
          const SizedBox(height: 12),
          Text(
            'Cash on Delivery',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please prepare exact amount of ${NumberFormat.currency(symbol: '₱').format(widget.amount)} upon delivery.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Text(
            '💡 Payment will be held in escrow after you confirm receipt.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
