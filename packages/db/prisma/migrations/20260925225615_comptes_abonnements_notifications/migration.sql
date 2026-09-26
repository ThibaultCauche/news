-- CreateTable
CREATE TABLE "app_user" (
    "id" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "app_user_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "device" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "install_id" TEXT NOT NULL,
    "push_token" TEXT,
    "platform" TEXT NOT NULL,
    "locale" TEXT,
    "timezone" TEXT,
    "live_activity_token" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "device_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "subscription" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "target_type" TEXT NOT NULL,
    "target_id" TEXT NOT NULL,
    "level" TEXT NOT NULL DEFAULT 'all',
    "notify_reminder" BOOLEAN NOT NULL DEFAULT true,
    "notify_start" BOOLEAN NOT NULL DEFAULT true,
    "notify_result" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "subscription_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_setting" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "spoiler_free" BOOLEAN NOT NULL DEFAULT true,
    "quiet_hours_start" INTEGER,
    "quiet_hours_end" INTEGER,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "user_setting_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notification_log" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "event_id" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "sent_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notification_log_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "device_user_id_install_id_key" ON "device"("user_id", "install_id");

-- CreateIndex
CREATE UNIQUE INDEX "subscription_user_id_target_type_target_id_key" ON "subscription"("user_id", "target_type", "target_id");

-- CreateIndex
CREATE UNIQUE INDEX "user_setting_user_id_key" ON "user_setting"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "notification_log_user_id_event_id_type_key" ON "notification_log"("user_id", "event_id", "type");

-- AddForeignKey
ALTER TABLE "device" ADD CONSTRAINT "device_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscription" ADD CONSTRAINT "subscription_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_setting" ADD CONSTRAINT "user_setting_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_log" ADD CONSTRAINT "notification_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "app_user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_log" ADD CONSTRAINT "notification_log_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "event"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
