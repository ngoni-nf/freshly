import { Controller, Get, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsBoolean, IsIn, IsInt, IsNumber, IsOptional, Max, Min } from 'class-validator';
import { Public } from '../../common/decorators';
import { DiscoveryService } from './discovery.service';

export class SearchProvidersDto {
  @Type(() => Number) @IsNumber() @Min(-90) @Max(90)
  lat!: number;

  @Type(() => Number) @IsNumber() @Min(-180) @Max(180)
  lng!: number;

  @IsOptional() @Type(() => Number) @IsNumber() @Min(0.5) @Max(50)
  radiusKm?: number;

  @IsOptional()
  @IsIn(['barber', 'hair', 'nails', 'makeup', 'aesthetics', 'braiding', 'locs', 'massage', 'brows_lashes'])
  category?: string;

  @IsOptional() @IsIn(['mobile', 'in_shop', 'both'])
  venue?: string;

  @IsOptional() @Type(() => Number) @IsInt() @Min(0)
  maxPriceMinor?: number;

  @IsOptional() @Type(() => Number) @IsNumber() @Min(0) @Max(5)
  minRating?: number;

  @IsOptional() @Type(() => Boolean) @IsBoolean()
  requirePowerBackup?: boolean;

  @IsOptional() @Type(() => Boolean) @IsBoolean()
  instantOnly?: boolean;

  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(50)
  limit?: number;

  @IsOptional() @Type(() => Number) @IsInt() @Min(0)
  offset?: number;
}

@ApiTags('discovery')
@Controller('discovery')
export class DiscoveryController {
  constructor(private readonly discovery: DiscoveryService) {}

  @Public()
  @Get('providers')
  @ApiOperation({ summary: 'Find providers near a point, filtered and ranked' })
  search(@Query() query: SearchProvidersDto) {
    return this.discovery.searchProviders(query);
  }
}
