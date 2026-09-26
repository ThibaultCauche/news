-- AlterTable
ALTER TABLE "competition" ADD COLUMN     "has_bracket" BOOLEAN NOT NULL DEFAULT false;

-- CreateIndex
CREATE UNIQUE INDEX "event_link_from_event_id_outcome_key" ON "event_link"("from_event_id", "outcome");

