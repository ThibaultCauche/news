import "package:flutter/material.dart";
import "../theme/tokens.dart";

/// Point rouge "en direct" : seul élément animé en continu de l'appli
/// (opacité 1 → 0,4 sur 1,2 s, `docs/maquettes/motion-specs`), retiré si
/// mouvement réduit.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.size = 8});

  final double size;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: AppMotion.livePulseDuration,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle),
      child: SizedBox(width: widget.size, height: widget.size),
    );
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return dot;
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.4).animate(_controller),
      child: dot,
    );
  }
}
