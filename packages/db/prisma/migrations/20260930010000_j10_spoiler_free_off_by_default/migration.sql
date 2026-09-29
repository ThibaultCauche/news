-- Sans spoil désactivé par défaut pour les nouveaux comptes (J10). Les comptes existants
-- gardent leur réglage : seul le défaut de la colonne change.
ALTER TABLE "user_setting" ALTER COLUMN "spoiler_free" SET DEFAULT false;
