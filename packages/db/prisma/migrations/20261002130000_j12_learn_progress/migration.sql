-- CreateTable
CREATE TABLE "learn_progress" (
    "user_id" TEXT NOT NULL,
    "guide" TEXT NOT NULL,
    "article_id" TEXT NOT NULL,
    "quiz_passed" BOOLEAN NOT NULL DEFAULT false,
    "first_read_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "learn_progress_pkey" PRIMARY KEY ("user_id","guide","article_id")
);

-- AddForeignKey
ALTER TABLE "learn_progress" ADD CONSTRAINT "learn_progress_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;
