import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsBoolean, IsNumber, IsOptional, IsString, Length, Max, Min } from 'class-validator';
import { CurrentUser } from '../../common/decorators';
import { AddressesService } from './addresses.service';

class SaveAddressDto {
  @IsString() @Length(1, 40) label!: string;
  @IsString() @Length(4, 500) formatted!: string;
  @Type(() => Number) @IsNumber() @Min(-90) @Max(90) lat!: number;
  @Type(() => Number) @IsNumber() @Min(-180) @Max(180) lng!: number;

  /// "Flat 3B". Kept separate from the formatted address because geocoders
  /// drop it and a provider standing in a lobby needs it.
  @IsOptional() @IsString() @Length(0, 200) unitNotes?: string;

  /// "Buzzer 4B, dog in the yard." Handed over only once a job is accepted.
  @IsOptional() @IsString() @Length(0, 500) accessNotes?: string;

  @IsOptional() @IsBoolean() isDefault?: boolean;
}

class UpdateAddressDto {
  @IsOptional() @IsString() @Length(1, 40) label?: string;
  @IsOptional() @IsString() @Length(4, 500) formatted?: string;
  @IsOptional() @Type(() => Number) @IsNumber() @Min(-90) @Max(90) lat?: number;
  @IsOptional() @Type(() => Number) @IsNumber() @Min(-180) @Max(180) lng?: number;
  @IsOptional() @IsString() @Length(0, 200) unitNotes?: string;
  @IsOptional() @IsString() @Length(0, 500) accessNotes?: string;
  @IsOptional() @IsBoolean() isDefault?: boolean;
}

@ApiTags('addresses')
@Controller('addresses')
export class AddressesController {
  constructor(private readonly addresses: AddressesService) {}

  @Get()
  @ApiOperation({ summary: 'Your saved addresses, default first' })
  list(@CurrentUser('userId') userId: string) {
    return this.addresses.list(userId);
  }

  @Post()
  @ApiOperation({ summary: 'Save a place you book to' })
  create(@CurrentUser('userId') userId: string, @Body() dto: SaveAddressDto) {
    return this.addresses.create(userId, dto);
  }

  @Patch(':id')
  @ApiOperation({ summary: 'Rename, move, or make default' })
  update(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateAddressDto,
  ) {
    return this.addresses.update(userId, id, dto);
  }

  @Delete(':id')
  @ApiOperation({ summary: 'Forget an address' })
  remove(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.addresses.remove(userId, id);
  }
}
