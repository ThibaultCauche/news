-- AlterTable
ALTER TABLE "competition" ADD COLUMN "image_url" TEXT;

-- Rattrapage : force la réécriture des ligues au prochain passage du catalogue
-- (le hash inchangé ferait sinon sauter l'écriture du logo).
UPDATE "provider_ref" SET "payload_hash" = ''
WHERE "object_type" = 'competition' AND "object_id" IN (SELECT "id" FROM "competition" WHERE "kind" = 'league');
