import 'package:dio/dio.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';

class ChatNotificationApi {
  const ChatNotificationApi();

  String _text(dynamic v) => (v ?? '').toString().trim();

  Future<int> getUnreadCount({
    required String receiverId,
    required String receiverRole,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/chat-notifications/unread-count?receiver_id=$receiverId&receiver_role=$receiverRole',
    );
    final Response resp = await DioClient.dio.get(uri.toString(), options: Options(validateStatus: (_) => true));
    if (resp.data is! Map) return 0;
    final decoded = Map<String, dynamic>.from(resp.data as Map);
    if (decoded['success'] != true) return 0;
    final c = decoded['unread_count'];
    if (c is num) return c.toInt();
    return int.tryParse(_text(c)) ?? 0;
  }

  Future<List<Map<String, dynamic>>> list({
    required String receiverId,
    required String receiverRole,
    int limit = 50,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/chat-notifications?receiver_id=$receiverId&receiver_role=$receiverRole&limit=$limit',
    );
    final Response resp = await DioClient.dio.get(uri.toString(), options: Options(validateStatus: (_) => true));
    if (resp.data is! Map) return <Map<String, dynamic>>[];
    final decoded = Map<String, dynamic>.from(resp.data as Map);
    if (decoded['success'] != true) return <Map<String, dynamic>>[];
    final raw = decoded['data'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<int> markRead({
    required String receiverId,
    required String receiverRole,
    String? rideId,
  }) async {
    final uri = Uri.parse('$baseUrl/chat-notifications/mark-read');
    final Response resp = await DioClient.dio.post(
      uri.toString(),
      data: {
        'receiver_id': receiverId,
        'receiver_role': receiverRole,
        if ((rideId ?? '').trim().isNotEmpty) 'ride_id': rideId,
      },
      options: Options(validateStatus: (_) => true),
    );
    if (resp.data is! Map) return 0;
    final decoded = Map<String, dynamic>.from(resp.data as Map);
    if (decoded['success'] != true) return 0;
    final c = decoded['unread_count'];
    if (c is num) return c.toInt();
    return int.tryParse(_text(c)) ?? 0;
  }

  Future<List<Map<String, dynamic>>> listApp({
    required String receiverId,
    int limit = 50,
  }) async {
    final uri = Uri.parse('$baseUrl/app-notifications?receiver_id=$receiverId&receiver_role=driver&limit=$limit');
    final Response resp = await DioClient.dio.get(uri.toString(), options: Options(validateStatus: (_) => true));
    if (resp.data is! Map) return <Map<String, dynamic>>[];
    final decoded = Map<String, dynamic>.from(resp.data as Map);
    if (decoded['success'] != true || decoded['data'] is! List) return <Map<String, dynamic>>[];
    return (decoded['data'] as List).whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> markAppRead({required String receiverId}) async {
    final uri = Uri.parse('$baseUrl/app-notifications/mark-read');
    await DioClient.dio.post(
      uri.toString(),
      data: {'receiver_id': receiverId, 'receiver_role': 'driver'},
      options: Options(validateStatus: (_) => true),
    );
  }
}

