-- AlterTable
ALTER TABLE "user_setting" ADD COLUMN     "morning_digest" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "context_snippet" (
    "id" TEXT NOT NULL,
    "target_type" TEXT NOT NULL,
    "target_id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "text" TEXT NOT NULL,
    "source" TEXT,
    "license" TEXT,
    "generated_by" TEXT NOT NULL,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "context_snippet_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "context_snippet_target_type_target_id_kind_key" ON "context_snippet"("target_type", "target_id", "kind");

