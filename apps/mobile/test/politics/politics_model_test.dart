import "dart:math" as math;

import "package:flutter_test/flutter_test.dart";
import "package:news_api_client/news_api_client.dart";
import "package:mobile/features/politics/politics_model.dart";

VoteGroupDto vgroup({int members = 10, int pour = 0, int contre = 0, int abst = 0, int nonVotants = 0}) => VoteGroupDto(
  (b) => b
    ..id = "PO1"
    ..name = "Groupe"
    ..members = members
    ..pour = pour
    ..contre = contre
    ..abst = abst
    ..nonVotants = nonVotants
    ..position = VoteGroupDtoPositionEnum.pour,
);

void main() {
  group("seatKinds", () {
    test("range les sièges d'un groupe : pour, contre, abstention, absents", () {
      final seats = seatKinds([vgroup(members: 6, pour: 2, contre: 1, abst: 1, nonVotants: 1)]);
      expect(seats, [SeatKind.pour, SeatKind.pour, SeatKind.contre, SeatKind.abstention, SeatKind.absent, SeatKind.absent]);
    });

    test("un groupe qui compte plus de voix que de membres garde ses voix", () {
      expect(seatKinds([vgroup(members: 2, pour: 3)]), hasLength(3));
    });

    test("enchaîne les groupes dans l'ordre reçu", () {
      final seats = seatKinds([vgroup(members: 1, contre: 1), vgroup(members: 1, pour: 1)]);
      expect(seats, [SeatKind.contre, SeatKind.pour]);
    });
  });

  group("hemicycleSeats", () {
    test("donne autant de places que de sièges, toutes dans le demi-cercle", () {
      final seats = hemicycleSeats(577);
      expect(seats, hasLength(577));
      for (final s in seats) {
        expect(s.dy, greaterThanOrEqualTo(-1e-9));
        expect(math.sqrt(s.dx * s.dx + s.dy * s.dy), lessThanOrEqualTo(1 + 1e-9));
      }
    });

    test("va de la gauche vers la droite : les premiers sièges sont à gauche", () {
      final seats = hemicycleSeats(100);
      final angles = [for (final s in seats) math.atan2(s.dy, s.dx)];
      for (var i = 1; i < angles.length; i++) {
        expect(angles[i], lessThanOrEqualTo(angles[i - 1] + 1e-9));
      }
      expect(seats.first.dx, lessThan(0));
      expect(seats.last.dx, greaterThan(0));
    });

    test("pas de siège sans vote, pas de vote sans siège", () {
      expect(hemicycleSeats(0), isEmpty);
      expect(hemicycleSeats(1), hasLength(1));
      expect(hemicycleRows(577), 10);
      expect(hemicycleDotFraction(163), lessThan(0.04));
    });
  });

  group("élections", () {
    test("la date du scrutin s'écrit en toutes lettres", () {
      expect(electionDateLabel("2027-04-18"), "dimanche 18 avril 2027");
      expect(electionDateLabel("2027-05-01"), "samedi 1er mai 2027");
    });

    test("le compte à rebours du blocage de 20 h", () {
      final now = DateTime.utc(2027, 4, 18, 14, 48);
      expect(liftsInLabel("2027-04-18T18:00:00.000Z", now: now), "dans 3 h 12");
      expect(liftsInLabel("2027-04-18T18:00:00.000Z", now: DateTime.utc(2027, 4, 18, 16, 0)), "dans 2 h");
      expect(liftsInLabel("2027-04-18T18:00:00.000Z", now: DateTime.utc(2027, 4, 18, 17, 40)), "dans 20 min");
      expect(liftsInLabel("2027-04-18T18:00:00.000Z", now: DateTime.utc(2027, 4, 13, 12)), "dans 5 jours");
      expect(liftsInLabel("2027-04-18T18:00:00.000Z", now: DateTime.utc(2027, 4, 18, 18, 1)), "");
    });

    test("nombres et pourcentages à la française", () {
      expect(frPercent(50.42), "50,4 %");
      expect(frInt(1405332), "1 405 332");
      expect(frInt(48), "48");
      expect(roundLabel(1), "1ᵉʳ tour");
      expect(roundLabel(2), "2ᵈ tour");
    });
  });

  group("textes", () {
    final now = DateTime(2026, 10, 8);
    test("la date omet l'année en cours", () {
      expect(lawDayLabel("2026-05-12", now: now), "12 mai");
      expect(lawDayLabel("2025-06-18", now: now), "18 juin 2025");
      expect(lawDayLabel("2026-08-01", now: now), "1er août");
      expect(lawDayLabel(null, now: now), "");
    });

    test("l'auteur se lit sans rien inventer", () {
      LawAuthorDto author(LawAuthorDtoKindEnum kind, {String? name, String? group, int cosigners = 0}) => LawAuthorDto(
        (b) => b
          ..kind = kind
          ..name = name
          ..group = group
          ..cosigners = cosigners,
      );
      expect(authorLabel(author(LawAuthorDtoKindEnum.government)), "Le gouvernement");
      expect(authorLabel(author(LawAuthorDtoKindEnum.senators)), "Des sénateurs");
      expect(authorLabel(author(LawAuthorDtoKindEnum.deputy, name: "Ayda Hadizadeh", group: "Socialistes et apparentés")), "Ayda Hadizadeh, Socialistes et apparentés");
      expect(authorLabel(author(LawAuthorDtoKindEnum.deputy)), "Des députés");
      expect(cosignersLabel(0), "");
      expect(cosignersLabel(3), "3 cosignataires");
    });
  });
}

