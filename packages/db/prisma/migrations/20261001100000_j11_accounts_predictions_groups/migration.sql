-- J11 : les comptes anonymes disparaissent (décision du 2026-10-01, base fraîche : comptes Firebase seulement).
DELETE FROM "app_user";

-- AlterTable
ALTER TABLE "app_user" ADD COLUMN     "email_verified" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "firebase_uid" TEXT,
ADD COLUMN     "pseudo" TEXT,
ADD COLUMN     "pseudo_changed_at" TIMESTAMP(3),
ADD COLUMN     "pseudo_key" TEXT;

-- CreateTable
CREATE TABLE "prediction" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "event_id" TEXT NOT NULL,
    "picked_entity_id" TEXT NOT NULL,
    "picked_score" INTEGER,
    "other_score" INTEGER,
    "points" INTEGER,
    "settled_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "prediction_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "friend_group" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "owner_id" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "friend_group_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "friend_group_member" (
    "group_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "joined_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "friend_group_member_pkey" PRIMARY KEY ("group_id","user_id")
);

-- CreateIndex
CREATE INDEX "prediction_event_id_idx" ON "prediction"("event_id");

-- CreateIndex
CREATE UNIQUE INDEX "prediction_user_id_event_id_key" ON "prediction"("user_id", "event_id");

-- CreateIndex
CREATE UNIQUE INDEX "friend_group_code_key" ON "friend_group"("code");

-- CreateIndex
CREATE INDEX "friend_group_member_user_id_idx" ON "friend_group_member"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "app_user_firebase_uid_key" ON "app_user"("firebase_uid");

-- CreateIndex
CREATE UNIQUE INDEX "app_user_pseudo_key_key" ON "app_user"("pseudo_key");

-- AddForeignKey
ALTER TABLE "prediction" ADD CONSTRAINT "prediction_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "prediction" ADD CONSTRAINT "prediction_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "event"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "friend_group" ADD CONSTRAINT "friend_group_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "friend_group_member" ADD CONSTRAINT "friend_group_member_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "friend_group"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "friend_group_member" ADD CONSTRAINT "friend_group_member_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

