// Les specs d'intégration font `new PrismaClient()` directement (pas via Nest/
// ConfigModule), donc `DATABASE_URL` doit déjà être dans process.env avant que
// Jest ne les charge — sinon `pnpm -r test` échoue sans le wrapper dotenv-cli
// utilisé par les autres scripts racine (api:dev, db:migrate…).
require("dotenv").config({ path: require("path").resolve(__dirname, "../../.env") });

/** @type {import('jest').Config} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  testMatch: ["<rootDir>/src/**/*.spec.ts"],
};
