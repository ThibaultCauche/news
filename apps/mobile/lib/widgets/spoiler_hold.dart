import "dart:async";
import "dart:ui";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

/// Matchs dont l'utilisateur a révélé le score (appui long) pendant cette session : la carte du
/// match et son écran de détail restent d'accord. Pas persisté : au prochain lancement, le
/// sans spoil masque de nouveau ces scores.
class RevealedEventsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void reveal(String eventId) => state = {...state, eventId};
}

final revealedEventsProvider = NotifierProvider<RevealedEventsNotifier, Set<String>>(RevealedEventsNotifier.new);

/// Flou d'un score masqué (sans spoil) : assez fort pour ne laisser deviner aucun chiffre, et
/// caché aux lecteurs d'écran tant qu'il est flouté. `sigma == 0` : le texte net.
class SpoilerBlur extends StatelessWidget {
  const SpoilerBlur({super.key, required this.sigma, required this.child});

  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (sigma <= 0) return child;
    return ExcludeSemantics(
      child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal), child: child),
    );
  }
}

/// Appui long pour révéler un score flouté : tant que le doigt reste posé, le flou se dissipe
/// petit à petit ; relâché trop tôt, il revient. Une fois net, [onReveal] est appelé (une fois).
/// Écoute les pointeurs sans entrer dans l'arène des gestes, donc un tap (ouvrir le match) et un
/// défilement restent normaux. Mouvement réduit : pas de dégradé, le flou reste fixe et un appui
/// de 600 ms suffit.
class SpoilerHold extends StatefulWidget {
  const SpoilerHold({super.key, required this.builder, required this.onReveal, this.maxSigma = 14});

  final Widget Function(BuildContext context, double sigma) builder;
  final VoidCallback onReveal;
  final double maxSigma;

  @override
  State<SpoilerHold> createState() => _SpoilerHoldState();
}

class _SpoilerHoldState extends State<SpoilerHold> with SingleTickerProviderStateMixin {
  // Le flou ne commence à se dissiper qu'après le délai de l'appui long (500 ms) : un simple tap
  // n'entame rien. Durée totale de maintien : 500 ms + 700 ms de dégradé.
  static const _hold = Duration(milliseconds: 1200);
  late final AnimationController _controller = AnimationController(vsync: this, duration: _hold, reverseDuration: const Duration(milliseconds: 250))
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) _done();
    });
  Timer? _reducedMotionTimer;
  bool _revealed = false;

  @override
  void dispose() {
    _reducedMotionTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _done() {
    if (_revealed) return;
    _revealed = true;
    HapticFeedback.mediumImpact();
    widget.onReveal();
  }

  void _down() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _reducedMotionTimer = Timer(const Duration(milliseconds: 600), _done);
    } else {
      _controller.forward();
    }
  }

  void _up() {
    _reducedMotionTimer?.cancel();
    if (!_revealed) _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // Les 500 premières ms (délai de l'appui long) : flou entier ; ensuite il s'efface.
          final t = reduced ? 0.0 : ((_controller.value * _hold.inMilliseconds - 500) / (_hold.inMilliseconds - 500)).clamp(0.0, 1.0);
          return widget.builder(context, widget.maxSigma * (1 - Curves.easeIn.transform(t)));
        },
      ),
    );
  }
}
