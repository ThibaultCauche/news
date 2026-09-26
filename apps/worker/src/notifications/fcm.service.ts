import { Injectable, OnModuleDestroy } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { createLogger } from "@news/domain";
import { App, cert, deleteApp, initializeApp } from "firebase-admin/app";
import { getMessaging, Messaging } from "firebase-admin/messaging";

const logger = createLogger("worker:fcm");

export interface SendResult {
  // Jeton mort (appareil désinstallé/réinstallé) : à l'appelant de nettoyer
  // l'appareil correspondant (docs/03 §6, docs/04 J4).
  tokenInvalid: boolean;
}

// Lazy : pas de credentials Firebase tant que `FIREBASE_*` n'est pas rempli (le
// projet est créé mais les clés pas encore ajoutées à `.env`) — on journalise
// sans envoyer plutôt que de planter le worker au démarrage.
@Injectable()
export class FcmService implements OnModuleDestroy {
  private app: App | null = null;

  constructor(private readonly config: ConfigService) {}

  private getMessaging(): Messaging | null {
    const projectId = this.config.get<string>("FIREBASE_PROJECT_ID");
    const clientEmail = this.config.get<string>("FIREBASE_CLIENT_EMAIL");
    const privateKey = this.config.get<string>("FIREBASE_PRIVATE_KEY");
    if (!projectId || !clientEmail || !privateKey) return null;
    if (!this.app) {
      this.app = initializeApp({ credential: cert({ projectId, clientEmail, privateKey: privateKey.replace(/\\n/g, "\n") }) });
    }
    return getMessaging(this.app);
  }

  async send(pushToken: string, title: string, body: string, data: Record<string, string>): Promise<SendResult> {
    const messaging = this.getMessaging();
    if (!messaging) {
      logger.warn({ title }, "FIREBASE_* absent, notification journalée mais pas envoyée");
      return { tokenInvalid: false };
    }
    try {
      await messaging.send({ token: pushToken, notification: { title, body }, data });
      return { tokenInvalid: false };
    } catch (err) {
      const code = (err as { code?: string }).code;
      if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token") {
        return { tokenInvalid: true };
      }
      // ponytail: pas de nouvelle tentative sur échec transitoire (réseau, quota
      // FCM) ; à ajouter si on observe des pertes en conditions réelles.
      logger.error(err, "échec d'envoi FCM");
      return { tokenInvalid: false };
    }
  }

  async onModuleDestroy(): Promise<void> {
    if (this.app) await deleteApp(this.app);
  }
}
