-- AlterTable
ALTER TABLE "bracket_pick_bonus" DROP CONSTRAINT "bracket_pick_bonus_pkey",
ADD COLUMN     "kind" TEXT NOT NULL DEFAULT 'perfect',
ADD CONSTRAINT "bracket_pick_bonus_pkey" PRIMARY KEY ("user_id", "competition_id", "kind");

-- AlterTable
ALTER TABLE "stage_pick" ADD COLUMN     "points" INTEGER,
ADD COLUMN     "settled_at" TIMESTAMP(3);

