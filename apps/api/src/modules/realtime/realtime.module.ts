import { Global, Module } from '@nestjs/common';
import { RealtimeGateway } from './realtime.gateway';
import { OutboxRelay } from './outbox.relay';

@Global()
@Module({ providers: [RealtimeGateway, OutboxRelay], exports: [RealtimeGateway] })
export class RealtimeModule {}
