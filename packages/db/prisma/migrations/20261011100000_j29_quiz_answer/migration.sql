-- CreateTable
CREATE TABLE "quiz_answer" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "quiz_day" TEXT NOT NULL,
    "question_id" TEXT NOT NULL,
    "choice" TEXT NOT NULL,
    "correct" BOOLEAN NOT NULL,
    "answered_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "quiz_answer_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "quiz_answer_user_id_quiz_day_idx" ON "quiz_answer"("user_id", "quiz_day");

-- CreateIndex
CREATE UNIQUE INDEX "quiz_answer_user_id_question_id_key" ON "quiz_answer"("user_id", "question_id");

-- AddForeignKey
ALTER TABLE "quiz_answer" ADD CONSTRAINT "quiz_answer_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;
