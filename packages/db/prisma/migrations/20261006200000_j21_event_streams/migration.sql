-- AlterTable
ALTER TABLE "event" DROP COLUMN "stream_url";
ALTER TABLE "event" ADD COLUMN "streams" JSONB;

-- CreateTable
CREATE TABLE "stream_channel" (
    "login" TEXT NOT NULL,
    "display_name" TEXT,
    "image_url" TEXT,
    "live" BOOLEAN NOT NULL DEFAULT false,
    "profile_checked_at" TIMESTAMP(3),
    "live_checked_at" TIMESTAMP(3),

    CONSTRAINT "stream_channel_pkey" PRIMARY KEY ("login")
);

-- Les matchs deja ingeres n'ont pas leurs chaines : on invalide leur empreinte pour que la
-- prochaine ingestion les reecrive.
UPDATE "provider_ref" SET "payload_hash" = '' WHERE "object_type" = 'event';
