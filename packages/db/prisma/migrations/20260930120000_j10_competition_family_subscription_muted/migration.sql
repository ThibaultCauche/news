-- Familles de compétitions et sourdine des abonnements (J10).

-- CreateTable
CREATE TABLE "competition_family" (
    "id" TEXT NOT NULL,
    "league_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,

    CONSTRAINT "competition_family_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "competition_family_league_id_name_key" ON "competition_family"("league_id", "name");

-- AddForeignKey
ALTER TABLE "competition_family" ADD CONSTRAINT "competition_family_league_id_fkey" FOREIGN KEY ("league_id") REFERENCES "competition"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AlterTable
ALTER TABLE "competition" ADD COLUMN "family_id" TEXT;

-- AddForeignKey
ALTER TABLE "competition" ADD CONSTRAINT "competition_family_id_fkey" FOREIGN KEY ("family_id") REFERENCES "competition_family"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AlterTable
ALTER TABLE "subscription" ADD COLUMN "muted" BOOLEAN NOT NULL DEFAULT false;

-- Rattrapage des séries existantes : mêmes règles que `familyNameOf` (packages/domain/src/family.ts) —
-- année finale retirée, « Masters <ville> » regroupé en « Masters », pas de famille pour un nom réduit à l'année.
CREATE TEMP TABLE serie_family AS
SELECT c.id AS serie_id,
       c.parent_id AS league_id,
       CASE
         WHEN regexp_replace(c.name, '\s*\m\d{4}$', '') LIKE 'Masters %' THEN 'Masters'
         ELSE trim(regexp_replace(c.name, '\s*\m\d{4}$', ''))
       END AS name
FROM "competition" c
WHERE c.kind = 'serie' AND c.parent_id IS NOT NULL AND c.name !~ '^\s*\d{4}\s*$';

INSERT INTO "competition_family" ("id", "league_id", "name")
SELECT gen_random_uuid()::text, league_id, name FROM (SELECT DISTINCT league_id, name FROM serie_family WHERE name <> '') f;

UPDATE "competition" c
SET "family_id" = f."id"
FROM serie_family s
JOIN "competition_family" f ON f."league_id" = s.league_id AND f."name" = s.name
WHERE c."id" = s.serie_id;

DROP TABLE serie_family;
