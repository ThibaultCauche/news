import { ConfigService } from "@nestjs/config";
import { Inject, Injectable } from "@nestjs/common";
import { createLogger } from "@news/domain";
import { PandaScoreProvider } from "@news/providers";
import { IngestionHeartbeatService } from "../ingestion/heartbeat.service";
import { FcmService } from "../notifications/fcm.service";
import { PANDASCORE_PROVIDER } from "../pandascore/pandascore.module";
import { INGESTION_STALE_THRESHOLD_MS, PUSH_FAILURE_ALERT_THRESHOLD, QUOTA_ALERT_THRESHOLD } from "./constants";

const logger = createLogger("worker:alerts");

// Supervision minimale (docs/03 §10) : pas de tableau de bord, un webhook texte
// (ntfy.sh ou équivalent) quand un des trois seuils est dépassé.
@Injectable()
export class AlertsService {
  constructor(
    private readonly heartbeat: IngestionHeartbeatService,
    @Inject(PANDASCORE_PROVIDER) private readonly provider: PandaScoreProvider,
    private readonly fcm: FcmService,
    private readonly config: ConfigService,
  ) {}

  async check(): Promise<void> {
    const problems: string[] = [];

    const lastSeenAt = await this.heartbeat.getLastSeenAt();
    if (lastSeenAt) {
      const staleMs = Date.now() - lastSeenAt.getTime();
      if (staleMs > INGESTION_STALE_THRESHOLD_MS) problems.push(`ingestion arrêtée depuis ${Math.round(staleMs / 60_000)} min`);
    }

    const quotaRatio = this.provider.quota.getUsageRatio();
    if (quotaRatio != null && quotaRatio > QUOTA_ALERT_THRESHOLD) problems.push(`quota PandaScore à ${Math.round(quotaRatio * 100)}%`);

    const failureRatio = this.fcm.getAndResetFailureRatio();
    if (failureRatio != null && failureRatio > PUSH_FAILURE_ALERT_THRESHOLD) {
      problems.push(`${Math.round(failureRatio * 100)}% des envois push ont échoué`);
    }

    if (problems.length === 0) return;
    logger.warn({ problems }, "seuil de supervision dépassé");
    await this.notify(problems);
  }

  private async notify(problems: string[]): Promise<void> {
    const url = this.config.get<string>("ALERT_WEBHOOK_URL");
    if (!url) return;
    try {
      await fetch(url, { method: "POST", body: `News : ${problems.join(" · ")}` });
    } catch (err) {
      logger.error(err, "échec d'envoi de l'alerte");
    }
  }
}
