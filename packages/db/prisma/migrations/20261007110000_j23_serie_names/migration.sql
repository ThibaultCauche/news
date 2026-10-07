-- Séries dont le nom complet n'était que l'année (« 2026 ») : le prochain passage du catalogue les renomme
-- « <ligue> <année> » et leur donne une famille. Le hash du provider_ref est invalidé pour forcer la réécriture.
UPDATE "provider_ref"
SET "payload_hash" = 'stale-j23'
WHERE "object_type" = 'competition'
  AND "object_id" IN (SELECT "id" FROM "competition" WHERE "kind" = 'serie' AND "name" ~ '^[0-9]{4}$');
