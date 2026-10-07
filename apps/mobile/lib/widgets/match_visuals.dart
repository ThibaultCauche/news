import "dart:async";
import "package:cached_network_image/cached_network_image.dart";
import "spoiler_hold.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "package:palette_generator/palette_generator.dart";
import "../theme/app_theme.dart";
import "../theme/tokens.dart";

/// Dégradé d'un match, directement de la couleur dominante d'une équipe à celle de
/// l'autre (`entityAccentColorProvider`). Partagé par la tuile de liste (`EventCard`),
/// la carte de grande finale et l'en-tête de l'écran du match : un seul rendu, et pas
/// de passage par `surface` au milieu, qui faisait une bande grise (J10). `null` si
/// aucune équipe n'a de couleur ; une seule couleur s'efface vers le fond de la carte.
LinearGradient? teamsGradient(Color? colorA, Color? colorB) {
  if (colorA == null && colorB == null) return null;
  return LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      colorA?.withValues(alpha: 0.26) ?? AppColors.surface.withValues(alpha: 0),
      colorB?.withValues(alpha: 0.26) ?? AppColors.surface.withValues(alpha: 0),
    ],
  );
}

/// Nouveaux essais d'un logo qui n'a pas pu se charger (réseau qui hoquette au démarrage) : au bout de
/// 2 s, 6 s puis 15 s. Sans ça, une image ratée le restait jusqu'au prochain lancement. Désactivé dans
/// les tests (`test/flutter_test_config.dart`) pour ne laisser aucun minuteur en attente.
bool imageRetryEnabled = true;
const _imageRetryDelays = [Duration(seconds: 2), Duration(seconds: 6), Duration(seconds: 15)];
final _providerAttempts = <String, int>{};

/// Relance le fournisseur [ref] plus tard après un échec ([key] compte les essais), ou n'y touche plus après le 3ᵉ.
void retryProviderLater(Ref ref, String key) {
  final attempt = _providerAttempts[key] ?? 0;
  if (!imageRetryEnabled || attempt >= _imageRetryDelays.length) return;
  _providerAttempts[key] = attempt + 1;
  final timer = Timer(_imageRetryDelays[attempt], ref.invalidateSelf);
  ref.onDispose(timer.cancel);
}

/// Vrai quand le logo est quasi entièrement noir (NRG, Karmine Corp…) : invisible sur nos fonds
/// sombres, il est alors affiché en blanc (`TeamLogo`). Mesuré sur les pixels du logo sans les
/// filtres par défaut de `PaletteGenerator` (qui écartent justement le noir) ; un logo qui garde une
/// vraie couleur (l'œil rouge de G2, 0,5 % des pixels) reste tel quel : seuil à 99,9 %. Mis en cache par URL.
final logoIsDarkProvider = FutureProvider.family<bool, String>((ref, imageUrl) async {
  try {
    final palette = await PaletteGenerator.fromImageProvider(CachedNetworkImageProvider(imageUrl), maximumColorCount: 6, filters: const []);
    final swatches = palette.paletteColors;
    final total = swatches.fold<int>(0, (sum, c) => sum + c.population);
    if (total == 0) return false;
    _providerAttempts.remove("dark:$imageUrl");
    final dark = swatches.where((c) => c.color.computeLuminance() < 0.08).fold<int>(0, (sum, c) => sum + c.population);
    return dark / total >= 0.999;
  } catch (_) {
    retryProviderLater(ref, "dark:$imageUrl");
    return false;
  }
});

/// Logo d'équipe : l'image du fournisseur, passée en blanc si elle est toute noire (`logoIsDarkProvider`).
/// Un chargement raté est retenté plusieurs fois (`_imageRetryDelays`).
class TeamLogo extends ConsumerStatefulWidget {
  const TeamLogo({super.key, required this.imageUrl, required this.size, this.fallback});

  final String imageUrl;
  final double size;
  final Widget? fallback;

  @override
  ConsumerState<TeamLogo> createState() => _TeamLogoState();
}

class _TeamLogoState extends ConsumerState<TeamLogo> {
  int _attempt = 0;
  Timer? _retry;

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  void _scheduleRetry() {
    if (!imageRetryEnabled || _retry != null || _attempt >= _imageRetryDelays.length) return;
    _retry = Timer(_imageRetryDelays[_attempt], () {
      _retry = null;
      if (!mounted) return;
      // L'échec est gardé dans le cache d'images : on l'en retire pour que l'image soit vraiment redemandée.
      CachedNetworkImageProvider(widget.imageUrl).evict();
      setState(() => _attempt++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = ref.watch(logoIsDarkProvider(widget.imageUrl)).value ?? false;
    final image = Image(
      image: CachedNetworkImageProvider(widget.imageUrl),
      key: ValueKey(_attempt),
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) {
        _scheduleRetry();
        return widget.fallback ?? const SizedBox.shrink();
      },
    );
    return dark ? ColorFiltered(colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn), child: image) : image;
  }
}

/// Logo d'équipe dans sa case (coin arrondi, pas un cercle : bannières larges et blasons
/// non circulaires) avec, en option, son score dessous. Le logo est dimensionné à la
/// case moins une marge : sans taille explicite, un logo plus grand que la case la
/// débordait (écran du match, J10). [fallback] s'affiche sans logo (initiales).
class TeamBadge extends StatelessWidget {
  const TeamBadge({super.key, required this.imageUrl, this.score, this.scoreSigma = 0, this.diameter = 44, this.fallback, this.crowned});

  final String? imageUrl;
  final num? score;

  /// Flou du score (sans spoil, J11) : 0 = net.
  final double scoreSigma;
  final double diameter;
  final String? fallback;

  /// Couronne au-dessus du logo du vainqueur d'un match terminé (J10) : `null` = pas de
  /// couronne du tout, `false` = emplacement réservé mais vide (le perdant), pour que
  /// les deux logos restent alignés.
  final bool? crowned;

  @override
  Widget build(BuildContext context) {
    final inset = 3 * diameter / 44;
    final inner = diameter - 2 * inset;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (crowned != null) ...[
          SizedBox(
            height: diameter * 0.3,
            width: diameter * 0.4,
            child: crowned! ? CustomPaint(painter: _CrownPainter()) : null,
          ),
          const SizedBox(height: 2),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.chip * diameter / 44),
          child: Container(
            width: diameter,
            height: diameter,
            color: AppColors.surfaceBorder,
            padding: EdgeInsets.all(inset),
            alignment: Alignment.center,
            child: imageUrl != null
                ? TeamLogo(imageUrl: imageUrl!, size: inner, fallback: _initials())
                : _initials(),
          ),
        ),
        if (score != null) ...[
          const SizedBox(height: 2),
          SpoilerBlur(
            sigma: scoreSigma,
            child: Text(
              "${score!.toInt()}",
              // Taille de score proportionnelle au logo (44 → 26, la tuile
              // réduite a un logo plus petit donc un score plus petit aussi).
              style: AppTextStyles.score(AppTypography.heroScore * diameter / 44),
            ),
          ),
        ],
      ],
    );
  }

  Widget _initials() => fallback == null ? const SizedBox.shrink() : Text(fallback!, style: const TextStyle(fontWeight: FontWeight.w700));
}

/// Couronne dorée (trois pointes sur un bandeau), dessinée : Material n'a pas d'icône couronne.
class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, h * 0.85)
      ..lineTo(0, h * 0.15)
      ..lineTo(w * 0.26, h * 0.55)
      ..lineTo(w * 0.5, 0)
      ..lineTo(w * 0.74, h * 0.55)
      ..lineTo(w, h * 0.15)
      ..lineTo(w, h * 0.85)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.brass);
    canvas.drawRect(Rect.fromLTWH(0, h * 0.88, w, h * 0.12), Paint()..color = AppColors.gold);
  }

  @override
  bool shouldRepaint(_CrownPainter oldDelegate) => false;
}

/// Initiales d'un participant sans logo (un joueur, ou une équipe dont le logo manque) : trois lettres de son nom court.
String participantInitials(EventParticipantDto p) {
  final raw = (p.shortName ?? p.name).trim();
  return (raw.length <= 3 ? raw : raw.substring(0, 3)).toUpperCase();
}
