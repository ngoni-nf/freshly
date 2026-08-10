import { Global, Module } from '@nestjs/common';
import { CommsService } from './comms.service';

@Global()
@Module({ providers: [CommsService], exports: [CommsService] })
export class CommsModule {}
