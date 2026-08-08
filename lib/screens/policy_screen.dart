import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:vite_captain/services/dio_client.dart';

class PolicyScreen extends StatefulWidget {
  final String type;

  const PolicyScreen({super.key, required this.type});

  @override
  State<PolicyScreen> createState() => _PolicyScreenState();
}

class _PolicyScreenState extends State<PolicyScreen> {
  bool loading = true;
  String title = 'Policy';
  String content = '';
  String? error;
  DateTime? updatedAt;
  final ScrollController _scrollController = ScrollController();
  double _scrollProgress = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetch();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    final max = pos.maxScrollExtent;
    if (max <= 0) {
      if (_scrollProgress != 0) setState(() => _scrollProgress = 0);
      return;
    }
    final next = (pos.pixels / max).clamp(0.0, 1.0);
    if ((next - _scrollProgress).abs() >= 0.01) {
      setState(() => _scrollProgress = next);
    }
  }

  Future<void> _fetch() async {
    setState(() {
      loading = true;
      error = null;
    });

    final safeType = widget.type.trim();
    if (safeType.isEmpty) {
      setState(() {
        loading = false;
        title = 'Policy';
        content = '';
      });
      return;
    }

    try {
      final resp = await DioClient.dio.get('/api/policies/$safeType');
      final data = resp.data;

      dynamic payload = data;
      if (data is Map && data['data'] != null) payload = data['data'];
      if (payload is List && payload.isNotEmpty) payload = payload.first;

      final nextTitle = (payload is Map && payload['title'] != null)
          ? payload['title'].toString()
          : (safeType == 'privacy'
              ? 'Privacy Policy'
              : safeType == 'terms'
                  ? 'Terms & Conditions'
                  : 'Policy');
      final nextContent = (payload is Map && payload['content'] != null) ? payload['content'].toString() : '';

      DateTime? nextUpdated;
      try {
        final rawUpdated = (payload is Map) ? (payload['updated_at'] ?? payload['updatedAt']) : null;
        if (rawUpdated != null) {
          nextUpdated = DateTime.tryParse(rawUpdated.toString());
        }
      } catch (_) {}

      setState(() {
        title = nextTitle;
        content = nextContent;
        updatedAt = nextUpdated;
        loading = false;
      });
    } catch (e) {
      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;
    final baseA = theme.colorScheme.primary;
    final baseB = theme.colorScheme.secondary;
    final headerGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(baseA, Colors.black, isDark ? 0.1 : 0.0)!,
        Color.lerp(baseB, Colors.black, isDark ? 0.1 : 0.0)!,
      ],
    );

    IconData headerIcon = Icons.description_outlined;
    if (widget.type == 'privacy') headerIcon = Icons.verified_user_outlined;
    if (widget.type == 'terms') headerIcon = Icons.gavel_outlined;

    String metaLine = '';
    if (updatedAt != null) {
      final dt = updatedAt!;
      metaLine = 'Last updated: ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(
            value: loading ? null : _scrollProgress,
            minHeight: 3,
            backgroundColor: theme.dividerColor.withOpacity(0.25),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: headerGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(headerIcon, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (metaLine.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          metaLine,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withOpacity(0.92),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withOpacity(0.7)),
              ),
              child: Builder(
                builder: (_) {
                  if (loading) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(
                        8,
                        (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            height: 14,
                            width: (i % 3 == 0) ? double.infinity : (i % 3 == 1 ? 240 : 180),
                            decoration: BoxDecoration(
                              color: theme.dividerColor.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  if (error != null) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Could not load this page',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          error!,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _fetch,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    );
                  }

                  if (content.trim().isEmpty) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No content available',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please check back later.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                        ),
                      ],
                    );
                  }

                  return Html(
                    data: content,
                    style: {
                      'body': Style(
                        margin: Margins.zero,
                        padding: HtmlPaddings.zero,
                        fontSize: FontSize(15.5),
                        lineHeight: const LineHeight(1.45),
                        color: theme.colorScheme.onSurface,
                      ),
                      'h1': Style(fontSize: FontSize(22), fontWeight: FontWeight.w800, margin: Margins.only(bottom: 10)),
                      'h2': Style(fontSize: FontSize(18), fontWeight: FontWeight.w800, margin: Margins.only(top: 14, bottom: 8)),
                      'h3': Style(fontSize: FontSize(16), fontWeight: FontWeight.w800, margin: Margins.only(top: 12, bottom: 6)),
                      'p': Style(margin: Margins.only(bottom: 10)),
                      'li': Style(margin: Margins.only(bottom: 6)),
                      'a': Style(
                        color: theme.colorScheme.primary,
                        textDecoration: TextDecoration.underline,
                      ),
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

