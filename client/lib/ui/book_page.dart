import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/registry.dart';
import 'reader_page.dart';

/// Book detail + table of contents.
class BookPage extends StatefulWidget {
  const BookPage({super.key, required this.book, required this.registry});

  final Book book;
  final SourceRegistry registry;

  @override
  State<BookPage> createState() => _BookPageState();
}

class _BookPageState extends State<BookPage> {
  List<Chapter>? _chapters;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final source = widget.registry.byId(widget.book.sourceId);
      final chapters = await source.chapters(widget.book.id);
      setState(() => _chapters = chapters);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    return Scaffold(
      appBar: AppBar(title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (book.coverUrl != null)
                Image.network(book.coverUrl!,
                    width: 96, height: 134, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.book, size: 96)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (book.author != null)
                      Text(book.author!,
                          style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(widget.registry.byId(book.sourceId).name,
                        style: Theme.of(context).textTheme.bodySmall),
                    if (book.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [for (final t in book.tags) Chip(label: Text(t))],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (book.intro != null) ...[
            const SizedBox(height: 12),
            Text(book.intro!),
          ],
          const SizedBox(height: 16),
          Text('Chapters', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
          else if (_chapters == null)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ))
          else if (_chapters!.isEmpty)
            const Text('No chapters available without an account.')
          else
            for (final ch in _chapters!)
              ListTile(
                dense: true,
                title: Text(ch.title),
                trailing: ch.locked ? const Icon(Icons.lock, size: 16) : null,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ReaderPage(
                    source: widget.registry.byId(book.sourceId),
                    chapters: _chapters!,
                    initialIndex: _chapters!.indexOf(ch),
                  ),
                )),
              ),
        ],
      ),
    );
  }
}
