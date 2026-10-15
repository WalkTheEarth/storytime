import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/source.dart';

/// Chapter reader with prev/next navigation.
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.source,
    required this.chapters,
    required this.initialIndex,
  });

  final NovelSource source;
  final List<Chapter> chapters;
  final int initialIndex;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late int _index = widget.initialIndex;
  ChapterContent? _content;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _content = null;
    });
    try {
      final content = await widget.source.chapterContent(widget.chapters[_index]);
      setState(() => _content = content);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.chapters.length) return;
    setState(() => _index = next);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final chapter = widget.chapters[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text(chapter.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  )
                : _content == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _content!.paragraphs.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _content!.paragraphs[i],
                            style: const TextStyle(fontSize: 17, height: 1.6),
                          ),
                        ),
                      ),
          ),
          SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _index > 0 && !_busy ? () => _go(-1) : null,
                ),
                Text('${_index + 1} / ${widget.chapters.length}'),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _index < widget.chapters.length - 1 && !_busy
                      ? () => _go(1)
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
