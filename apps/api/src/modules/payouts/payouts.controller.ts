import {
  Body, Controller, Get, Headers, HttpCode, Param, Post, Query, Req,
} from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsBoolean, IsIn, IsInt, IsOptional, IsString, Length, Matches, Max, Min,
} from 'class-validator';
import type { Request } from 'express';
import { CurrentUser, Idempotent, Public, Roles } from '../../common/decorators';
import { PayoutsService } from './payouts.service';

class RequestPayoutDto {
  @Type(() => Number) @IsInt() @Min(1) @Max(100_000_000) amountMinor!: number;
  /** Defaults to the free daily batch — a fee is never applied by omission. */
  @IsOptional() @IsBoolean() instant?: boolean;
}

class AddAccountDto {
  @IsIn(['bank_transfer', 'ecocash', 'onemoney', 'innbucks']) method!: string;
  @Matches(/^[0-9\s]{6,24}$/, { message: 'Enter the account or phone number using digits only' })
  accountNumber!: string;
  @IsString() @Length(2, 120) accountName!: string;
  @IsOptional() @IsString() @Length(1, 20) institutionCode?: string;
  @IsOptional() @IsString() @Length(1, 80) institutionName?: string;
}

@ApiTags('payouts')
@Controller('payouts')
export class PayoutsController {
  constructor(private readonly payouts: PayoutsService) {}

  @Roles('provider')
  @Get('wallet')
  @ApiOperation({ summary: 'Balance, escrow still pending, and whether cash-out is possible' })
  wallet(@CurrentUser('providerId') providerId: string) {
    return this.payouts.wallet(providerId);
  }

  @Roles('provider')
  @Get('accounts')
  accounts(@CurrentUser('providerId') providerId: string) {
    return this.payouts.listAccounts(providerId);
  }

  @Roles('provider')
  @Post('accounts')
  @ApiOperation({ summary: 'Add a bank or mobile money destination' })
  addAccount(@CurrentUser('providerId') providerId: string, @Body() dto: AddAccountDto) {
    return this.payouts.addAccount(providerId, dto);
  }

  @Roles('provider')
  @Get()
  history(
    @CurrentUser('providerId') providerId: string,
    @Query('limit') limit?: string,
  ) {
    return this.payouts.history(providerId, Math.min(Number(limit) || 30, 100));
  }

  @Roles('provider')
  @Idempotent()
  @Post()
  @ApiOperation({ summary: 'Cash out' })
  request(
    @CurrentUser('providerId') providerId: string,
    @Body() dto: RequestPayoutDto,
    @Headers('idempotency-key') idempotencyKey: string,
  ) {
    return this.payouts.request(providerId, dto.amountMinor, dto.instant ?? false, idempotencyKey);
  }

  /**
   * Settlement callbacks. Public because the bank has no bearer token, and
   * authenticated instead by the signature over the raw body — which is why
   * this reads `req.rawBody` rather than the parsed DTO. Re-serialising JSON
   * changes the bytes and every signature check then fails.
   */
  @Public()
  @HttpCode(200)
  @Post('webhooks/:provider')
  webhook(
    @Param('provider') provider: string,
    @Headers('x-signature') signature: string,
    @Req() request: Request & { rawBody?: Buffer },
  ) {
    const raw = request.rawBody?.toString('utf8') ?? JSON.stringify(request.body ?? {});
    return this.payouts.handleWebhook(provider, signature, raw);
  }
}
