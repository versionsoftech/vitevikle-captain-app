import 'package:flutter_contacts/flutter_contacts.dart';

class ContactPickResult {
  final String name;
  final String phone;

  const ContactPickResult({
    required this.name,
    required this.phone,
  });
}

class ContactService {
  const ContactService();

  Future<bool> requestPermission() async {
    return FlutterContacts.requestPermission(readonly: true);
  }

  Future<List<Contact>> getContacts() async {
    return FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: false,
    );
  }

  ContactPickResult? mapContact(Contact contact) {
    final phones = contact.phones;
    if (phones.isEmpty) return null;

    final phone = phones.first.number.trim();
    final name = contact.displayName.trim().isEmpty
        ? 'Selected contact'
        : contact.displayName.trim();

    return ContactPickResult(
      name: name,
      phone: phone,
    );
  }
}
