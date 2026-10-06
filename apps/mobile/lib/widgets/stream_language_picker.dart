import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../core/stream_language.dart";
import "../theme/tokens.dart";

/// Le choix de la langue des streams (J21) : onboarding et Réglages.
class StreamLanguagePicker extends ConsumerWidget {
  const StreamLanguagePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(streamLanguageProvider);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final l in streamLanguages)
          ChoiceChip(label: Text(l.label), selected: l.code == current, onSelected: (_) => ref.read(streamLanguageProvider.notifier).select(l.code)),
      ],
    );
  }
}
