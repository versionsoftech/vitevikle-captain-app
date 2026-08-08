import 'package:flutter/material.dart';

class DocumentCaptureInstructionScreen extends StatelessWidget {
  const DocumentCaptureInstructionScreen({
    super.key,
    required this.title,
    required this.subtitleLines,
    required this.cameraScreenBuilder,
    this.illustrationAssetPath,
    this.illustrationMaxHeight,
  });

  final String title;
  final List<String> subtitleLines;
  final WidgetBuilder cameraScreenBuilder;
  final String? illustrationAssetPath;
  final double? illustrationMaxHeight;

  static const Color _primary = Color(0xFF369D01);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      ...subtitleLines.map(
                        (line) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(Icons.check, color: Colors.black87, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  line,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (illustrationAssetPath != null) ...[
                        const SizedBox(height: 20),
                        Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: illustrationMaxHeight ?? 220,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Image.asset(
                                illustrationAssetPath!,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final String? captured = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: cameraScreenBuilder,
                      ),
                    );

                    if (captured == null || captured.trim().isEmpty) return;
                    if (!context.mounted) return;
                    Navigator.pop(context, captured);
                  },
                  child: const Text(
                    'Take a picture',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
