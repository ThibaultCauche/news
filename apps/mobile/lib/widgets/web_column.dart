import "package:flutter/material.dart";

/// Largeur maximale de l'appli (J17) : au-delà, le contenu reste centré plutôt que de s'étirer sur un très grand écran.
const webColumnMaxWidth = 1280.0;

class WebColumn extends StatelessWidget {
  const WebColumn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final width = mediaQuery.size.width.clamp(0.0, webColumnMaxWidth);
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: SizedBox(
          width: width,
          child: MediaQuery(data: mediaQuery.copyWith(size: Size(width, mediaQuery.size.height)), child: child),
        ),
      ),
    );
  }
}
