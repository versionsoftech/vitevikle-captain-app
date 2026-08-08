import 'package:flutter/material.dart';

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  bool _emailsPromos = false;
  bool _emailsInvoice = true;

  bool _smsInvoice = true;
  bool _smsPromos = true;
  bool _whatsappUpdates = true;

  bool _pushNotifications = true;
  bool _pipAccess = true;

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Colors.blueGrey,
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }

  Widget _switchRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Preferences'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('EMAIL'),
              const SizedBox(height: 10),
              _card(
                children: [
                  _switchRow(
                    title: 'Allow emails for promotions and offers',
                    value: _emailsPromos,
                    onChanged: (v) => setState(() => _emailsPromos = v),
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
                  _switchRow(
                    title: 'Allow emails for invoice',
                    value: _emailsInvoice,
                    onChanged: (v) => setState(() => _emailsInvoice = v),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _sectionTitle('SMS & WHATSAPP'),
              const SizedBox(height: 10),
              _card(
                children: [
                  _switchRow(
                    title: 'Allow SMS for invoice',
                    value: _smsInvoice,
                    onChanged: (v) => setState(() => _smsInvoice = v),
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
                  _switchRow(
                    title: 'Allow promotional SMS offers',
                    value: _smsPromos,
                    onChanged: (v) => setState(() => _smsPromos = v),
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
                  _switchRow(
                    title: 'Allow updates to be sent on WhatsApp',
                    value: _whatsappUpdates,
                    onChanged: (v) => setState(() => _whatsappUpdates = v),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _sectionTitle('PUSH NOTIFICATIONS'),
              const SizedBox(height: 10),
              _card(
                children: [
                  _switchRow(
                    title: 'Allow mobile push notifications',
                    value: _pushNotifications,
                    onChanged: (v) => setState(() => _pushNotifications = v),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _sectionTitle('PICTURE IN PICTURE (PIP)'),
              const SizedBox(height: 10),
              _card(
                children: [
                  _switchRow(
                    title: 'Allow picture in picture access',
                    value: _pipAccess,
                    onChanged: (v) => setState(() => _pipAccess = v),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
