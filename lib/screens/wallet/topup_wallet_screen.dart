import 'dart:convert';
import 'package:vite_captain/widgets/vite_loader.dart';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:vite_captain/screens/wallet/cashfree_checkout_screen.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/payment_gateway_api.dart';
import 'package:vite_captain/services/session_service.dart';

class TopupWalletScreen extends StatefulWidget {
  const TopupWalletScreen({super.key});

  @override
  State<TopupWalletScreen> createState() => _TopupWalletScreenState();
}

class _TopupWalletScreenState extends State<TopupWalletScreen> {
  final TextEditingController amountController = TextEditingController();
  final Razorpay _razorpay = Razorpay();

  List<PaymentGatewayModel> paymentMethods = <PaymentGatewayModel>[];
  String? selectedMethod;

  bool isLoading = true;
  bool isProcessingPayment = false;

  @override
  void initState() {
    super.initState();
    fetchPaymentMethods();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    amountController.dispose();
    _razorpay.clear();
    super.dispose();
  }

  Future<void> fetchPaymentMethods() async {
    try {
      final gateways = await const PaymentGatewayApi().getPaymentGateways();
      if (!mounted) return;
      setState(() {
        paymentMethods = gateways;
        selectedMethod = gateways.isNotEmpty ? gateways.first.serial : null;
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    print('[RAZORPAY] Payment Success: ${response.paymentId}');
    print('[RAZORPAY] Order ID: ${response.orderId}');
    print('[RAZORPAY] Signature: ${response.signature}');
    
    if (response.orderId != null && response.paymentId != null && response.signature != null) {
      _verifyPayment(response.orderId!, response.paymentId!, response.signature!);
    } else {
      print('[RAZORPAY] Payment response missing required fields');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment response incomplete')),
      );
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    print('[RAZORPAY] Payment Error: ${response.code} - ${response.message}');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Payment Failed: ${response.message}')),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    print('[RAZORPAY] External Wallet: ${response.walletName}');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('External Wallet: ${response.walletName}')),
    );
  }

  Future<void> _verifyPayment(String orderId, String paymentId, String signature) async {
    print('[RAZORPAY] Verifying payment...');
    
    try {
      final response = await DioClient.dio.post(
        '/api/payments/razorpay/verify',
        data: {
          'razorpay_order_id': orderId,
          'razorpay_payment_id': paymentId,
          'razorpay_signature': signature,
        },
        options: Options(
          validateStatus: (_) => true,
          contentType: Headers.jsonContentType,
        ),
      );

      print('[RAZORPAY] Verify Response: ${response.data}');

      if (response.data['success'] == true) {
        print('[RAZORPAY] Payment verified successfully');
        await _creditWallet(method: 'razorpay');
      } else {
        print('[RAZORPAY] Payment verification failed');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment verification failed')),
        );
      }
    } catch (e) {
      print('[RAZORPAY] Verify Error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment verification failed')),
      );
    }
  }

  Future<void> _creditWallet({String method = 'razorpay'}) async {
    print('[RAZORPAY] Crediting wallet...');
    
    final token = await const SessionService().getToken();
    final amount = amountController.text.trim();

    try {
      final response = await DioClient.dio.post(
        '/api/driver/wallet/credit',
        data: {
          'amount': amount,
          'method': method,
        },
        options: Options(
          validateStatus: (_) => true,
          contentType: Headers.jsonContentType,
          headers: {
            if (token != null && token.trim().isNotEmpty)
              'Authorization': 'Bearer $token',
          },
        ),
      );

      print('[RAZORPAY] Wallet Credit Response: ${response.data}');

      if (response.data['success'] == true) {
        print('[RAZORPAY] Wallet credited successfully');
        print('[RAZORPAY] New wallet balance: ${response.data['walletBalance']}');
        
        if (!mounted) return;
        
        // Refresh wallet balance in SessionService
        await const SessionService().saveWalletBalance(response.data['walletBalance']?.toDouble() ?? 0.0);
        
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Wallet topped up successfully")),
        );
        return;
      }

      final message = (response.data['message'] ?? 'Something went wrong').toString();
      print('[RAZORPAY] Wallet credit failed: $message');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      print('[RAZORPAY] Wallet Credit Error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Something went wrong")),
      );
    }
  }

  Future<void> addBalance() async {
    print('[TOPUP] =========================================');
    print('[TOPUP] Button clicked at: ${DateTime.now()}');
    print('[TOPUP] =========================================');
    
    if (amountController.text.trim().isEmpty || selectedMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter amount & select method")),
      );
      return;
    }

    final amount = amountController.text.trim();
    final selectedGateway = paymentMethods.firstWhere(
      (g) => g.serial == selectedMethod,
      orElse: () => const PaymentGatewayModel(name: '', serial: '', icon: ''),
    );
    final selectedSerial = selectedGateway.serial.trim().toLowerCase();
    final selectedName = selectedGateway.name.trim().toLowerCase();
    final isRazorpay = selectedSerial.startsWith('rzp') || selectedSerial == 'razorpay' || selectedName == 'razorpay';
    final isCashfree = selectedSerial == '1' || selectedSerial.contains('cashfree') || selectedName.replaceAll(' ', '') == 'cashfree';

    print('[RAZORPAY] Selected Method: $selectedMethod');
    print('[RAZORPAY] Is Razorpay: $isRazorpay');
    print('[RAZORPAY] Amount: $amount');

    // Show loading dialog immediately
    setState(() {
      isProcessingPayment = true;
    });
    
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Row(
            children: [
              ViteLoader(),
              SizedBox(width: 20),
              Text("Preparing Payment..."),
            ],
          ),
        );
      },
    );

    if (isRazorpay) {
      await _processRazorpayPayment(amount);
    } else if (isCashfree) {
      await _processCashfreePayment(amount);
    } else {
      await _processOtherPayment(amount);
    }
  }

  Future<void> _processCashfreePayment(String amount) async {
    try {
      final userBasics = await const SessionService().getUserBasics();
      final createOrderResponse = await DioClient.dio.post(
        '/api/payments/cashfree/create-order',
        data: {
          'amount': double.parse(amount),
          'currency': 'INR',
          'receipt': 'driver_cashfree_${DateTime.now().millisecondsSinceEpoch}',
          'customer_id': userBasics['id'] ?? userBasics['_id'] ?? 'driver_${DateTime.now().millisecondsSinceEpoch}',
          'customer_name': userBasics['name'] ?? 'Driver',
          'customer_email': userBasics['email'] ?? 'driver@vitevikle.com',
          'customer_phone': userBasics['mobile'] ?? '9999999999',
        },
        options: Options(
          validateStatus: (_) => true,
          contentType: Headers.jsonContentType,
        ),
      );

      if (createOrderResponse.data['success'] != true) {
        throw Exception(createOrderResponse.data['message'] ?? 'Failed to create Cashfree order');
      }

      final sessionId = (createOrderResponse.data['payment_session_id'] ?? '').toString();
      final orderId = (createOrderResponse.data['order_id'] ?? '').toString();
      final mode = (createOrderResponse.data['mode'] ?? 'sandbox').toString();

      if (sessionId.isEmpty || orderId.isEmpty) {
        throw Exception('Invalid Cashfree payment session');
      }

      if (mounted) {
        Navigator.of(context).pop();
        setState(() {
          isProcessingPayment = false;
        });
      }

      final paid = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => CashfreeCheckoutScreen(paymentSessionId: sessionId, mode: mode),
        ),
      );

      if (paid != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment Cancelled')),
        );
        return;
      }

      final verifyResponse = await DioClient.dio.post(
        '/api/payments/cashfree/verify',
        data: {'order_id': orderId},
        options: Options(
          validateStatus: (_) => true,
          contentType: Headers.jsonContentType,
        ),
      );

      if (verifyResponse.data['success'] == true) {
        await _creditWallet(method: 'cashfree');
      } else {
        final message = (verifyResponse.data['message'] ?? 'Payment verification failed').toString();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        setState(() {
          isProcessingPayment = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cashfree Payment Failed: $e')),
        );
      }
    }
  }

  Future<void> _processRazorpayPayment(String amount) async {
    print('[TOPUP] Create order API started at: ${DateTime.now()}');
    print('[RAZORPAY] Processing Razorpay payment...');

    try {
      // Step 1: Create Order
      print('[RAZORPAY] Step 1: Creating order...');
      final createOrderStartTime = DateTime.now();
      
      final createOrderResponse = await DioClient.dio.post(
        '/api/payments/razorpay/create-order',
        data: {
          'amount': double.parse(amount),
          'currency': 'INR',
          'receipt': 'driver_wallet_${DateTime.now().millisecondsSinceEpoch}',
        },
        options: Options(
          validateStatus: (_) => true,
          contentType: Headers.jsonContentType,
        ),
      );

      final createOrderEndTime = DateTime.now();
      final createOrderDuration = createOrderEndTime.difference(createOrderStartTime);
      
      print('[TOPUP] Create order API response received at: ${DateTime.now()}');
      print('[TOPUP] Create order API duration: ${createOrderDuration.inMilliseconds}ms');
      print('[RAZORPAY] Create Order Response: ${createOrderResponse.data}');

      if (createOrderResponse.data['success'] != true) {
        throw Exception(createOrderResponse.data['message'] ?? 'Failed to create order');
      }

      final orderId = createOrderResponse.data['orderId'];
      final razorpayAmount = createOrderResponse.data['amount'];
      final currency = createOrderResponse.data['currency'];

      print('[RAZORPAY] Order ID: $orderId');
      print('[RAZORPAY] Amount: $razorpayAmount');
      print('[RAZORPAY] Currency: $currency');

      // Step 2: Get Public Key
      print('[RAZORPAY] Step 2: Fetching public key...');
      print('[TOPUP] Public key API started at: ${DateTime.now()}');
      final publicKeyStartTime = DateTime.now();
      
      final publicKeyResponse = await DioClient.dio.get(
        '/api/payments/razorpay/public-key',
        options: Options(
          validateStatus: (_) => true,
          contentType: Headers.jsonContentType,
        ),
      );

      final publicKeyEndTime = DateTime.now();
      final publicKeyDuration = publicKeyEndTime.difference(publicKeyStartTime);
      
      print('[TOPUP] Public key API response received at: ${DateTime.now()}');
      print('[TOPUP] Public key API duration: ${publicKeyDuration.inMilliseconds}ms');
      print('[RAZORPAY] Public Key Response: ${publicKeyResponse.data}');

      if (publicKeyResponse.data['success'] != true) {
        throw Exception(publicKeyResponse.data['message'] ?? 'Failed to fetch public key');
      }

      final razorpayKey = publicKeyResponse.data['key'];
      final razorpayMode = publicKeyResponse.data['mode'] ?? 'unknown';

      print('[RAZORPAY] =========================================');
      print('[RAZORPAY] Razorpay Key: $razorpayKey');
      print('[RAZORPAY] Key Prefix: ${razorpayKey.substring(0, 8)}');
      print('[RAZORPAY] Mode: $razorpayMode');
      print('[RAZORPAY] =========================================');

      // Step 3: Open Razorpay Checkout
      print('[RAZORPAY] Step 3: Opening Razorpay checkout...');
      print('[TOPUP] Razorpay checkout opening at: ${DateTime.now()}');
      final checkoutStartTime = DateTime.now();

      final userBasics = await const SessionService().getUserBasics();

      final options = {
        'key': razorpayKey,
        'amount': razorpayAmount,
        'currency': currency,
        'order_id': orderId,
        'name': 'ViteVikle',
        'description': 'Wallet Top Up',
        'prefill': {
          'contact': userBasics['mobile'] ?? '',
          'email': userBasics['email'] ?? '',
        },
      };

      try {
        _razorpay.open(options);
        final checkoutEndTime = DateTime.now();
        final checkoutDuration = checkoutEndTime.difference(checkoutStartTime);
        print('[TOPUP] Razorpay checkout opened at: ${DateTime.now()}');
        print('[TOPUP] Razorpay checkout duration: ${checkoutDuration.inMilliseconds}ms');
        print('[TOPUP] =========================================');
        
        // Hide loading dialog when checkout opens
        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          setState(() {
            isProcessingPayment = false;
          });
        }
      } catch (e) {
        print('[TOPUP] Razorpay checkout error: $e');
        // Hide loading dialog on error
        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          setState(() {
            isProcessingPayment = false;
          });
        }
      }

    } catch (e) {
      print('[RAZORPAY] Payment Error: $e');
      // Hide loading dialog on error
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog if open
        setState(() {
          isProcessingPayment = false;
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment Failed: $e')),
      );
    }
  }

  Future<void> _processOtherPayment(String amount) async {
    print('[RAZORPAY] Processing other payment method...');
    
    final token = await const SessionService().getToken();

    try {
      final response = await DioClient.dio.post(
        '$baseUrl/add_wallet',
        data: {
          'amount': amount,
          'method': selectedMethod!,
        },
        options: Options(
          validateStatus: (_) => true,
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            if (token != null && token.trim().isNotEmpty)
              'Authorization': 'Bearer $token',
          },
        ),
      );

      print('[RAZORPAY] Other Payment Response: ${response.data}');

      dynamic decoded = response.data;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is! Map<String, dynamic>) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Something went wrong")),
        );
        return;
      }

      final bool ok =
          decoded['status'] == true || decoded['success'] == true || decoded['ok'] == true;

      if (!mounted) return;

      if (ok) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Balance Added Successfully")),
        );
        return;
      }

      final message = (decoded['message'] ?? 'Something went wrong').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      print('[RAZORPAY] Other Payment Error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Something went wrong")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Topup Wallet"),
        leading: const BackButton(),
      ),
      body: isLoading
          ? const Center(child: ViteLoader())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Amount"),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: "Enter Amount",
                        prefixIcon: const Icon(Icons.currency_rupee),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text("Select Method"),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: paymentMethods.length,
                      itemBuilder: (context, index) {
                        final item = paymentMethods[index];
                        final bool isRazorpay =
                            item.serial.trim().toLowerCase().startsWith('rzp') ||
                            item.name.trim().toLowerCase() == 'razorpay';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                spreadRadius: 1,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                height: 45,
                                width: 60,
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: isRazorpay
                                    ? Image.asset(
                                        'assets/images/2.png',
                                        fit: BoxFit.contain,
                                      )
                                    : (item.iconUrl.trim().isNotEmpty
                                        ? Image.network(
                                            item.iconUrl,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(Icons.image),
                                          )
                                        : const Icon(Icons.image)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.name.isEmpty ? "Razorpay" : item.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Radio<String>(
                                value: item.serial,
                                groupValue: selectedMethod,
                                onChanged: (value) {
                                  setState(() {
                                    selectedMethod = value;
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF009640),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 5,
                      ),
                      onPressed: addBalance,
                      child: const Text(
                        "Add Balance",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

