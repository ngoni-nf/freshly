import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Roles } from '../../common/decorators';
import { AdminService } from './admin.service';

class ResolveDisputeDto {
  decision!: 'refund_client' | 'release_to_pro';
}

@ApiTags('admin')
@Controller('admin')
@Roles('admin', 'support')
export class AdminController {
  constructor(private readonly admin: AdminService) {}

  @Get('stats/pulse')
  @ApiOperation({ summary: 'Real-time marketplace health metrics' })
  pulse() {
    return this.admin.getPulse();
  }

  @Get('stats/badges')
  @ApiOperation({ summary: 'Count of pending items for navigation badges' })
  badges() {
    return this.admin.getBadges();
  }

  @Get('search')
  @ApiOperation({ summary: 'Global search across users, providers, and bookings' })
  search(@Query('q') q: string) {
    if (!q || q.length < 2) return [];
    return this.admin.globalSearch(q);
  }

  @Get('bookings/disputed')
  @ApiOperation({ summary: 'List bookings currently in dispute' })
  listDisputed() {
    return this.admin.listDisputed();
  }

  @Post('bookings/:id/resolve-dispute')
  @ApiOperation({ summary: 'Settle a dispute by refunding or releasing funds' })
  resolveDispute(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ResolveDisputeDto,
  ) {
    return this.admin.resolveDispute(id, dto.decision);
  }

  @Roles('admin')
  @Get('markets')
  @ApiOperation({ summary: 'List all market configurations (admin only)' })
  markets() {
    return this.admin.listMarkets();
  }

  @Roles('admin')
  @Post('markets/:code')
  @ApiOperation({ summary: 'Update market settings (VAT, commission, fees)' })
  updateMarket(
    @Param('code') code: string,
    @Body() updates: Record<string, any>,
  ) {
    return this.admin.updateMarket(code, updates);
  }
}
