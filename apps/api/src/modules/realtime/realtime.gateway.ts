import { Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import {
  ConnectedSocket, MessageBody, OnGatewayConnection, OnGatewayDisconnect,
  SubscribeMessage, WebSocketGateway, WebSocketServer,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { DatabaseService } from '../../common/database/database.service';
import { RedisService } from '../../common/redis/redis.service';
import { MarketsService } from '../markets/markets.service';

interface SocketUser {
  userId: string;
  providerId?: string;
  roles: string[];
}

/**
 * Realtime channel.
 *
 * Rooms, not broadcasts. A client joins only the bookings they own and a
 * provider only their own dispatch room, so a compromised or curious client
 * cannot subscribe to the city's live location feed by guessing an id.
 */
@WebSocketGateway({ cors: { origin: '*' }, transports: ['websocket'] })
export class RealtimeGateway implements OnGatewayConnection, OnGatewayDisconnect, OnModuleInit {
  private readonly logger = new Logger(RealtimeGateway.name);
  private readonly users = new Map<string, SocketUser>();

  @WebSocketServer() server!: Server;

  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly db: DatabaseService,
    private readonly redis: RedisService,
    private readonly markets: MarketsService,
  ) {}

  onModuleInit(): void {
    this.logger.log('realtime gateway ready');
  }

  async handleConnection(socket: Socket): Promise<void> {
    try {
      const token = (socket.handshake.auth?.token ?? socket.handshake.headers.authorization?.slice(7)) as string;
      const payload = await this.jwt.verifyAsync(token, {
        secret: this.config.getOrThrow<string>('JWT_SECRET'),
      });

      const user: SocketUser = {
        userId: payload.sub,
        providerId: payload.providerId,
        roles: payload.roles ?? ['client'],
      };
      this.users.set(socket.id, user);

      await socket.join(`user:${user.userId}`);
      if (user.providerId) await socket.join(`provider:${user.providerId}`);
    } catch {
      // An unauthenticated socket is disconnected rather than downgraded —
      // there is nothing on this channel a stranger should receive.
      socket.disconnect(true);
    }
  }

  handleDisconnect(socket: Socket): void {
    this.users.delete(socket.id);
  }

  @SubscribeMessage('booking.subscribe')
  async subscribeToBooking(
    @ConnectedSocket() socket: Socket,
    @MessageBody() body: { bookingId: string },
  ): Promise<{ ok: boolean }> {
    const user = this.users.get(socket.id);
    if (!user) return { ok: false };

    // Membership is checked against the database, not asserted by the client.
    const allowed = await this.db.queryOne<{ id: string }>(
      `SELECT b.id FROM bookings b
         LEFT JOIN providers p ON p.id = b.provider_id
        WHERE b.id = $1 AND (b.client_id = $2 OR p.user_id = $2)`,
      [body.bookingId, user.userId],
    );
    if (!allowed) return { ok: false };

    await socket.join(`booking:${body.bookingId}`);
    return { ok: true };
  }

  @SubscribeMessage('booking.unsubscribe')
  async unsubscribeFromBooking(
    @ConnectedSocket() socket: Socket,
    @MessageBody() body: { bookingId: string },
  ): Promise<{ ok: boolean }> {
    await socket.leave(`booking:${body.bookingId}`);
    return { ok: true };
  }

  /**
   * Provider position while a job is live.
   *
   * Breadcrumbs land in Redis under a TTL and are never written to Postgres.
   * Once the trip ends there is no lawful purpose for keeping them, so the
   * simplest compliant design is one where they expire on their own rather
   * than one where deletion is a job somebody has to remember to run.
   */
  @SubscribeMessage('location.publish')
  async publishLocation(
    @ConnectedSocket() socket: Socket,
    @MessageBody() body: { lat: number; lng: number; heading?: number; speedKph?: number },
  ): Promise<{ ok: boolean }> {
    const user = this.users.get(socket.id);
    if (!user?.providerId) return { ok: false };

    const ttl = this.markets.setting<number>('tracking.retention_minutes', 60) * 60;
    await this.redis.recordLocation(user.providerId, body, ttl);

    const active = await this.db.query<{ id: string }>(
      `SELECT id FROM bookings
        WHERE provider_id = $1 AND status IN ('accepted','en_route','arrived','in_progress')`,
      [user.providerId],
    );

    for (const booking of active) {
      this.server.to(`booking:${booking.id}`).emit('location.ping', {
        bookingId: booking.id,
        status: 'en_route',
        providerLocation: { lat: body.lat, lng: body.lng },
        headingDegrees: body.heading ?? null,
        etaMinutes: null,
        distanceRemainingKm: null,
        updatedAt: new Date().toISOString(),
      });
    }

    return { ok: true };
  }

  // ─── Server-side emitters ────────────────────────────────────────────────

  emitToBooking(bookingId: string, event: string, payload: unknown): void {
    this.server?.to(`booking:${bookingId}`).emit(event, payload);
  }

  emitToProvider(providerId: string, event: string, payload: unknown): void {
    this.server?.to(`provider:${providerId}`).emit(event, payload);
  }

  emitToUser(userId: string, event: string, payload: unknown): void {
    this.server?.to(`user:${userId}`).emit(event, payload);
  }
}
