import { ConfigService } from "@nestjs/config";
import { AlertsService } from "./alerts.service";

// Unitaire, pure logique de seuils (docs/03 §10) : Prisma, le provider PandaScore
// et FcmService sont simulés, un vrai webhook n'a rien à faire dans un test.
describe("AlertsService", () => {
  function makeService(opts: {
    lastSyncedAt: Date | null;
    quotaRatio: number | null;
    failureRatio: number | null;
    webhookUrl?: string;
  }) {
    const prisma = { providerRef: { aggregate: jest.fn().mockResolvedValue({ _max: { lastSyncedAt: opts.lastSyncedAt } }) } };
    const provider = { quota: { getUsageRatio: () => opts.quotaRatio } };
    const fcm = { getAndResetFailureRatio: () => opts.failureRatio };
    const config = new ConfigService(opts.webhookUrl ? { ALERT_WEBHOOK_URL: opts.webhookUrl } : {});
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const service = new AlertsService(prisma as any, provider as any, fcm as any, config);
    return service;
  }

  beforeEach(() => {
    global.fetch = jest.fn().mockResolvedValue({});
  });

  it("n'alerte pas quand tout est sous les seuils", async () => {
    const service = makeService({ lastSyncedAt: new Date(), quotaRatio: 0.1, failureRatio: 0, webhookUrl: "https://ntfy.sh/test" });
    await service.check();
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it("alerte quand l'ingestion est arrêtée depuis plus de 15 min", async () => {
    const service = makeService({
      lastSyncedAt: new Date(Date.now() - 20 * 60 * 1000),
      quotaRatio: 0.1,
      failureRatio: 0,
      webhookUrl: "https://ntfy.sh/test",
    });
    await service.check();
    expect(global.fetch).toHaveBeenCalledWith("https://ntfy.sh/test", expect.objectContaining({ body: expect.stringContaining("ingestion arrêtée") }));
  });

  it("alerte quand le quota dépasse 80%", async () => {
    const service = makeService({ lastSyncedAt: new Date(), quotaRatio: 0.85, failureRatio: 0, webhookUrl: "https://ntfy.sh/test" });
    await service.check();
    expect(global.fetch).toHaveBeenCalledWith("https://ntfy.sh/test", expect.objectContaining({ body: expect.stringContaining("quota") }));
  });

  it("alerte quand plus de 5% des envois push échouent", async () => {
    const service = makeService({ lastSyncedAt: new Date(), quotaRatio: 0.1, failureRatio: 0.2, webhookUrl: "https://ntfy.sh/test" });
    await service.check();
    expect(global.fetch).toHaveBeenCalledWith("https://ntfy.sh/test", expect.objectContaining({ body: expect.stringContaining("envois push") }));
  });

  it("ne tente pas d'envoyer le webhook si ALERT_WEBHOOK_URL n'est pas configuré", async () => {
    const service = makeService({ lastSyncedAt: new Date(Date.now() - 999 * 60 * 1000), quotaRatio: null, failureRatio: null });
    await service.check();
    expect(global.fetch).not.toHaveBeenCalled();
  });
});
