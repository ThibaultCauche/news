-- AlterTable
ALTER TABLE "forum_message" ADD COLUMN     "edited_at" TIMESTAMP(3),
ADD COLUMN     "is_spoiler" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "pinned_at" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "user_setting" ADD COLUMN     "notify_forum_threads" BOOLEAN NOT NULL DEFAULT true;

-- CreateTable
CREATE TABLE "forum_thread_follow" (
    "thread_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "last_notified_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "forum_thread_follow_pkey" PRIMARY KEY ("thread_id","user_id")
);

-- CreateTable
CREATE TABLE "moderation_log" (
    "id" TEXT NOT NULL,
    "moderator_id" TEXT,
    "action" TEXT NOT NULL,
    "target_user_id" TEXT,
    "message_id" TEXT,
    "thread_id" TEXT,
    "detail" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "moderation_log_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "forum_thread_follow_user_id_idx" ON "forum_thread_follow"("user_id");

-- CreateIndex
CREATE INDEX "moderation_log_created_at_idx" ON "moderation_log"("created_at");

-- AddForeignKey
ALTER TABLE "forum_thread_follow" ADD CONSTRAINT "forum_thread_follow_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "forum_thread"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "forum_thread_follow" ADD CONSTRAINT "forum_thread_follow_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "moderation_log" ADD CONSTRAINT "moderation_log_moderator_id_fkey" FOREIGN KEY ("moderator_id") REFERENCES "app_user"("id") ON DELETE SET NULL ON UPDATE CASCADE;

