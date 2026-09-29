-- AlterTable
ALTER TABLE "competition" ADD COLUMN     "game" TEXT;

-- CreateTable
CREATE TABLE "favorite_game" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "game" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "favorite_game_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "favorite_game_user_id_game_key" ON "favorite_game"("user_id", "game");

-- AddForeignKey
ALTER TABLE "favorite_game" ADD CONSTRAINT "favorite_game_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Rattrapage : l'ingestion ne couvrait que Valorant avant ce jalon.
UPDATE "competition" SET "game" = 'valorant' WHERE "game" IS NULL;
