-- Ordre stable des équipes d'un match (J10) : `event_participant.side` (0 = gauche, 1 = droite) n'était
-- jamais écrit, l'ordre dépendait de l'ordre physique des lignes en base et changeait à chaque mise à jour.
-- L'ingestion écrit désormais `side` (ordre des adversaires du fournisseur) ; ce rattrapage remplit l'existant.

-- 1. Depuis le nom du match, « Winners Match: VIT vs LOUD » : la gauche est la première équipe citée.
UPDATE "event_participant" p
SET "side" = CASE
    WHEN lower(ent."short_name") = lower(trim(split_part(split_part(e."name", ': ', -1), ' vs ', 1))) THEN 0
    WHEN lower(ent."short_name") = lower(trim(split_part(split_part(e."name", ': ', -1), ' vs ', 2))) THEN 1
  END
FROM "event" e, "entity" ent
WHERE p."event_id" = e."id" AND p."entity_id" = ent."id" AND p."side" IS NULL AND e."name" LIKE '% vs %';

-- 2. Le reste : à l'opposé de l'autre équipe si son côté est connu, sinon par identifiant (stable, arbitraire).
UPDATE "event_participant" p
SET "side" = COALESCE(
    (SELECT 1 - o."side" FROM "event_participant" o WHERE o."event_id" = p."event_id" AND o."id" <> p."id" AND o."side" IS NOT NULL LIMIT 1),
    r.rn - 1
)
FROM (
    SELECT "id", row_number() OVER (PARTITION BY "event_id" ORDER BY "id") AS rn
    FROM "event_participant"
    WHERE "side" IS NULL
) r
WHERE p."id" = r."id" AND p."side" IS NULL;
