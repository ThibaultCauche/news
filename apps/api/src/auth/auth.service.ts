import { randomUUID } from "node:crypto";
import { Inject, Injectable, UnauthorizedException } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { ConfigService } from "@nestjs/config";
import { JwtService } from "@nestjs/jwt";
import { PrismaClient } from "@news/db";
import { PRISMA } from "../db/db.module";
import { AuthUser } from "./auth.types";
import { FirebaseAuthService } from "./firebase-auth.service";

const ACCESS_TOKEN_TTL = "1h";
const REFRESH_TOKEN_TTL = "180d";

export class AuthTokensDto {
  @ApiProperty() userId!: string;
  @ApiProperty() accessToken!: string;
  @ApiProperty() refreshToken!: string;
}

export class AccessTokenDto {
  @ApiProperty() accessToken!: string;
}

interface AccessTokenPayload {
  sub: string;
}

// Comptes Firebase Auth (e-mail + mot de passe, J11) : l'appli se connecte à Firebase, puis
// échange l'ID token contre nos JWT (accès court + rafraîchissement, docs/03 §4). Les gardes
// et le rafraîchissement restent ceux du J4. L'invité n'a ni compte ni jeton.
@Injectable()
export class AuthService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly firebase: FirebaseAuthService,
  ) {}

  private get accessSecret(): string {
    return this.config.getOrThrow<string>("JWT_SECRET");
  }

  private get refreshSecret(): string {
    return this.config.getOrThrow<string>("JWT_REFRESH_SECRET");
  }

  private issueAccessToken(userId: string): string {
    return this.jwt.sign({ sub: userId }, { secret: this.accessSecret, expiresIn: ACCESS_TOKEN_TTL });
  }

  // Crée le compte à la première connexion, le retrouve ensuite ; met à jour `emailVerified`
  // (l'appli se reconnecte après le clic sur le lien de vérification).
  async loginWithFirebase(idToken: string): Promise<AuthTokensDto> {
    const identity = await this.firebase.verifyIdToken(idToken);
    // Réglages créés avec le compte : `GET /v1/me/settings` peut compter sur leur présence.
    const user = await this.prisma.appUser.upsert({
      where: { firebaseUid: identity.uid },
      update: { emailVerified: identity.emailVerified },
      create: { id: randomUUID(), firebaseUid: identity.uid, emailVerified: identity.emailVerified, setting: { create: { id: randomUUID() } } },
    });
    return {
      userId: user.id,
      accessToken: this.issueAccessToken(user.id),
      refreshToken: this.jwt.sign({ sub: user.id }, { secret: this.refreshSecret, expiresIn: REFRESH_TOKEN_TTL }),
    };
  }

  async refreshAccessToken(refreshToken: string): Promise<AccessTokenDto> {
    let payload: AccessTokenPayload;
    try {
      payload = this.jwt.verify<AccessTokenPayload>(refreshToken, { secret: this.refreshSecret });
    } catch {
      throw new UnauthorizedException("Jeton de rafraîchissement invalide");
    }
    const user = await this.prisma.appUser.findUnique({ where: { id: payload.sub }, select: { id: true } });
    if (!user) throw new UnauthorizedException("Compte introuvable");
    return { accessToken: this.issueAccessToken(user.id) };
  }

  // `null` si l'en-tête est absent/invalide ou si le compte a été supprimé (RGPD,
  // `DELETE /v1/me`) : un jeton signé mais orphelin ne doit plus rien autoriser.
  async getUserFromHeader(header: string | undefined): Promise<AuthUser | null> {
    const token = header?.startsWith("Bearer ") ? header.slice(7) : null;
    if (!token) return null;
    try {
      const payload = this.jwt.verify<AccessTokenPayload>(token, { secret: this.accessSecret });
      return await this.prisma.appUser.findUnique({ where: { id: payload.sub }, select: { id: true } });
    } catch {
      return null;
    }
  }

  async requireUserFromHeader(header: string | undefined): Promise<AuthUser> {
    const user = await this.getUserFromHeader(header);
    if (!user) throw new UnauthorizedException();
    return user;
  }
}
