import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../domain/event_status.dart";
import "../features/bracket/bracket_model.dart";
import "../features/next_match/next_match_screen.dart";
import "../theme/tokens.dart";
import "ornate_frame.dart";
import "spoiler_hold.dart";

enum CardEmphasis { none, next, live }

const bracketCardWidth = 176.0;
const bracketCardHeight = 100.0;

/// Une case de la pyramide (J20) : titre du match, deux équipes (logo, nom, score), état ou
/// date en bas. Le **prochain match** (`next`) porte un cadre à pointes renforcé, le match en
/// direct (`live`) le même en rouge : ce sont les deux cases que l'œil doit trouver d'abord.
class BracketMatchCard extends ConsumerWidget {
  const BracketMatchCard({super.key, required this.node, required this.sides, this.followed = const {}, this.emphasis = CardEmphasis.none});

  final BracketNodeDto node;
  final List<MatchSide> sides;
  final Set<String> followed;
  final CardEmphasis emphasis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideScores = node.status == "finished" && ref.watch(scoreHiddenProvider(node.eventId));
    final emphasized = emphasis != CardEmphasis.none;
    final accent = emphasis == CardEmphasis.live ? AppColors.live : AppColors.brass;
    return SizedBox(
      width: bracketCardWidth,
      height: bracketCardHeight,
      child: OrnateFrame(
        radius: AppRadii.chip,
        strong: emphasized,
        color: accent,
        child: Material(
          color: emphasized ? Color.alphaBlend(accent.withValues(alpha: 0.08), AppColors.surface) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.chip),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: node.eventId))),
            child: Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      cardTitle(node.name).toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: emphasized ? accent : AppColors.textTertiary),
                    ),
                  ),
                  const SizedBox(height: 2),
                  for (final side in sides.take(2)) Expanded(child: _SideLine(side: side, followed: followed, hideScore: hideScores)),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: _Footer(node: node)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideLine extends StatelessWidget {
  const _SideLine({required this.side, required this.followed, required this.hideScore});
  final bool hideScore;
  final MatchSide side;
  final Set<String> followed;

  @override
  Widget build(BuildContext context) {
    final unknown = side.code == null;
    final mine = side.entityId != null && followed.contains(side.entityId);
    final color = mine ? AppColors.gold : (unknown || side.lost ? AppColors.textTertiary : AppColors.textPrimary);
    // La ligne gagnante est teintée en vert mousse sur toute la largeur de la case.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: side.won ? AppColors.moss.withValues(alpha: 0.28) : null,
      child: Row(
        children: [
          BracketTeamLogo(side: side),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              side.label,
              maxLines: unknown ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: unknown ? 11 : 13, height: 1.1, color: color, fontWeight: side.won ? FontWeight.w700 : FontWeight.w500),
            ),
          ),
          if (side.score != null && !hideScore) Text("${side.score}", style: TextStyle(fontWeight: FontWeight.w700, color: side.won || mine ? color : AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// Logo d'équipe dans une petite case arrondie ; sans logo (ou en échec de chargement), le code.
class BracketTeamLogo extends StatelessWidget {
  const BracketTeamLogo({super.key, required this.side});
  final MatchSide side;

  @override
  Widget build(BuildContext context) {
    final initials = FittedBox(child: Text(side.code ?? "?", maxLines: 1, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.textSecondary)));
    return Container(
      width: 22,
      height: 22,
      padding: const EdgeInsets.all(2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceBorder,
        borderRadius: BorderRadius.circular(6),
        border: side.code == null ? Border.all(color: AppColors.surfaceBorderHighlight) : null,
      ),
      child: side.imageUrl == null
          ? initials
          : Image.network(side.imageUrl!, fit: BoxFit.contain, errorBuilder: (_, _, _) => initials),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.node});
  final BracketNodeDto node;

  @override
  Widget build(BuildContext context) {
    final kind = node.status.statusKind;
    final start = node.startsAt == null ? null : DateTime.parse(node.startsAt!);
    final (String text, Color color) = switch (kind) {
      EventStatusKind.live => ("EN DIRECT", AppColors.live),
      EventStatusKind.finished => ("Terminé", AppColors.textTertiary),
      _ when start != null => (_capitalize(scheduleLabel(start, DateTime.now())), AppColors.textSecondary),
      _ => ("Date à venir", AppColors.textTertiary),
    };
    return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: color, fontWeight: kind == EventStatusKind.live ? FontWeight.w700 : FontWeight.w400));
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
