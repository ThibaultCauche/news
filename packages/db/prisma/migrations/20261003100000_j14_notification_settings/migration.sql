-- AlterTable
ALTER TABLE "user_setting" ADD COLUMN     "notify_match_reminder" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "notify_match_result" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "notify_match_start" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "notify_prediction_reminders" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "notify_qualification" BOOLEAN NOT NULL DEFAULT true;
