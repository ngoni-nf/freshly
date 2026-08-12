import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsIn, IsOptional, IsString, IsUUID, Length } from 'class-validator';
import { CurrentUser, Roles } from '../../common/decorators';
import { SupportService } from './support.service';

class RaiseTicketDto {
  @IsString() @Length(3, 160) subject!: string;
  @IsString() @Length(10, 4000) body!: string;
  @IsOptional() @IsUUID() bookingId?: string;
  @IsOptional() @IsIn(['client', 'provider']) raisedBy?: 'client' | 'provider';
}

class MessageDto {
  @IsString() @Length(1, 4000) body!: string;
}

class CloseDto {
  /// Required: closing a complaint without telling the person why is how you
  /// get the same complaint again with less goodwill.
  @IsString() @Length(3, 2000) resolution!: string;
}

@ApiTags('support')
@Controller('support')
export class SupportController {
  constructor(private readonly support: SupportService) {}

  @Post('tickets')
  @ApiOperation({ summary: 'Raise a complaint or ask for help' })
  raise(@CurrentUser('userId') userId: string, @Body() dto: RaiseTicketDto) {
    return this.support.raise(userId, dto);
  }

  @Get('tickets')
  @ApiOperation({ summary: 'Your own tickets, with their replies' })
  mine(@CurrentUser('userId') userId: string) {
    return this.support.mine(userId);
  }

  @Post('tickets/:id/messages')
  @ApiOperation({ summary: 'Add to your own ticket' })
  addMessage(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: MessageDto,
  ) {
    return this.support.addMessage(id, userId, dto.body);
  }

  // ─── Operator ────────────────────────────────────────────────────────────

  @Roles('admin', 'support')
  @Get('queue/clients')
  @ApiOperation({ summary: 'Complaints raised by clients' })
  clientQueue(@Query('status') status?: 'open' | 'closed' | 'all') {
    return this.support.queue('client', status ?? 'open');
  }

  @Roles('admin', 'support')
  @Get('queue/providers')
  @ApiOperation({ summary: 'Complaints raised by providers' })
  providerQueue(@Query('status') status?: 'open' | 'closed' | 'all') {
    return this.support.queue('provider', status ?? 'open');
  }

  @Roles('admin', 'support')
  @Post('tickets/:id/reply')
  @ApiOperation({ summary: 'Answer a complaint; the reply is pushed to them' })
  reply(
    @CurrentUser('userId') staffUserId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: MessageDto,
  ) {
    return this.support.reply(id, staffUserId, dto.body);
  }

  @Roles('admin', 'support')
  @Post('tickets/:id/close')
  @ApiOperation({ summary: 'Close a complaint with a stated resolution' })
  close(
    @CurrentUser('userId') staffUserId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CloseDto,
  ) {
    return this.support.close(id, staffUserId, dto.resolution);
  }
}
