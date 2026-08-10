import { Controller, Get, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsIn } from 'class-validator';
import { Public } from '../../common/decorators';
import { GridService } from './grid.service';

class GridQuery {
  @IsIn(['ZA', 'ZW'])
  countryCode!: 'ZA' | 'ZW';
}

@ApiTags('grid')
@Controller('grid')
export class GridController {
  constructor(private readonly grid: GridService) {}

  @Public()
  @Get('status')
  @ApiOperation({ summary: 'Current load-shedding stage and the next outage window' })
  status(@Query() query: GridQuery) {
    return this.grid.current(query.countryCode);
  }
}
