import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/transcript_service.dart';
import '../theme/app_theme.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<TranscriptInfo>? _transcripts;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await TranscriptService.listTranscripts();
      setState(() {
        _transcripts = list;
        _loading     = false;
      });
    } catch (e) {
      setState(() {
        _transcripts = [];
        _loading     = false;
      });
    }
  }

  Future<void> _share(TranscriptInfo info) async {
    await Share.shareXFiles(
      [XFile(info.file.path, mimeType: 'text/csv')],
      subject: '${info.technique} transcript — ${info.timestampLabel}',
    );
  }

  Future<void> _confirmDelete(TranscriptInfo info) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete transcript?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "${info.basename}"? This cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await TranscriptService.delete(info.file);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Transcripts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _transcripts == null || _transcripts!.isEmpty
              ? const _EmptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _transcripts!.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) => _TranscriptTile(
                      info: _transcripts![i],
                      onShare: () => _share(_transcripts![i]),
                      onDelete: () => _confirmDelete(_transcripts![i]),
                      onPreview: () =>
                          _showPreview(_transcripts![i]),
                    ),
                  ),
                ),
    );
  }

  void _showPreview(TranscriptInfo info) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => _TranscriptPreviewScreen(info: info)),
    );
  }
}

// ── Transcript tile ───────────────────────────────────────────────────────────
class _TranscriptTile extends StatelessWidget {
  const _TranscriptTile({
    required this.info,
    required this.onShare,
    required this.onDelete,
    required this.onPreview,
  });
  final TranscriptInfo info;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onPreview;

  IconData _iconFor(String technique) {
    switch (technique.toUpperCase()) {
      case 'CV':  return Icons.loop;
      case 'CA':  return Icons.timer_outlined;
      case 'SWV': return Icons.square_foot;
      case 'DPV': return Icons.bar_chart;
      case 'NPV': return Icons.stacked_line_chart;
      default:    return Icons.description_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.cardBg,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onPreview,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent1.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_iconFor(info.technique),
                    color: AppColors.accent1, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.technique,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info.timestampLabel,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12),
                    ),
                    Text(
                      info.sizeLabel,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
              // Action buttons
              IconButton(
                icon: const Icon(Icons.share_outlined,
                    color: AppColors.accent2, size: 20),
                tooltip: 'Share',
                onPressed: onShare,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.redAccent, size: 20),
                tooltip: 'Delete',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Preview screen ────────────────────────────────────────────────────────────
class _TranscriptPreviewScreen extends StatefulWidget {
  const _TranscriptPreviewScreen({required this.info});
  final TranscriptInfo info;

  @override
  State<_TranscriptPreviewScreen> createState() =>
      _TranscriptPreviewScreenState();
}

class _TranscriptPreviewScreenState
    extends State<_TranscriptPreviewScreen> {
  String? _content;

  @override
  void initState() {
    super.initState();
    widget.info.file.readAsString().then((c) {
      if (mounted) setState(() => _content = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.info.basename,
            style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: () => Share.shareXFiles(
              [XFile(widget.info.file.path, mimeType: 'text/csv')],
              subject: widget.info.basename,
            ),
          ),
        ],
      ),
      body: _content == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Text(
                _content!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
            ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_outlined,
                size: 64, color: AppColors.textSecondary),
            SizedBox(height: 16),
            Text('No saved transcripts yet.',
                style: TextStyle(color: AppColors.textSecondary)),
            SizedBox(height: 8),
            Text('Run a BLE measurement to save one.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      );
}
