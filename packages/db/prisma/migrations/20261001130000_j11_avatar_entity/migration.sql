-- J11 : l'avatar devient le logo d'une équipe (avant : identifiant d'icône, plus valable).
ALTER TABLE "app_user" RENAME COLUMN "avatar" TO "avatar_entity_id";
UPDATE "app_user" SET "avatar_entity_id" = NULL;
