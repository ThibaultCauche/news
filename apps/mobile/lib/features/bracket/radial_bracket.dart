import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../domain/event_status.dart";
import "../../theme/tokens.dart";
import "../../widgets/spoiler_hold.dart";
import "../../widgets/match_countdown.dart";
import "../next_match/next_match_screen.dart";
import "bracket_model.dart";
import "bracket_painter.dart";

void openMatch(BuildContext context, String eventId) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: eventId)));

/// L'arbre en cercle : dessin, appuis sur un cercle (→ son match) et contenu du centre ([center],
/// par défaut le compte à rebours ou le champion du match décisif).
class RadialBracket extends StatelessWidget {
  const RadialBracket({super.key, required this.tree, required this.followed, this.center, this.centerOpensMatch = true, this.divider, this.dividerOutside = false});
  final RadialTree tree;
  final Set<String> followed;
  final Widget? center;

  /// Faux pour le centre d'une poule (« Qualifiés »), qui n'est pas un match.
  final bool centerOpensMatch;

  /// Voir `BracketPainter.divider`.
  final ({String top, String bottom})? divider;

  /// Les noms des deux moitiés au-dessus et au-dessous du cercle plutôt que sur la ligne (phase finale : des cercles les recouvriraient).
  final bool dividerOutside;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size.square(constraints.maxWidth);
        final layout = RadialLayout(tree, size);
        final circle = SizedBox.fromSize(
          size: size,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final id = layout.matchAt(details.localPosition);
              if (id != null && (centerOpensMatch || id != tree.center?.eventId)) openMatch(context, id);
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(size: size, painter: BracketPainter(tree: tree, followedEntityIds: followed, divider: dividerOutside && divider != null ? (top: "", bottom: "") : divider)),
                // Le logo (ou le code de l'équipe) dans chaque cercle : un widget, parce que le peintre ne charge pas d'images.
                for (final slot in tree.slots.where((s) => !s.hidden))
                  Positioned(
                    left: layout.position(slot).dx - layout.slotRadius,
                    top: layout.position(slot).dy - layout.slotRadius,
                    width: 2 * layout.slotRadius,
                    height: 2 * layout.slotRadius,
                    child: IgnorePointer(child: _SlotContent(slot: slot, followed: followed)),
                  ),
                IgnorePointer(
                  child: SizedBox(width: layout.centerRadius * 1.6, child: FittedBox(fit: BoxFit.scaleDown, child: center ?? CenterLabel(node: tree.center!))),
                ),
              ],
            ),
          ),
        );
        if (!dividerOutside || divider == null) return circle;
        const label = TextStyle(color: AppColors.brass, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2);
        return Column(
          children: [
            Text(divider!.top, style: label),
            const SizedBox(height: AppSpacing.xs),
            circle,
            const SizedBox(height: AppSpacing.xs),
            Text(divider!.bottom, style: label),
          ],
        );
      },
    );
  }
}

class _SlotContent extends ConsumerWidget {
  const _SlotContent({required this.slot, required this.followed});
  final TreeSlot slot;
  final Set<String> followed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = slot.team;
    final finishedScore = !slot.live && (slot.won || slot.lost) && slot.score != null && !ref.watch(scoreHiddenProvider(slot.matchId));
    final mine = team != null && followed.contains(team.entityId);
    final color = team == null || slot.lost ? AppColors.textTertiary : (mine ? AppColors.gold : AppColors.textPrimary);
    final code = Text(team == null ? "?" : teamCode(team), maxLines: 1, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600));
    final label = Padding(padding: const EdgeInsets.all(3), child: FittedBox(child: code));
    final logo = team?.imageUrl;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (logo == null)
          label
        else
          Padding(
            padding: const EdgeInsets.all(6),
            // Un perdant reste visible mais en retrait, comme son cercle.
            child: Opacity(opacity: slot.lost ? 0.4 : 1, child: Image.network(logo, fit: BoxFit.contain, errorBuilder: (_, _, _) => label)),
          ),
        // Score du match en direct (maquette : badge rouge « 1-0 »).
        if (slot.live && slot.score != null)
          Positioned(
            right: -6,
            bottom: -6,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle),
              child: Text("${slot.score}", style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          )
        else if (finishedScore)
          Positioned(
            right: -6,
            bottom: -6,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, border: Border.all(color: slot.won ? AppColors.win : AppColors.surfaceBorderHighlight)),
              child: Text("${slot.score}", style: TextStyle(color: slot.won ? AppColors.win : AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }
}

/// Le contenu du cercle central : compte à rebours, « en direct » ou champion.
class CenterLabel extends ConsumerWidget {
  const CenterLabel({super.key, required this.node});
  final BracketNodeDto node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = node.status.statusKind;
    // Sans spoil : le nom du champion reste caché derrière « Terminé » tant qu'on n'a pas révélé le match.
    final winner = ref.watch(scoreHiddenProvider(node.eventId)) ? null : winnerOf(node);
    final finalists = node.participants.map(teamCode).join(" – ");
    final startsAt = node.startsAt == null ? null : DateTime.parse(node.startsAt!);
    final (Color trophy, Widget main) = switch (kind) {
      EventStatusKind.finished => (AppColors.win, Text(winner == null ? "Terminé" : teamCode(winner), style: const TextStyle(color: AppColors.win, fontWeight: FontWeight.w700, fontSize: 16))),
      EventStatusKind.live => (AppColors.live, const Text("EN DIRECT", style: TextStyle(color: AppColors.live, fontWeight: FontWeight.w700, fontSize: 11))),
      _ => (
        AppColors.textSecondary,
        startsAt == null
            ? const Text("Finale", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14))
            : MatchCountdown(startsAt: startsAt, fontSize: 14),
      ),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.emoji_events_rounded, color: trophy, size: 22),
        main,
        if (finalists.isNotEmpty && kind != EventStatusKind.finished) Text(finalists, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
      ],
    );
  }
}

