import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/date_symbol_data_local.dart";
import "app.dart";
import "theme/app_theme.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting("fr_FR");
  runApp(const ProviderScope(child: NewsRoot()));
}

class NewsRoot extends StatelessWidget {
  const NewsRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "News",
      debugShowCheckedModeBanner: false,
      locale: const Locale("fr"),
      supportedLocales: const [Locale("fr")],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildAppTheme(),
      home: const NewsApp(),
    );
  }
}
