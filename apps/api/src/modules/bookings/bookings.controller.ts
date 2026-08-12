import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser, Idempotent, Roles } from '../../common/decorators';
import { BookingsService } from './bookings.service';
import {
  AddonResponseDto, AdvanceStatusDto, CancelBookingDto, ChangeDestinationDto, ChatMessageDto, CheckoutDto,
  CreateBookingDto, QuoteBookingDto, ReviewDto, VerifyPinDto,
} from './dto/bookings.dto';

@ApiTags('bookings')
@Controller('bookings')
export class BookingsController {
  constructor(private readonly bookings: BookingsService) {}

  @Post('quote')
  @ApiOperation({ summary: 'Price a basket without creating anything' })
  quote(@Body() dto: QuoteBookingDto) {
    return this.bookings.quote(dto);
  }

  @Post()
  @Idempotent()
  @ApiOperation({ summary: 'Create a booking in pending_auth' })
  create(@CurrentUser('userId') userId: string, @Body() dto: CreateBookingDto) {
    return this.bookings.create(userId, dto);
  }

  @Post(':id/checkout')
  @Idempotent()
  @ApiOperation({ summary: 'Authorise payment and start dispatch' })
  checkout(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CheckoutDto,
  ) {
    return this.bookings.checkout(userId, id, dto.method, `checkout-${id}`);
  }

  @Get()
  list(@CurrentUser('userId') userId: string, @Query('status') status?: string) {
    return this.bookings.listMine(userId, status);
  }

  @Get(':id')
  findOne(@CurrentUser('userId') userId: string, @Param('id', ParseUUIDPipe) id: string) {
    return this.bookings.findOne(userId, id);
  }

  @Get(':id/pin')
  @ApiOperation({ summary: "The client's own completion code" })
  pin(@CurrentUser('userId') userId: string, @Param('id', ParseUUIDPipe) id: string) {
    return this.bookings.completionPin(userId, id);
  }

  @Post(':id/destination')
  @Idempotent()
  @ApiOperation({ summary: 'Correct the address, re-pricing the travel' })
  changeDestination(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ChangeDestinationDto,
  ) {
    return this.bookings.changeDestination(userId, id, {
      lat: dto.destination.lat,
      lng: dto.destination.lng,
      address: dto.destinationAddress,
      notes: dto.destinationNotes,
    });
  }

  @Post(':id/cancel')
  cancel(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CancelBookingDto,
  ) {
    return this.bookings.cancel(userId, id, dto.reason);
  }

  @Post(':id/review')
  review(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ReviewDto,
  ) {
    return this.bookings.review(userId, id, dto.rating, dto.tags ?? [], dto.comment);
  }

  // ─── Provider-side ───────────────────────────────────────────────────────

  @Roles('provider')
  @Post(':id/status')
  @ApiOperation({ summary: 'Move a job to en_route or arrived' })
  advance(
    @CurrentUser('providerId') providerId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AdvanceStatusDto,
  ) {
    return this.bookings.advanceStatus(providerId, id, dto.status);
  }

  @Roles('provider')
  /**
   * Tighter than the global 120 a minute, which is far too generous for a
   * four-digit code. The per-booking counter in the service is the real
   * control; this stops a caller hammering many bookings at once.
   */
  @Throttle({ short: { ttl: 60_000, limit: 10 } })
  @Post(':id/verify-pin')
  @ApiOperation({ summary: "Verify the client's code and start the service" })
  verifyPin(
    @CurrentUser('providerId') providerId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: VerifyPinDto,
  ) {
    return this.bookings.verifyPin(providerId, id, dto.pin);
  }

  @Roles('provider')
  @Post(':id/complete')
  @Idempotent()
  @ApiOperation({ summary: 'Finish the job and release escrow' })
  complete(
    @CurrentUser('providerId') providerId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.bookings.complete(providerId, id);
  }

  // ─── Chat ────────────────────────────────────────────────────────────────

  @Get(':id/chat')
  @ApiOperation({ summary: 'Chat history for a booking' })
  getChat(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.bookings.getChatHistory(userId, id);
  }

  @Post(':id/chat')
  @ApiOperation({ summary: 'Send a chat message' })
  sendChat(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ChatMessageDto,
  ) {
    return this.bookings.sendChatMessage(userId, id, dto.body);
  }

  @Post(':id/addons/:itemId/respond')
  @Idempotent()
  @ApiOperation({ summary: 'Approve or decline an add-on suggested mid-service' })
  respondToAddon(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('itemId', ParseUUIDPipe) itemId: string,
    @Body() dto: AddonResponseDto,
  ) {
    return this.bookings.respondToAddon(userId, id, itemId, dto.approve);
  }

  @Post(':id/chat/read')
  @ApiOperation({ summary: 'Mark all messages as read' })
  readChat(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.bookings.markChatAsRead(userId, id);
  }
}
