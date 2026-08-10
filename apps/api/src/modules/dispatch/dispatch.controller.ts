import { Body, Controller, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsBoolean, IsOptional, IsString, Length } from 'class-validator';
import { CurrentUser, Roles } from '../../common/decorators';
import { DispatchService } from './dispatch.service';

class RespondOfferDto {
  @IsBoolean() accept!: boolean;
  @IsOptional() @IsString() @Length(0, 200) reason?: string;
}

@ApiTags('dispatch')
@Controller('dispatch')
export class DispatchController {
  constructor(private readonly dispatch: DispatchService) {}

  @Roles('provider')
  @Post('offers/:id/respond')
  @ApiOperation({ summary: 'Accept or decline a dispatch offer' })
  respond(
    @CurrentUser('providerId') providerId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: RespondOfferDto,
  ) {
    return this.dispatch.respond(providerId, id, dto.accept, dto.reason);
  }
}
