-- AlterTable
ALTER TABLE "event" ADD COLUMN "stream_url" TEXT;

-- Les matchs deja ingeres n'ont pas de lien : on invalide leur empreinte pour que la prochaine
-- ingestion les reecrive (sinon un match dont le payload ne change plus ne l'aurait jamais).
UPDATE "provider_ref" SET "payload_hash" = '' WHERE "object_type" = 'event';
