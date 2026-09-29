import "dart:async";

import "package:flutter/material.dart";

String _two(int n) => n.toString().padLeft(2, "0");

/// "03:10:30", ou "2j 04:30:12" au-delà d'un jour : toujours heures:minutes:secondes,
/// pour qu'on y lise tout de suite un compte à rebours (J10).
String formatCountdown(Duration remaining) {
  if (remaining <= Duration.zero) return "Imminent";
  final time = "${_two(remaining.inHours % 24)}:${_two(remaining.inMinutes % 60)}:${_two(remaining.inSeconds % 60)}";
  return remaining.inDays > 0 ? "${remaining.inDays}j $time" : time;
}

/// Compte à rebours vers [startsAt] : les deux-points clignotent à chaque seconde, sauf
/// en mouvement réduit (`MediaQuery.disableAnimations`, règle 13 de `CLAUDE.md`) où ils
/// restent fixes. Pas d'animation Flutter : le texte est simplement redessiné chaque
/// seconde par un seul `Timer`, aligné sur le changement de seconde.
class MatchCountdown extends StatefulWidget {
  const MatchCountdown({super.key, required this.startsAt, this.fontSize = 22, this.now = DateTime.now});

  final DateTime startsAt;
  final double fontSize;

  /// Horloge, remplaçable dans les tests (`DateTime.now` ne suit pas le temps simulé de `pump`).
  final DateTime Function() now;

  @override
  State<MatchCountdown> createState() => _MatchCountdownState();
}

class _MatchCountdownState extends State<MatchCountdown> {
  Timer? _timer;

  Duration get _remaining => widget.startsAt.difference(widget.now());

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(MatchCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startsAt != widget.startsAt) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final remaining = _remaining;
    if (remaining <= Duration.zero) return;
    _timer = Timer(Duration(milliseconds: remaining.inMilliseconds % 1000 + 20), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;
    final blinkOff = !MediaQuery.disableAnimationsOf(context) && remaining.inSeconds.isOdd;
    final style = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w800,
      fontSize: widget.fontSize,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final ch in formatCountdown(remaining).split(""))
            TextSpan(text: ch, style: ch == ":" && blinkOff ? const TextStyle(color: Colors.transparent) : null),
        ],
      ),
    );
  }
}
