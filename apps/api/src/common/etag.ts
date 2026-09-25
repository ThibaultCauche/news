import { createHash } from "node:crypto";
import type { Request, Response } from "express";

// Envoie un ETag sur le corps JSON et répond 304 si le client l'a déjà (docs/03
// §4) : pendant un direct, l'appli redemande souvent, presque gratuit grâce au 304.
// `import type` : pas besoin d'`express` au runtime, seulement de ses types.
export function sendWithEtag(req: Request, res: Response, body: unknown): void {
  const etag = `"${createHash("sha1").update(JSON.stringify(body)).digest("hex")}"`;
  res.setHeader("ETag", etag);
  res.setHeader("Cache-Control", "public, max-age=15");
  if (req.headers["if-none-match"] === etag) {
    res.status(304).end();
    return;
  }
  res.json(body);
}
