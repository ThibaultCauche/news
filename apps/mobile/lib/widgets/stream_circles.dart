import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "package:url_launcher/url_launcher.dart";
import "../core/stream_language.dart";
import "../theme/app_theme.dart";
import "../theme/tokens.dart";

/// Où regarder le match (J21) : un cercle par chaîne de l'éditeur (logo, nom dessous, langue), celles
/// de ta langue d'abord, contour rouge qui respire quand la chaîne est en direct. « Autres streamers »
/// ouvre la page du jeu chez Twitch, où l'on trouve tous les co-streams.
class StreamCircles extends ConsumerStatefulWidget {
  const StreamCircles({super.key, required this.streams, required this.moreUrl});

  final List<StreamDto> streams;
  final String? moreUrl;

  @override
  ConsumerState<StreamCircles> createState() => _StreamCirclesState();
}

class _StreamCirclesState extends ConsumerState<StreamCircles> with SingleTickerProviderStateMixin {
  // Un seul battement pour tous les cercles en direct.
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  void _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(streamLanguageProvider);
    final streams = sortStreamsFor(widget.streams, language);
    if (streams.isEmpty && widget.moreUrl == null) return const SizedBox.shrink();

    // Mouvement réduit : le contour reste rouge et fixe.
    final still = MediaQuery.of(context).disableAnimations;
    final anyLive = streams.any((s) => s.live == true);
    if (anyLive && !still) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else if (_breath.isAnimating) {
      _breath.stop();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm), child: Text("REGARDER", style: AppTextStyles.sectionTitle.copyWith(fontSize: 14, letterSpacing: 1.2))),
        SizedBox(
          height: 124,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final s in streams) _StreamCircle(stream: s, breath: _breath, onTap: () => _open(s.url)),
              if (widget.moreUrl != null) _MoreCircle(onTap: () => _open(widget.moreUrl!)),
            ],
          ),
        ),
      ],
    );
  }
}

const _diameter = 64.0;

class _StreamCircle extends StatelessWidget {
  const _StreamCircle({required this.stream, required this.breath, required this.onTap});

  final StreamDto stream;
  final Animation<double> breath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final live = stream.live == true;
    final name = stream.displayName ?? stream.channel;
    final clean = name.replaceAll("_", " ").trim();
    final initials = (clean.length < 2 ? clean : clean.substring(0, 2)).toUpperCase();
    final language = stream.language?.toUpperCase();
    final logo = stream.imageUrl;
    final avatar = ClipOval(
      child: logo == null
          ? ColoredBox(color: AppColors.surface, child: Center(child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w700))))
          : Image.network(logo, fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surface, child: Center(child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w700))))),
    );
    return Semantics(
      button: true,
      label: "Regarder sur $name${language == null ? "" : ", $language"}${live ? ", en direct" : ""}",
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.chip),
        onTap: onTap,
        child: SizedBox(
          width: 84,
          child: Column(
            children: [
              SizedBox(
                width: _diameter + 12,
                height: _diameter + 12,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (live)
                      // Le contour respire : opacité et échelle seulement.
                      AnimatedBuilder(
                        animation: breath,
                        builder: (_, child) => Opacity(opacity: 0.45 + 0.55 * (1 - breath.value), child: Transform.scale(scale: 1 + 0.07 * breath.value, child: child)),
                        child: Container(width: _diameter + 10, height: _diameter + 10, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.live, width: 3))),
                      )
                    else
                      Container(width: _diameter + 10, height: _diameter + 10, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.surfaceBorder, width: 2))),
                    SizedBox(width: _diameter, height: _diameter, child: avatar),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: AppTypography.caption)),
              if (language != null) Text(language, style: const TextStyle(fontSize: 10, color: AppColors.textTertiary, letterSpacing: 0.8)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreCircle extends StatelessWidget {
  const _MoreCircle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: "Autres streamers, sur Twitch",
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.chip),
        onTap: onTap,
        child: SizedBox(
          width: 84,
          child: Column(
            children: [
              SizedBox(
                width: _diameter + 12,
                height: _diameter + 12,
                child: Center(
                  child: Container(
                    width: _diameter,
                    height: _diameter,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.brass.withValues(alpha: 0.6))),
                    child: const Icon(Icons.open_in_new_rounded, color: AppColors.brass),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              const Text("Autres streamers", maxLines: 2, textAlign: TextAlign.center, style: TextStyle(fontSize: AppTypography.caption)),
            ],
          ),
        ),
      ),
    );
  }
}
