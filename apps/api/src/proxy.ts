import type { INestApplication } from "@nestjs/common";
import type { Express } from "express";

/**
 * Derrière Tailscale Funnel, l'adresse de la connexion est celle du relais, pas celle du client : sans cela la
 * limite de requêtes (`ThrottlerModule`, par IP) est partagée par tous les utilisateurs (J19). `TRUST_PROXY` = nombre
 * de relais de confiance devant l'API (1 en prod) : Express lit alors l'IP du client dans `X-Forwarded-For`, en
 * partant de la droite, donc une valeur ajoutée par le client à gauche ne change pas son compteur. 0 (défaut) = rien.
 */
export function trustProxyHops(app: INestApplication, hops = Number(process.env.TRUST_PROXY ?? 0)): void {
  if (hops > 0) (app.getHttpAdapter().getInstance() as Express).set("trust proxy", hops);
}
