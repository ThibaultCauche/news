import "package:connectivity_plus/connectivity_plus.dart";
import "../features/profile/community_providers.dart";
import "dart:async";

import "package:flutter/widgets.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../features/agenda/agenda_screen.dart";
import "../features/bracket/bracket_provider.dart";
import "../features/competitions/competitions_data.dart";
import "../features/follows/follows_provider.dart";
import "../features/forum/forum_providers.dart" show inboxProvider;
import "../features/home/home_screen.dart";
import "../features/next_match/next_match_screen.dart";
import "../features/team/team_screen.dart";
import "../features/bracket/ranking_view.dart" show rankingProvider;
import "../features/valorant_season/season_data.dart";
import "clock.dart";
import "navigation.dart";

/// Intervalle entre deux rafraîchissements des données qui bougent (direct, scores, suivis).
const autoRefreshInterval = Duration(seconds: 60);

/// Garde les écrans à jour sans qu'on ait à tirer pour rafraîchir (docs/04 J10) : une app laissée
/// ouverte la nuit gardait la date, les cartes et les statuts de la veille.
/// - retour au premier plan : tout est rechargé et la date du jour est resynchronisée ;
/// - au premier plan : l'Accueil, les Suivis et les pages de match sont rechargés chaque minute
///   (l'Agenda aussi tant que son onglet est affiché) ; le serveur répond par un 304 si rien n'a changé ;
/// - changement d'onglet : les données visibles sont rechargées.
/// Les écrans gardent l'ancien contenu pendant le rechargement (pas de spinner).
class AutoRefresh extends ConsumerStatefulWidget {
  const AutoRefresh({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AutoRefresh> createState() => _AutoRefreshState();
}

class _AutoRefreshState extends ConsumerState<AutoRefresh> with WidgetsBindingObserver {
  Timer? _timer;

  static const _agendaTab = 1;

  StreamSubscription<List<ConnectivityResult>>? _connectivity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    // Le réseau revient (J18) : on recharge tout de suite au lieu d'attendre la prochaine minute. Sert
    // seulement à relancer un chargement, jamais à décider qu'on est « en ligne ».
    try {
      _connectivity = Connectivity().onConnectivityChanged.listen((results) {
        if (!results.contains(ConnectivityResult.none)) _refreshAll();
      }, onError: (_) {});
    } catch (_) {
      // Plugin absent (tests) : le rechargement chaque minute suffit.
    }
  }

  @override
  void dispose() {
    _connectivity?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(autoRefreshInterval, (_) => _refreshLive());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAll();
      _startTimer();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  // Ce qui bouge en cours de journée : direct, scores, statuts.
  void _refreshLive() {
    ref.read(todayProvider.notifier).sync();
    ref.invalidate(homeProvider);
    ref.invalidate(followsProvider);
    ref.invalidate(predictionsProvider);
    // Points et badges évoluent au fil des matchs (règlement par le worker) : le profil suit.
    ref.invalidate(profileProvider);
    ref.invalidate(inboxProvider);
    ref.invalidate(eventProvider);
    if (ref.read(tabIndexProvider) == _agendaTab) ref.invalidate(agendaProvider);
  }

  // Retour au premier plan : on ne sait pas depuis combien de temps l'app dormait.
  void _refreshAll() {
    _refreshLive();
    ref.invalidate(agendaProvider);
    ref.invalidate(catalogProvider);
    ref.invalidate(competitionDetailProvider);
    ref.invalidate(bracketProvider);
    ref.invalidate(rankingProvider);
    ref.invalidate(entityProvider);
    ref.invalidate(valorantSeasonProvider);
    ref.invalidate(gameTeamsProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tabIndexProvider, (previous, next) {
      if (previous == next) return;
      ref.read(todayProvider.notifier).sync();
      _refreshLive();
      if (next == _agendaTab) ref.invalidate(agendaProvider);
    });
    return widget.child;
  }
}
