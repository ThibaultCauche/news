import { CanActivate, ExecutionContext, Injectable } from "@nestjs/common";
import type { Request } from "express";
import { AuthService } from "./auth.service";
import { AuthUser } from "./auth.types";

export interface RequestWithUser extends Request {
  user?: AuthUser | null;
}

// Guard obligatoire : 401 si le jeton est absent, invalide, expiré, ou si le
// compte a été supprimé depuis (docs/03 §4).
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly auth: AuthService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest<RequestWithUser>();
    req.user = await this.auth.requireUserFromHeader(req.headers.authorization);
    return true;
  }
}

// Guard tolérant pour `/v1/home` : personnalise si un jeton valide est fourni,
// répond quand même sans utilisateur sinon (docs/04 J4 : version sans compte
// toujours servie, comme au J2).
@Injectable()
export class OptionalUserGuard implements CanActivate {
  constructor(private readonly auth: AuthService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest<RequestWithUser>();
    req.user = await this.auth.getUserFromHeader(req.headers.authorization);
    return true;
  }
}
