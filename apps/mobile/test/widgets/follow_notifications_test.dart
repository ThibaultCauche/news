import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/follows/follows_provider.dart";
import "package:mobile/features/settings/follow_notifications_screen.dart";
import "package:news_api_client/news_api_client.dart";

class _Notifier extends FollowsNotifier {
  _Notifier(this.initial, this.calls);
  final List<FollowStateDto> initial;
  final List<String> calls;

  @override
  Future<List<FollowStateDto>> build() async => initial;

  @override
  Future<void> setNotifications(FollowStateDto follow, {bool? reminder, bool? start, bool? result}) async {
    calls.add("${follow.name} reminder=$reminder start=$start result=$result");
  }
}

FollowStateDto _follow(String name, String type, {bool reminder = false, bool start = true, bool result = true, bool muted = false}) => FollowStateDto((b) => b
  ..id = "sub-$name"
  ..targetType = type
  ..targetId = name
  ..level = "all"
  ..muted = muted
  ..notifyReminder = reminder
  ..notifyStart = start
  ..notifyResult = result
  ..name = name);

void main() {
  testWidgets("un suivi par carte, trois interrupteurs, et la sourdine n'est pas listée (J21)", (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [followsProvider.overrideWith(() => _Notifier([_follow("G2", "entity"), _follow("VCT", "competition", start: false), _follow("Masters", "competition", muted: true)], calls))],
        child: const MaterialApp(home: FollowNotificationsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text("G2"), findsOneWidget);
    expect(find.text("VCT"), findsOneWidget);
    expect(find.text("Masters"), findsNothing);
    expect(find.byType(Switch), findsNWidgets(6));

    await tester.tap(find.byType(Switch).first); // rappel de G2
    await tester.pump();
    expect(calls, ["G2 reminder=true start=null result=null"]);
  });
}
