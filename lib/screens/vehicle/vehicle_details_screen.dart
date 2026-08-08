import 'package:flutter/material.dart';
import 'package:vite_captain/services/vehicle_type_api.dart';

class VehicleDetailsScreen extends StatefulWidget {
  final String vehicleTypeId;

  const VehicleDetailsScreen({
    super.key,
    required this.vehicleTypeId,
  });

  @override
  State<VehicleDetailsScreen> createState() => _VehicleDetailsScreenState();
}

class _VehicleDetailsScreenState extends State<VehicleDetailsScreen> {
  bool _loading = true;
  VehicleTypeDetailsModel? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });

    final res = await const VehicleTypeApi().getVehicleTypeById(vehicleTypeId: widget.vehicleTypeId);
    if (!mounted) return;

    setState(() {
      _data = res;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = (_data?.name.trim().isNotEmpty ?? false) ? _data!.name : 'Vehicle Details';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_data == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Unable to load vehicle details'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if ((_data?.imageUrl ?? '').trim().isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          _data!.imageUrl,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            final fallback = _data!.fallbackImageUrl;
                            if (fallback.trim().isEmpty || fallback == _data!.imageUrl) {
                              return const SizedBox.shrink();
                            }
                            return Image.network(
                              fallback,
                              height: 180,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      _data!.name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    if (_data!.slug.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _data!.slug,
                        style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_data!.maxSeat != null) ...[
                      Row(
                        children: [
                          const Icon(Icons.event_seat, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Seats: ${_data!.maxSeat}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_data!.description.trim().isNotEmpty) ...[
                      Text(
                        _data!.description,
                        style: const TextStyle(height: 1.4),
                      ),
                    ],
                  ],
                )),
    );
  }
}

