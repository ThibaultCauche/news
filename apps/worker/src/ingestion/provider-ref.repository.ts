import { Prisma, PrismaClient, ProviderRef } from "@news/db";
import { computePayloadHash, shouldUpsert } from "@news/domain";

// Retrouve l'objet interne déjà lié à une référence externe (provider_ref),
// clé de l'ingestion idempotente (règle 4 de CLAUDE.md).
export function findProviderRef(
  prisma: PrismaClient,
  provider: string,
  objectType: string,
  externalId: string,
): Promise<ProviderRef | null> {
  return prisma.providerRef.findUnique({
    where: { provider_objectType_externalId: { provider, objectType, externalId } },
  });
}

// Enregistre le lien vers l'objet interne et garde la réponse brute 7 jours
// (docs/03 §3) — appelé uniquement quand quelque chose a changé.
export async function commitProviderRef(
  prisma: PrismaClient,
  params: { provider: string; objectType: string; externalId: string; objectId: string; payloadHash: string; raw: unknown },
): Promise<void> {
  const { provider, objectType, externalId, objectId, payloadHash, raw } = params;
  await prisma.providerRef.upsert({
    where: { provider_objectType_externalId: { provider, objectType, externalId } },
    create: { provider, objectType, externalId, objectId, payloadHash, lastSyncedAt: new Date() },
    update: { objectId, payloadHash, lastSyncedAt: new Date() },
  });
  await prisma.providerPayload.create({
    data: { provider, objectType, externalId, payload: raw as Prisma.InputJsonValue },
  });
}

// Upsert générique pour un objet sans logique métier annexe (compétition, entité) :
// ne réécrit rien si le hash n'a pas changé (règle 4).
export async function upsertByProviderRef(
  prisma: PrismaClient,
  params: {
    provider: string;
    objectType: string;
    externalId: string;
    raw: unknown;
    write: (existingObjectId: string | null) => Promise<string>;
  },
): Promise<{ objectId: string; changed: boolean }> {
  const { provider, objectType, externalId, raw, write } = params;
  const hash = computePayloadHash(raw);
  const existing = await findProviderRef(prisma, provider, objectType, externalId);
  if (existing && !shouldUpsert(existing.payloadHash, hash)) {
    return { objectId: existing.objectId, changed: false };
  }
  const objectId = await write(existing?.objectId ?? null);
  await commitProviderRef(prisma, { provider, objectType, externalId, objectId, payloadHash: hash, raw });
  return { objectId, changed: true };
}
