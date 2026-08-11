import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DatabaseService } from '../../common/database/database.service';

export interface PushMessage {
  title: string;
  body: string;
  /** Everything here reaches the app as strings; FCM does not carry types. */
  data?: Record<string, string>;
  /**
   * Seconds. A dispatch offer is worth nothing once its window has closed, so
   * an undelivered one should die in Google's queue rather than wake a provider
   * ten minutes later for a job somebody else already took.
   */
  ttlSeconds?: number;
  /** Wakes a dozing handset. Reserve it for things with a deadline. */
  urgent?: boolean;
  /**
   * Must match a channel the receiving app actually declares — the partner app
   * registers `freshly_dispatch`, the client app `freshly_bookings`. Android
   * silently drops an unknown channel back to default importance, which costs
   * exactly the heads-up alert this exists to produce.
   */
  channelId?: string;
}

/**
 * Push, as a fallback for the websocket rather than a duplicate of it.
 *
 * Dispatch offers arrive over socket.io, which only exists while the app is in
 * the foreground. Android freezes the socket within seconds of backgrounding,
 * so a provider whose phone is in their pocket — which is every provider not
 * currently staring at the app — silently misses the offer window and the job
 * goes to someone else. Push is the only channel that survives that.
 *
 * Nothing here throws. A booking must not fail because Google was slow, and a
 * dispatch wave must not abort halfway through its candidates because one
 * provider's token was stale.
 */
@Injectable()
export class PushService {
  private readonly logger = new Logger(PushService.name);
  private messaging: unknown | null = null;
  readonly enabled: boolean;

  constructor(
    private readonly config: ConfigService,
    private readonly db: DatabaseService,
  ) {
    this.enabled = Boolean(this.config.get<boolean>('PUSH_ENABLED'));
    if (!this.enabled) {
      this.logger.warn(
        'push disabled; offers reach providers only while the app is in the foreground',
      );
    }
  }

  /**
   * Lazy, non-literal import for the same reason as FirebaseAuthService: a
   * deployment that does not send push should not have to carry firebase-admin,
   * and TypeScript should not fail the build over a package it never calls.
   */
  private async client(): Promise<any> {
    if (this.messaging) return this.messaging;

    const appModule = 'firebase-admin/app';
    const messagingModule = 'firebase-admin/messaging';
    const firebase: any = await import(appModule);
    const { getMessaging }: any = await import(messagingModule);

    const raw = this.config.get<string>('FIREBASE_SERVICE_ACCOUNT_JSON');
    const existing = firebase.getApps();

    // Deliberately reuses the app FirebaseAuthService may already have created.
    // Two initialisations of the same project is a warning at best and a
    // credential mismatch at worst.
    const app = existing.length
      ? existing[0]
      : firebase.initializeApp({
          projectId: this.config.getOrThrow<string>('FIREBASE_PROJECT_ID'),
          credential: raw ? firebase.cert(JSON.parse(raw)) : firebase.applicationDefault(),
        });

    this.messaging = getMessaging(app);
    return this.messaging;
  }

  async sendToUser(userId: string, message: PushMessage): Promise<number> {
    const rows = await this.db.query<{ push_token: string }>(
      `SELECT push_token FROM devices
        WHERE user_id = $1 AND push_token IS NOT NULL`,
      [userId],
    );
    return this.dispatch(rows.map((r) => r.push_token), message);
  }

  async sendToProvider(providerId: string, message: PushMessage): Promise<number> {
    const rows = await this.db.query<{ push_token: string }>(
      `SELECT d.push_token
         FROM devices d
         JOIN providers p ON p.user_id = d.user_id
        WHERE p.id = $1 AND d.push_token IS NOT NULL`,
      [providerId],
    );
    return this.dispatch(rows.map((r) => r.push_token), message);
  }

  private async dispatch(tokens: string[], message: PushMessage): Promise<number> {
    if (!this.enabled || tokens.length === 0) return 0;

    try {
      const messaging = await this.client();
      const ttl = (message.ttlSeconds ?? 600) * 1_000;

      const response = await messaging.sendEachForMulticast({
        tokens,
        notification: { title: message.title, body: message.body },
        data: message.data ?? {},
        android: {
          priority: message.urgent ? 'high' : 'normal',
          ttl,
          notification: { channelId: message.channelId ?? 'freshly_bookings' },
        },
        apns: {
          headers: {
            'apns-priority': message.urgent ? '10' : '5',
            'apns-expiration': String(Math.floor((Date.now() + ttl) / 1000)),
          },
        },
      });

      await this.pruneDeadTokens(tokens, response.responses);
      return response.successCount;
    } catch (err) {
      this.logger.warn(`push send failed: ${(err as Error).message}`);
      return 0;
    }
  }

  /**
   * FCM tells us when a token belongs to an app that has been uninstalled or
   * had its data cleared. Left in place they accumulate forever, and every
   * later send wastes a slot in the multicast batch on a handset that will
   * never answer.
   */
  private async pruneDeadTokens(tokens: string[], responses: any[]): Promise<void> {
    const dead = tokens.filter((_, i) => {
      const code = responses[i]?.error?.code;
      return (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token'
      );
    });
    if (dead.length === 0) return;

    await this.db.query('DELETE FROM devices WHERE push_token = ANY($1::text[])', [dead]);
    this.logger.log(`pruned ${dead.length} unregistered push token(s)`);
  }
}
