import { Controller, Get, Param, ParseUUIDPipe, Res } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import type { Response } from 'express';
import { AuthenticatedUser, CurrentUser } from '../../common/decorators';
import { InvoicesService } from './invoices.service';

@ApiTags('invoices')
@Controller('invoices')
export class InvoicesController {
  constructor(private readonly invoices: InvoicesService) {}

  /**
   * The listing lives on the booking (`GET /bookings/:id/invoices`); this is
   * the document itself, so the app can hand the bytes to the share sheet.
   */
  @Get(':id.pdf')
  @ApiOperation({ summary: 'One invoice as a PDF; the same visibility rules as the listing' })
  async pdf(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Res() res: Response,
  ) {
    const { number, pdf } = await this.invoices.pdf(user, id);
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `inline; filename="${number}.pdf"`);
    res.setHeader('Content-Length', String(pdf.length));
    res.end(pdf);
  }
}
