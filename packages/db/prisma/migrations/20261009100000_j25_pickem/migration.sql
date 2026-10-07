-- CreateTable
CREATE TABLE "bracket_pick" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "competition_id" TEXT NOT NULL,
    "event_id" TEXT NOT NULL,
    "picked_entity_id" TEXT NOT NULL,
    "points" INTEGER,
    "settled_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "bracket_pick_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "bracket_pick_bonus" (
    "user_id" TEXT NOT NULL,
    "competition_id" TEXT NOT NULL,
    "points" INTEGER NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "bracket_pick_bonus_pkey" PRIMARY KEY ("user_id","competition_id")
);

-- CreateIndex
CREATE INDEX "bracket_pick_competition_id_idx" ON "bracket_pick"("competition_id");

-- CreateIndex
CREATE UNIQUE INDEX "bracket_pick_user_id_event_id_key" ON "bracket_pick"("user_id", "event_id");

-- AddForeignKey
ALTER TABLE "bracket_pick" ADD CONSTRAINT "bracket_pick_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bracket_pick" ADD CONSTRAINT "bracket_pick_competition_id_fkey" FOREIGN KEY ("competition_id") REFERENCES "competition"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bracket_pick" ADD CONSTRAINT "bracket_pick_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "event"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bracket_pick_bonus" ADD CONSTRAINT "bracket_pick_bonus_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bracket_pick_bonus" ADD CONSTRAINT "bracket_pick_bonus_competition_id_fkey" FOREIGN KEY ("competition_id") REFERENCES "competition"("id") ON DELETE CASCADE ON UPDATE CASCADE;

