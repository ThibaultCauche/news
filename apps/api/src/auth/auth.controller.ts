import { Body, Controller, Post } from "@nestjs/common";
import { ApiOkResponse } from "@nestjs/swagger";
import { AccessTokenDto, AuthService, AuthTokensDto } from "./auth.service";
import { RefreshDto } from "./refresh.dto";

// POST /v1/auth/anonymous, POST /v1/auth/refresh — compte anonyme au premier
// lancement, pas d'inscription (docs/03 §4, docs/04 J4).
@Controller("auth")
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post("anonymous")
  @ApiOkResponse({ type: AuthTokensDto })
  async createAnonymous(): Promise<AuthTokensDto> {
    return this.auth.createAnonymousUser();
  }

  @Post("refresh")
  @ApiOkResponse({ type: AccessTokenDto })
  async refresh(@Body() dto: RefreshDto): Promise<AccessTokenDto> {
    return this.auth.refreshAccessToken(dto.refreshToken);
  }
}
