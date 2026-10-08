import "package:flutter/material.dart";

/// Largeur maximale de l'appli sur le web : la mise en page est pensée pour un téléphone (J17).
/// Sur un grand écran elle reste une colonne centrée ; une vraie mise en page à deux colonnes viendra si elle manque.
const webColumnMaxWidth = 480.0;

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
