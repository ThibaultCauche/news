import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/app_update.dart";

void main() {
  test("compareVersions compare numériquement, sans tenir compte du build", () {
    expect(compareVersions("1.0.0", "1.0.0+7"), 0);
    expect(compareVersions("1.9.0", "1.10.0"), lessThan(0));
    expect(compareVersions("2.0.0", "1.99.99"), greaterThan(0));
    expect(compareVersions("1.0", "1.0.1"), lessThan(0));
  });
}
