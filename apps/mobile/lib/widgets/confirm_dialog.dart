import "package:flutter/material.dart";
import "../theme/tokens.dart";

/// Une seule confirmation claire avant une action lourde (J15) : « Annuler » aussi visible que
/// le bouton d'action. `true` seulement si l'utilisateur confirme.
Future<bool> confirmAction(BuildContext context, {required String title, required String body, required String confirmLabel}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(confirmLabel, style: const TextStyle(color: AppColors.live))),
      ],
    ),
  );
  return confirmed == true;
}
