import { Inject, Injectable, OnModuleDestroy, OnModuleInit } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { PrismaClient } from "@news/db";
import { createLogger, StreamDTO } from "@news/domain";
import { PRISMA } from "../db/db.module";

const logger = createLogger("worker:twitch");

const INTERVAL_MS = 60_000;
// Les matchs qui comptent : en cours, ou qui commencent dans les deux heures (le temps de voir la chaîne passer « en direct »).
const WINDOW_MS = 2 * 60 * 60 * 1000;
const PROFILE_MAX_AGE_MS = 24 * 60 * 60 * 1000;
// Twitch accepte 100 chaînes par requête.
const BATCH = 100;

interface HelixUser {
  login: string;
  display_name: string;
  profile_image_url: string;
}

type Credentials = { id: string; secret: string };

// Logo, nom affiché et « en direct » des chaînes de diffusion (J21). L'API Twitch (Helix, officielle,
// clé d'application) n'est interrogée que depuis le worker (règle 1), pour les chaînes des matchs
// proches. Sans `TWITCH_CLIENT_ID`/`TWITCH_CLIENT_SECRET`, rien ne tourne : l'appli affiche des
// initiales, sans « en direct ».
@Injectable()
export class TwitchService implements OnModuleInit, OnModuleDestroy {
  private timer: NodeJS.Timeout | null = null;
  private running = false;
  private token: { value: string; expiresAt: number } | null = null;
  // Remplaçable dans les tests.
  fetchFn: typeof fetch = (...args) => fetch(...args);

  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly config: ConfigService,
  ) {}

  private get credentials(): Credentials | null {
    const id = this.config.get<string>("TWITCH_CLIENT_ID");
    const secret = this.config.get<string>("TWITCH_CLIENT_SECRET");
    return id && secret ? { id, secret } : null;
  }

  onModuleInit(): void {
    if (!this.credentials) {
      logger.warn("TWITCH_CLIENT_ID/TWITCH_CLIENT_SECRET absents : pas de logos ni de « en direct » pour les streams");
      return;
    }
    this.timer = setInterval(() => void this.run().catch((err) => logger.error(err, "échec du rafraîchissement Twitch")), INTERVAL_MS);
    this.timer.unref();
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }

  async run(now = new Date()): Promise<void> {
    const creds = this.credentials;
    if (!creds || this.running) return;
    this.running = true;
    try {
      const logins = await this.loginsToWatch(now);
      if (logins.length === 0) return;
      await this.refreshProfiles(logins, now, creds);
      await this.refreshLive(logins, now, creds);
    } finally {
      this.running = false;
    }
  }

  private async loginsToWatch(now: Date): Promise<string[]> {
    const events = await this.prisma.event.findMany({
      where: { OR: [{ status: "live" }, { status: "scheduled", startsAt: { gte: now, lt: new Date(now.getTime() + WINDOW_MS) } }] },
      select: { streams: true },
    });
    const logins = new Set<string>();
    for (const e of events) for (const s of (e.streams as unknown as StreamDTO[] | null) ?? []) if (s.channel) logins.add(s.channel);
    return [...logins];
  }

  private async refreshProfiles(logins: string[], now: Date, creds: Credentials): Promise<void> {
    const known = await this.prisma.streamChannel.findMany({ where: { login: { in: logins } } });
    const fresh = new Set(known.filter((c) => c.profileCheckedAt && now.getTime() - c.profileCheckedAt.getTime() < PROFILE_MAX_AGE_MS).map((c) => c.login));
    const stale = logins.filter((l) => !fresh.has(l));
    for (let i = 0; i < stale.length; i += BATCH) {
      const batch = stale.slice(i, i + BATCH);
      const users = await this.helix<HelixUser>("users", batch.map((l) => ["login", l]), creds);
      const byLogin = new Map(users.map((u) => [u.login.toLowerCase(), u]));
      for (const login of batch) {
        const u = byLogin.get(login);
        // Une chaîne que Twitch ne connaît pas garde une ligne vide : on ne la redemande pas avant 24 h.
        const data = { displayName: u?.display_name ?? null, imageUrl: u?.profile_image_url ?? null, profileCheckedAt: now };
        await this.prisma.streamChannel.upsert({ where: { login }, create: { login, ...data }, update: data });
      }
    }
  }

  private async refreshLive(logins: string[], now: Date, creds: Credentials): Promise<void> {
    for (let i = 0; i < logins.length; i += BATCH) {
      const batch = logins.slice(i, i + BATCH);
      const live = await this.helix<{ user_login: string }>("streams", batch.map((l) => ["user_login", l]), creds);
      const liveSet = new Set(live.map((s) => s.user_login.toLowerCase()));
      await this.prisma.streamChannel.updateMany({ where: { login: { in: batch.filter((l) => liveSet.has(l)) } }, data: { live: true, liveCheckedAt: now } });
      await this.prisma.streamChannel.updateMany({ where: { login: { in: batch.filter((l) => !liveSet.has(l)) } }, data: { live: false, liveCheckedAt: now } });
    }
  }

  private async helix<T>(path: string, params: [string, string][], creds: Credentials, retry = true): Promise<T[]> {
    const url = `https://api.twitch.tv/helix/${path}?${new URLSearchParams(params)}`;
    const res = await this.fetchFn(url, { headers: { "Client-Id": creds.id, Authorization: `Bearer ${await this.accessToken(creds)}` } });
    if (res.status === 401 && retry) {
      this.token = null; // jeton révoqué ou expiré : on en redemande un
      return this.helix(path, params, creds, false);
    }
    if (!res.ok) throw new Error(`Twitch ${path} : HTTP ${res.status}`);
    return ((await res.json()) as { data: T[] }).data;
  }

  private async accessToken(creds: Credentials): Promise<string> {
    if (this.token && this.token.expiresAt > Date.now()) return this.token.value;
    const res = await this.fetchFn("https://id.twitch.tv/oauth2/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ client_id: creds.id, client_secret: creds.secret, grant_type: "client_credentials" }),
    });
    if (!res.ok) throw new Error(`Twitch OAuth : HTTP ${res.status}`);
    const body = (await res.json()) as { access_token: string; expires_in: number };
    this.token = { value: body.access_token, expiresAt: Date.now() + (body.expires_in - 60) * 1000 };
    return body.access_token;
  }
}
