-- CreateTable
CREATE TABLE "category" (
    "id" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "icon" TEXT,

    CONSTRAINT "category_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "competition" (
    "id" TEXT NOT NULL,
    "category_id" TEXT NOT NULL,
    "parent_id" TEXT,
    "kind" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "format" TEXT,
    "status" TEXT,
    "starts_at" TIMESTAMP(3),
    "ends_at" TIMESTAMP(3),
    "structure" JSONB,
    "importance" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "competition_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "entity" (
    "id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "short_name" TEXT,
    "parent_id" TEXT,
    "region" TEXT,
    "image_url" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "entity_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "event" (
    "id" TEXT NOT NULL,
    "competition_id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "starts_at" TIMESTAMP(3),
    "ends_at" TIMESTAMP(3),
    "best_of" INTEGER,
    "result" JSONB,
    "importance" INTEGER NOT NULL DEFAULT 0,
    "spoiler_sensitive" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "event_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "event_participant" (
    "id" TEXT NOT NULL,
    "event_id" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "side" INTEGER,
    "score" INTEGER,
    "is_winner" BOOLEAN,
    "seed" INTEGER,

    CONSTRAINT "event_participant_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "event_link" (
    "id" TEXT NOT NULL,
    "from_event_id" TEXT NOT NULL,
    "to_event_id" TEXT NOT NULL,
    "outcome" TEXT NOT NULL,
    "slot" INTEGER,

    CONSTRAINT "event_link_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "standing" (
    "id" TEXT NOT NULL,
    "competition_id" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "rank" INTEGER,
    "wins" INTEGER,
    "losses" INTEGER,
    "lives_left" INTEGER,
    "qualified" BOOLEAN,

    CONSTRAINT "standing_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "provider_ref" (
    "id" TEXT NOT NULL,
    "object_type" TEXT NOT NULL,
    "object_id" TEXT NOT NULL,
    "provider" TEXT NOT NULL,
    "external_id" TEXT NOT NULL,
    "last_synced_at" TIMESTAMP(3) NOT NULL,
    "payload_hash" TEXT NOT NULL,

    CONSTRAINT "provider_ref_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "provider_payload" (
    "id" TEXT NOT NULL,
    "provider" TEXT NOT NULL,
    "object_type" TEXT NOT NULL,
    "external_id" TEXT NOT NULL,
    "payload" JSONB NOT NULL,
    "fetched_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "provider_payload_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "category_slug_key" ON "category"("slug");

-- CreateIndex
CREATE UNIQUE INDEX "event_participant_event_id_entity_id_key" ON "event_participant"("event_id", "entity_id");

-- CreateIndex
CREATE UNIQUE INDEX "standing_competition_id_entity_id_key" ON "standing"("competition_id", "entity_id");

-- CreateIndex
CREATE UNIQUE INDEX "provider_ref_provider_object_type_external_id_key" ON "provider_ref"("provider", "object_type", "external_id");

-- AddForeignKey
ALTER TABLE "competition" ADD CONSTRAINT "competition_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "category"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "competition" ADD CONSTRAINT "competition_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "competition"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "entity" ADD CONSTRAINT "entity_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "entity"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "event" ADD CONSTRAINT "event_competition_id_fkey" FOREIGN KEY ("competition_id") REFERENCES "competition"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "event_participant" ADD CONSTRAINT "event_participant_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "event"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "event_participant" ADD CONSTRAINT "event_participant_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "entity"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "event_link" ADD CONSTRAINT "event_link_from_event_id_fkey" FOREIGN KEY ("from_event_id") REFERENCES "event"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "event_link" ADD CONSTRAINT "event_link_to_event_id_fkey" FOREIGN KEY ("to_event_id") REFERENCES "event"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "standing" ADD CONSTRAINT "standing_competition_id_fkey" FOREIGN KEY ("competition_id") REFERENCES "competition"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "standing" ADD CONSTRAINT "standing_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "entity"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
