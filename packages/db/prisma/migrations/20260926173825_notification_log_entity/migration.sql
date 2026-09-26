-- DropForeignKey
ALTER TABLE "notification_log" DROP CONSTRAINT "notification_log_event_id_fkey";

-- AlterTable
ALTER TABLE "notification_log" ADD COLUMN     "entity_id" TEXT,
ALTER COLUMN "event_id" DROP NOT NULL;

-- CreateIndex
CREATE UNIQUE INDEX "notification_log_user_id_entity_id_type_key" ON "notification_log"("user_id", "entity_id", "type");

-- AddForeignKey
ALTER TABLE "notification_log" ADD CONSTRAINT "notification_log_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "event"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_log" ADD CONSTRAINT "notification_log_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "entity"("id") ON DELETE SET NULL ON UPDATE CASCADE;

