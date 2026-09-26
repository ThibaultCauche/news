import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../core/api_providers.dart";
import "../theme/tokens.dart";
import "section_label.dart";

final glossaryTermProvider = FutureProvider.autoDispose.family<GlossaryTermDto, String>((ref, term) async {
  final response = await ref.watch(apiClientProvider).getGlossaryApi().glossaryControllerGetByTerm(term: term);
  return response.data!;
});

/// Feuille glossaire (écran 04, `docs/02`) : ouverte au toucher d'un mot
/// souligné dans un texte de contexte (ex. "pourquoi ce match compte").
void showGlossarySheet(BuildContext context, String term) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card))),
    builder: (context) => _GlossarySheetContent(term: term),
  );
}

class _GlossarySheetContent extends ConsumerWidget {
  const _GlossarySheetContent({required this.term});

  final String term;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(glossaryTermProvider(term));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel("GLOSSAIRE"),
            const SizedBox(height: AppSpacing.xs),
            Text(term, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            switch (entry) {
              AsyncData(:final value) => Text(value.text, style: Theme.of(context).textTheme.bodyMedium),
              AsyncError() => const Text("Définition indisponible.", style: TextStyle(color: AppColors.textSecondary)),
              _ => const Center(child: CircularProgressIndicator()),
            },
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text("Compris")),
            ),
          ],
        ),
      ),
    );
  }
}
