import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

class EmergencyContactEntry {
  final String name;
  final String phone;

  const EmergencyContactEntry({required this.name, required this.phone});
}

class EmergencyContactsScreen extends StatefulWidget {
  final List<EmergencyContactEntry> initialSelected;

  const EmergencyContactsScreen({super.key, this.initialSelected = const []});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  static const int _maxContacts = 4;

  bool _loading = true;
  bool _permissionGranted = false;

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  List<Contact> _contacts = [];
  late List<EmergencyContactEntry> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List<EmergencyContactEntry>.from(widget.initialSelected);
    _init();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final granted = await FlutterContacts.requestPermission();
    if (!mounted) return;

    if (!granted) {
      setState(() {
        _permissionGranted = false;
        _loading = false;
      });
      return;
    }

    final contacts = await FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: false,
    );

    if (!mounted) return;

    final filtered = contacts
        .where((c) => c.phones.isNotEmpty)
        .toList(growable: false);

    setState(() {
      _permissionGranted = true;
      _contacts = filtered;
      _loading = false;
    });
  }

  void _finish() {
    Navigator.pop(context, _selected);
  }

  bool _isSelected(String name, String phone) {
    return _selected.any((e) => e.name == name && e.phone == phone);
  }

  void _removeSelected(EmergencyContactEntry entry) {
    setState(() {
      _selected.removeWhere((e) => e.name == entry.name && e.phone == entry.phone);
    });
  }

  void _toggleSelection({required String name, required String phone, required bool next}) {
    if (next) {
      if (_selected.length >= _maxContacts) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You can only add up to 4 emergency contacts'),
          ),
        );
        return;
      }
      setState(() {
        _selected.add(EmergencyContactEntry(name: name, phone: phone));
      });
      return;
    }

    setState(() {
      _selected.removeWhere((e) => e.name == name && e.phone == phone);
    });
  }

  List<Contact> get _visibleContacts {
    if (_query.isEmpty) return _contacts;

    return _contacts.where((c) {
      final name = c.displayName.toLowerCase();
      final phone = c.phones.isNotEmpty ? c.phones.first.number.toLowerCase() : '';
      return name.contains(_query) || phone.contains(_query);
    }).toList(growable: false);
  }

  Widget _helpButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.help_outline, size: 18),
        label: const Text('Help'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black87,
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search contacts',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _selectedSection() {
    if (_selected.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        ..._selected.map((e) {
          final firstLetter = (e.name.trim().isEmpty ? '?' : e.name.trim()[0]).toUpperCase();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.grey.shade200,
                      child: Text(
                        firstLetter,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            e.phone,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _removeSelected(e),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
            ],
          );
        }),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _contactRow(Contact c) {
    final name = c.displayName.trim().isEmpty ? 'Unknown' : c.displayName.trim();
    final phone = c.phones.isNotEmpty ? c.phones.first.number : '';
    final firstLetter = (name.isEmpty ? '?' : name[0]).toUpperCase();
    final selected = _isSelected(name, phone);

    return Column(
      children: [
        InkWell(
          onTap: () => _toggleSelection(name: name, phone: phone, next: !selected),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.grey.shade200,
                  child: Text(
                    firstLetter,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        phone,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Checkbox(
                  value: selected,
                  onChanged: (value) {
                    _toggleSelection(name: name, phone: phone, next: value ?? false);
                  },
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
      ],
    );
  }

  Widget _permissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.contacts, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'Contacts permission is required to continue',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                });
                _init();
              },
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _finish();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _finish,
          ),
          title: const Text('Emergency Contacts'),
          actions: [_helpButton()],
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !_permissionGranted
                    ? _permissionDenied()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          _searchBar(),
                          const SizedBox(height: 10),
                          Text(
                            'You can add upto 4 contacts only',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                          _selectedSection(),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _visibleContacts.length,
                              itemBuilder: (context, index) {
                                return _contactRow(_visibleContacts[index]);
                              },
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
