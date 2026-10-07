-- CreateTable
CREATE TABLE "organization" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "image_url" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "organization_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "organization_key_key" ON "organization"("key");

-- AlterTable
ALTER TABLE "entity" ADD COLUMN "organization_id" TEXT;

-- CreateIndex
CREATE INDEX "entity_organization_id_idx" ON "entity"("organization_id");

-- AddForeignKey
ALTER TABLE "entity" ADD CONSTRAINT "entity_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "organization"("id") ON DELETE SET NULL ON UPDATE CASCADE;
