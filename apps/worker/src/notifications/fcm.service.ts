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
  // Fenêtre glissante pour l'alerte "échecs d'envoi push > 5%" (docs/03 §10) ;
  // un jeton invalide (désinstallation) n'est pas une panne, seule une vraie
  // erreur d'envoi compte.
  private windowSent = 0;
  private windowFailed = 0;

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

  // Message « data » seul (J22) : l'appli le transforme en notification avec le logo de l'équipe en petite
  // icône (`local_notifications.dart`), ce que FCM ne sait pas faire (grande image seulement). `tag` (J21) :
  // une notification qui porte le même tag en remplace la précédente, donc un match = une notification.
  // Priorité haute pour une livraison immédiate, même appli fermée (pas « arrêtée de force »).
  // ponytail: Android seulement ; iOS (reporté) demandera un bloc `notification` + `apns` en plus.
  async send(pushToken: string, title: string, body: string, data: Record<string, string>, tag?: string, imageUrl?: string): Promise<SendResult> {
    const messaging = this.getMessaging();
    if (!messaging) {
      logger.warn({ title }, "FIREBASE_* absent, notification journalée mais pas envoyée");
      return { tokenInvalid: false };
    }
    try {
      await messaging.send({
        token: pushToken,
        data: { ...data, title, body, ...(tag ? { tag } : {}), ...(imageUrl ? { imageUrl } : {}) },
        android: { priority: "high" },
      });
      this.windowSent++;
      return { tokenInvalid: false };
    } catch (err) {
      const code = (err as { code?: string }).code;
      if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token") {
        return { tokenInvalid: true };
      }
      // ponytail: pas de nouvelle tentative sur échec transitoire (réseau, quota
      // FCM) ; à ajouter si on observe des pertes en conditions réelles.
      this.windowFailed++;
      logger.error(err, "échec d'envoi FCM");
      return { tokenInvalid: false };
    }
  }

  // Ratio d'échec depuis le dernier appel, remis à zéro à chaque lecture
  // (AlertsService, toutes les 5 min). `null` si aucun envoi dans la fenêtre.
  getAndResetFailureRatio(): number | null {
    const total = this.windowSent + this.windowFailed;
    const ratio = total === 0 ? null : this.windowFailed / total;
    this.windowSent = 0;
    this.windowFailed = 0;
    return ratio;
  }

  async onModuleDestroy(): Promise<void> {
    if (this.app) await deleteApp(this.app);
  }
}
