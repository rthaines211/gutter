import 'package:flutter/material.dart';
import '../providers/providers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/comic_file.dart';

class ComicGridTile extends StatelessWidget {
  final ComicFile file;
  final String serverUrl;
  final VoidCallback onTap;

  const ComicGridTile({super.key, required this.file, required this.serverUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildCover(context)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              file.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white70,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    if (file.isDir) {
      return Container(
        color: Colors.grey[800],
        child: const Icon(Icons.folder, size: 64, color: Colors.amber),
      );
    }

    if (file.coverUrl != null && file.coverUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: '$serverUrl${file.coverUrl!}',
        httpHeaders: imageHeadersOf(context, '$serverUrl${file.coverUrl!}'),
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(
          color: Colors.grey[900],
          child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (_, _, _) => _fallbackCover(),
      );
    }

    return _fallbackCover();
  }

  Widget _fallbackCover() {
    return Container(
      color: Colors.grey[900],
      child: const Icon(Icons.menu_book, size: 48, color: Colors.grey),
    );
  }
}
