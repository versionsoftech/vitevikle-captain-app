import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vite_captain/main.dart';
import 'package:vite_captain/widgets/payment_received_popup.dart';

Future<void> showGlobalPaymentPopup({
  required double amount,
  required double commissionAmount,
  required bool commissionDeducted,
}) async {
  try {
    print('POPUP FUNCTION CALLED');
  } catch (_) {}

  final state = navigatorKey.currentState;
  if (state == null || !state.mounted) {
    try {
      print('NAVIGATOR NOT MOUNTED');
    } catch (_) {}
    return;
  }

  final context = navigatorKey.currentContext;
  if (context == null) {
    try {
      print('POPUP CONTEXT NULL');
    } catch (_) {}
    return;
  }

  final completer = Completer<void>();

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      try {
        print('POPUP CONTEXT NULL');
      } catch (_) {}
      if (!completer.isCompleted) {
        completer.complete();
      }
      return;
    }

    try {
      try {
        print('GLOBAL PAYMENT POPUP DISPLAYED');
      } catch (_) {}

      try {
        print('WAITING FOR DRIVER TAP');
      } catch (_) {}

      await showPaymentReceivedPopup(
        ctx,
        amount: amount,
        commissionAmount: commissionAmount,
        commissionDeducted: commissionDeducted,
      );
      try {
        print('PAYMENT POPUP CLOSED BY DRIVER');
      } catch (_) {}
    } catch (_) {}

    if (!completer.isCompleted) {
      completer.complete();
    }
  });

  return completer.future;
}

