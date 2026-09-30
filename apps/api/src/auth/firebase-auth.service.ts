import { Injectable, ServiceUnavailableException, UnauthorizedException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import type { Auth } from "firebase-admin/auth";

export interface FirebaseIdentity {
  uid: string;
  emailVerified: boolean;
}

// Vérifie les ID tokens Firebase Auth (e-mail + mot de passe, J11) et supprime le compte
// Firebase à la suppression RGPD. Lazy comme `FcmService` du worker : sans `FIREBASE_*`,
// l'API démarre quand même (la lecture sans compte reste servie), seule la connexion échoue.
// Les tests e2e remplacent ce service (voir `test-utils.ts`).
@Injectable()
export class FirebaseAuthService {
  private auth: Auth | null = null;

  constructor(private readonly config: ConfigService) {}

  // Import dynamique : `firebase-admin` tire `jose` (ESM), que Jest ne sait pas charger ; les
  // e2e remplacent ce service et ne doivent pas déclencher l'import.
  private async getAuth(): Promise<Auth> {
    const projectId = this.config.get<string>("FIREBASE_PROJECT_ID");
    const clientEmail = this.config.get<string>("FIREBASE_CLIENT_EMAIL");
    const privateKey = this.config.get<string>("FIREBASE_PRIVATE_KEY");
    if (!projectId || !clientEmail || !privateKey) throw new ServiceUnavailableException("Connexion indisponible : FIREBASE_* non configuré");
    if (!this.auth) {
      const { cert, initializeApp } = await import("firebase-admin/app");
      const { getAuth } = await import("firebase-admin/auth");
      // La clé privée du `.env` porte des « \n » littéraux à convertir en vrais retours à la ligne.
      this.auth = getAuth(initializeApp({ credential: cert({ projectId, clientEmail, privateKey: privateKey.replace(/\\n/g, "\n") }) }));
    }
    return this.auth;
  }

  async verifyIdToken(idToken: string): Promise<FirebaseIdentity> {
    try {
      const decoded = await (await this.getAuth()).verifyIdToken(idToken);
      return { uid: decoded.uid, emailVerified: decoded.email_verified === true };
    } catch (err) {
      if (err instanceof ServiceUnavailableException) throw err;
      throw new UnauthorizedException("Jeton Firebase invalide");
    }
  }

  async deleteUser(uid: string): Promise<void> {
    try {
      await (await this.getAuth()).deleteUser(uid);
    } catch (err) {
      // Déjà supprimé côté Firebase : rien à faire, la suppression locale continue.
      if ((err as { code?: string }).code !== "auth/user-not-found") throw err;
    }
  }
}
