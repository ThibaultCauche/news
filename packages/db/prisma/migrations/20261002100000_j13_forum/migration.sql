-- AlterTable
ALTER TABLE "app_user" ADD COLUMN     "forum_banned_at" TIMESTAMP(3),
ADD COLUMN     "forum_beta" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "is_moderator" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "terms_accepted_at" TIMESTAMP(3),
ADD COLUMN     "terms_version" INTEGER;

-- AlterTable
ALTER TABLE "user_setting" ADD COLUMN     "notify_forum_replies" BOOLEAN NOT NULL DEFAULT true;

-- CreateTable
CREATE TABLE "forum_thread" (
    "id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "target_id" TEXT,
    "game" TEXT,
    "title" TEXT NOT NULL,
    "created_by_id" TEXT,
    "locked_at" TIMESTAMP(3),
    "message_count" INTEGER NOT NULL DEFAULT 0,
    "last_message_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "forum_thread_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "forum_message" (
    "id" TEXT NOT NULL,
    "thread_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "parent_id" TEXT,
    "body" TEXT NOT NULL,
    "hidden_at" TIMESTAMP(3),
    "hidden_reason" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "forum_message_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "forum_reaction" (
    "message_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "emoji" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "forum_reaction_pkey" PRIMARY KEY ("message_id","user_id")
);

-- CreateTable
CREATE TABLE "forum_report" (
    "id" TEXT NOT NULL,
    "message_id" TEXT NOT NULL,
    "reporter_id" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "resolved_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "forum_report_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_block" (
    "blocker_id" TEXT NOT NULL,
    "blocked_id" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_block_pkey" PRIMARY KEY ("blocker_id","blocked_id")
);

-- CreateTable
CREATE TABLE "forum_camp" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "game" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "changed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "forum_camp_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "forum_thread_game_last_message_at_idx" ON "forum_thread"("game", "last_message_at");

-- CreateIndex
CREATE UNIQUE INDEX "forum_thread_kind_target_id_key" ON "forum_thread"("kind", "target_id");

-- CreateIndex
CREATE INDEX "forum_message_thread_id_created_at_idx" ON "forum_message"("thread_id", "created_at");

-- CreateIndex
CREATE INDEX "forum_message_user_id_idx" ON "forum_message"("user_id");

-- CreateIndex
CREATE INDEX "forum_report_resolved_at_idx" ON "forum_report"("resolved_at");

-- CreateIndex
CREATE UNIQUE INDEX "forum_report_message_id_reporter_id_key" ON "forum_report"("message_id", "reporter_id");

-- CreateIndex
CREATE UNIQUE INDEX "forum_camp_user_id_game_key" ON "forum_camp"("user_id", "game");

-- AddForeignKey
ALTER TABLE "forum_thread" ADD CONSTRAINT "forum_thread_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "app_user"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "forum_message" ADD CONSTRAINT "forum_message_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "forum_thread"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "forum_message" ADD CONSTRAINT "forum_message_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "forum_message" ADD CONSTRAINT "forum_message_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "forum_message"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "forum_reaction" ADD CONSTRAINT "forum_reaction_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "forum_message"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "forum_reaction" ADD CONSTRAINT "forum_reaction_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "forum_report" ADD CONSTRAINT "forum_report_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "forum_message"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "forum_report" ADD CONSTRAINT "forum_report_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_block" ADD CONSTRAINT "user_block_blocker_id_fkey" FOREIGN KEY ("blocker_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_block" ADD CONSTRAINT "user_block_blocked_id_fkey" FOREIGN KEY ("blocked_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "forum_camp" ADD CONSTRAINT "forum_camp_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

