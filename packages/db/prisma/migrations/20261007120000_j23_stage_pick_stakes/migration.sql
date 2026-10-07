-- DropIndex
DROP INDEX "notification_log_user_id_entity_id_type_key";

-- AlterTable
ALTER TABLE "event" ADD COLUMN     "stakes" TEXT;

-- AlterTable
ALTER TABLE "notification_log" ADD COLUMN     "competition_id" TEXT;

-- CreateTable
CREATE TABLE "stage_pick" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "competition_id" TEXT NOT NULL,
    "entity_ids" JSONB NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "stage_pick_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "stage_pick_user_id_competition_id_key" ON "stage_pick"("user_id", "competition_id");

-- CreateIndex
CREATE UNIQUE INDEX "notification_log_user_id_entity_id_competition_id_type_key" ON "notification_log"("user_id", "entity_id", "competition_id", "type");

-- AddForeignKey
ALTER TABLE "stage_pick" ADD CONSTRAINT "stage_pick_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stage_pick" ADD CONSTRAINT "stage_pick_competition_id_fkey" FOREIGN KEY ("competition_id") REFERENCES "competition"("id") ON DELETE CASCADE ON UPDATE CASCADE;

