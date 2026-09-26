import { createParamDecorator, ExecutionContext } from "@nestjs/common";
import { RequestWithUser } from "./jwt-auth.guard";

// À utiliser avec `JwtAuthGuard` (jamais `null`) ou `OptionalUserGuard` (peut
// être `null`) : ces deux guards sont les seuls à remplir `req.user`.
export const CurrentUser = createParamDecorator((_data: unknown, ctx: ExecutionContext) => {
  return ctx.switchToHttp().getRequest<RequestWithUser>().user ?? null;
});
