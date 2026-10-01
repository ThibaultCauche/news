-- Le nombre de messages se compte a la lecture (la suppression de compte le ferait deriver).
ALTER TABLE "forum_thread" DROP COLUMN "message_count";
