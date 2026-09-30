import { Module } from "@nestjs/common";
import { JwtModule } from "@nestjs/jwt";
import { DbModule } from "../db/db.module";
import { AuthController } from "./auth.controller";
import { AuthService } from "./auth.service";
import { FirebaseAuthService } from "./firebase-auth.service";
import { JwtAuthGuard, OptionalUserGuard } from "./jwt-auth.guard";

// Pas de secret par défaut sur `JwtModule` : `AuthService` signe/vérifie avec
// `JWT_SECRET` (accès) ou `JWT_REFRESH_SECRET` (rafraîchissement) au cas par cas.
@Module({
  imports: [DbModule, JwtModule.register({})],
  controllers: [AuthController],
  providers: [AuthService, FirebaseAuthService, JwtAuthGuard, OptionalUserGuard],
  exports: [AuthService, FirebaseAuthService, JwtAuthGuard, OptionalUserGuard],
})
export class AuthModule {}
