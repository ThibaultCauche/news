/*
  Warnings:

  - You are about to drop the column `timezone` on the `device` table. All the data in the column will be lost.

*/
-- AlterTable
ALTER TABLE "device" DROP COLUMN "timezone",
ADD COLUMN     "utc_offset_minutes" INTEGER;
