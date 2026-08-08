import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CashfreeCheckoutScreen extends StatefulWidget {
  final String paymentSessionId;
  final String mode;

  const CashfreeCheckoutScreen({
    super.key,
    required this.paymentSessionId,
    required this.mode,
  });

  @override
  State<CashfreeCheckoutScreen> createState() => _CashfreeCheckoutScreenState();
}

class _CashfreeCheckoutScreenState extends State<CashfreeCheckoutScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    final environment = widget.mode.trim().toLowerCase() == 'live' ? 'PRODUCTION' : 'SANDBOX';
    final html = '''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<script src="https://sdk.cashfree.com/js/v3/cashfree.js"></script>
<style>body{font-family:Arial,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;color:#111827}.box{text-align:center}.loader{margin:18px auto;width:34px;height:34px;border:4px solid #e5e7eb;border-top-color:#16a34a;border-radius:50%;animation:spin 1s linear infinite}@keyframes spin{to{transform:rotate(360deg)}}</style>
</head>
<body>
<div class="box"><div class="loader"></div><div>Opening Cashfree Checkout...</div></div>
<script>
console.log('=== CASHFREE DEBUG START ===');
console.log('Cashfree SDK loading...');
const cashfree = Cashfree({ mode: '$environment' });
console.log('Cashfree SDK initialized with mode:', '$environment');
console.log('Payment Session ID: ${widget.paymentSessionId}');
console.log('Payment Session ID Length: ${widget.paymentSessionId.length}');
const checkoutOptions = {
  paymentSessionId: '${widget.paymentSessionId}',
  mode: '$environment'.toLowerCase(),
  redirectTarget: '_self'
};
console.log('CHECKOUT OPTIONS FINAL:', JSON.stringify(checkoutOptions, null, 2));
console.log('=== CASHFREE DEBUG END ===');
cashfree.checkout(checkoutOptions).then(function(result){
  console.log('Cashfree checkout result:', result);
  if (result.error) {
    console.log('Cashfree error:', result.error);
    CashfreeResult.postMessage('failed');
  }
  else if (result.paymentDetails) {
    console.log('Cashfree success:', result.paymentDetails);
    CashfreeResult.postMessage('success');
  }
  else {
    console.log('Cashfree cancelled');
    CashfreeResult.postMessage('cancelled');
  }
}).catch(function(err){
  console.log('Cashfree catch error:', err);
  CashfreeResult.postMessage('failed');
});
</script>
</body>
</html>
''';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'CashfreeResult',
        onMessageReceived: (message) {
          final value = message.message.trim().toLowerCase();
          if (!mounted) return;
          Navigator.pop(context, value == 'success');
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = request.url.toLowerCase();
            if (url.contains('success') || url.contains('paid')) {
              Navigator.pop(context, true);
              return NavigationDecision.prevent;
            }
            if (url.contains('cancel') || url.contains('failed') || url.contains('failure')) {
              Navigator.pop(context, false);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(html);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cashfree Payment')),
      body: WebViewWidget(controller: _controller),
    );
  }
}
