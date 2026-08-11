import { Body, Controller, Get, Post, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsUUID, Max, Min } from 'class-validator';
import { CurrentUser, Public, Roles } from '../../common/decorators';
import { SERVICE_CATEGORIES } from '../../common/catalog/service-categories';
import { CatalogService } from './catalog.service';

class AddToMenuDto {
  @IsUUID() templateId!: string;
  @Type(() => Number) @IsInt() @Min(100) @Max(100_000_000) priceMinor!: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(5) @Max(600) durationMinutes?: number;
  @IsOptional() @IsIn(['mobile', 'in_shop', 'both']) venueMode?: string;
}

@ApiTags('catalog')
@Controller('catalog')
export class CatalogController {
  constructor(private readonly catalog: CatalogService) {}

  /**
   * Public. Someone deciding whether to sign up is entitled to see what can be
   * booked before handing over a phone number.
   */
  @Public()
  @Get('categories')
  @ApiOperation({ summary: 'Specializations with something bookable in them' })
  categories() {
    return this.catalog.categories();
  }

  @Public()
  @Get('services')
  @ApiOperation({ summary: 'The canonical service menu, optionally by specialization' })
  services(@Query('category') category?: string) {
    const valid = category && (SERVICE_CATEGORIES as readonly string[]).includes(category);
    return this.catalog.services(valid ? category : undefined);
  }

  @Roles('provider')
  @Get('me/menu')
  menu(@CurrentUser('providerId') providerId: string) {
    return this.catalog.menu(providerId);
  }

  @Roles('provider')
  @Post('me/menu')
  @ApiOperation({ summary: 'Add a catalogue service to your menu at your own price' })
  addToMenu(@CurrentUser('providerId') providerId: string, @Body() dto: AddToMenuDto) {
    return this.catalog.addToMenu(providerId, dto);
  }
}
