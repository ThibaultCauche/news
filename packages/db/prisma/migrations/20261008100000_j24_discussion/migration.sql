-- AlterTable
ALTER TABLE "forum_message" ADD COLUMN     "idea_status" TEXT,
ADD COLUMN     "kind" TEXT NOT NULL DEFAULT 'text',
ADD COLUMN     "payload" JSONB,
ADD COLUMN     "ref_id" TEXT;

-- AlterTable
ALTER TABLE "forum_thread" ADD COLUMN     "group_id" TEXT;

-- CreateTable
CREATE TABLE "forum_thread_member" (
    "thread_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,

    CONSTRAINT "forum_thread_member_pkey" PRIMARY KEY ("thread_id","user_id")
);

-- CreateTable
CREATE TABLE "forum_thread_read" (
    "thread_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "last_read_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_notified_at" TIMESTAMP(3),

    CONSTRAINT "forum_thread_read_pkey" PRIMARY KEY ("thread_id","user_id")
);

-- CreateTable
CREATE TABLE "forum_poll_vote" (
    "message_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "option" INTEGER NOT NULL,

    CONSTRAINT "forum_poll_vote_pkey" PRIMARY KEY ("message_id","user_id")
);

-- CreateIndex
CREATE INDEX "forum_thread_member_user_id_idx" ON "forum_thread_member"("user_id");

-- CreateIndex
CREATE INDEX "forum_thread_read_user_id_idx" ON "forum_thread_read"("user_id");

-- AddForeignKey
ALTER TABLE "forum_thread" ADD CONSTRAINT "forum_thread_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "friend_group"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "forum_thread_member" ADD CONSTRAINT "forum_thread_member_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "forum_thread"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "forum_thread_member" ADD CONSTRAINT "forum_thread_member_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "forum_thread_read" ADD CONSTRAINT "forum_thread_read_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "forum_thread"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "forum_thread_read" ADD CONSTRAINT "forum_thread_read_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "forum_poll_vote" ADD CONSTRAINT "forum_poll_vote_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "forum_message"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "forum_poll_vote" ADD CONSTRAINT "forum_poll_vote_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

