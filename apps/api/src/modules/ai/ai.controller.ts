import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsString, Length } from 'class-validator';
import { AiService } from './ai.service';

class ParseIntentDto {
  @IsString() @Length(2, 300) text!: string;
}

@ApiTags('ai')
@Controller('ai')
export class AiController {
  constructor(private readonly ai: AiService) {}

  @Post('parse-intent')
  @HttpCode(200)
  @ApiOperation({ summary: 'Turn free text into a structured booking intent' })
  parse(@Body() dto: ParseIntentDto) {
    return this.ai.parseBookingIntent(dto.text);
  }
}
