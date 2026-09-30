import { Body, Controller, Post } from "@nestjs/common";
import { ApiOkResponse } from "@nestjs/swagger";
import { AccessTokenDto, AuthService, AuthTokensDto } from "./auth.service";
import { FirebaseLoginDto } from "./firebase-login.dto";
import { RefreshDto } from "./refresh.dto";

// POST /v1/auth/firebase, POST /v1/auth/refresh — inscription possible (J11) : compte
// Firebase e-mail + mot de passe échangé contre nos JWT ; l'invité navigue sans jeton.
@Controller("auth")
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post("firebase")
  @ApiOkResponse({ type: AuthTokensDto })
  async loginWithFirebase(@Body() dto: FirebaseLoginDto): Promise<AuthTokensDto> {
    return this.auth.loginWithFirebase(dto.idToken);
  }

  @Post("refresh")
  @ApiOkResponse({ type: AccessTokenDto })
  async refresh(@Body() dto: RefreshDto): Promise<AccessTokenDto> {
    return this.auth.refreshAccessToken(dto.refreshToken);
  }
}
