import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/registry.dart';
import '../core/source.dart';
import 'book_page.dart';

/// Search + story-code import across all sources.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.registry});

  final SourceRegistry registry;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  /// sourceId -> books
  Map<NovelSource, SearchResult> _results = const {};

  Future<void> _search({bool storyCode = false}) async {
    final q = _controller.text.trim();
    if (q.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _results = const {};
    });
    try {
      final errors = <String>[];
      if (storyCode) {
        // Story-code import: fan out to all sources, keep first hit each.
        final books = await widget.registry.importStoryCode(q, errors: errors);
        setState(() {
          _results = {
            for (final b in books)
              widget.registry.byId(b.sourceId): SearchResult(books: [b]),
          };
        });
      } else {
        final r = await widget.registry.searchAll(q, errors: errors);
        setState(() {
          _results = r;
        });
      }
      if (_results.isEmpty) {
        _error = errors.isEmpty
            ? 'No results'
            : 'No results — ${errors.length}/${widget.registry.sources.length} '
                'sources failed: ${errors.first}';
      }
    } catch (e) {
      _error = '$e';
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('StoryTime')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Search or paste a story code…',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _search(),
                ),
              ),
              onSubmitted: (_) => _search(),
              textInputAction: TextInputAction.search,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _search(storyCode: true),
                  child: const Text('Import story code'),
                ),
                const SizedBox(width: 12),
                if (_busy) const CircularProgressIndicator(),
                if (_error != null)
                  Expanded(
                    child: Text(_error!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _results.isEmpty
                ? const Center(child: Text('Search across 4 novel services'))
                : ListView(
                    children: [
                      for (final entry in _results.entries) ...[
                        ListTile(
                          title: Text(entry.key.name,
                              style: Theme.of(context).textTheme.titleMedium),
                          dense: true,
                        ),
                        for (final book in entry.value.books)
                          BookTile(book: book, registry: widget.registry),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class BookTile extends StatelessWidget {
  const BookTile({super.key, required this.book, required this.registry});

  final Book book;
  final SourceRegistry registry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: book.coverUrl != null
          ? Image.network(book.coverUrl!,
              width: 44, height: 62, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.book, size: 44))
          : const Icon(Icons.book, size: 44),
      title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [book.author, book.sourceId].where((s) => s != null).join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BookPage(book: book, registry: registry),
      )),
    );
  }
}
