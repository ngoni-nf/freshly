import { ForbiddenException, Injectable, Logger } from '@nestjs/common';
import PDFDocument from 'pdfkit';
import { DatabaseService, TransactionContext } from '../../common/database/database.service';
import { AuthenticatedUser } from '../../common/decorators';
import { NotFoundError } from '../../common/errors/domain.errors';
import { formatMoney } from '../../common/money/money';
import { MarketsService } from '../markets/markets.service';
import {
  draftInvoices, formatBps, InvoiceDraft, InvoiceKind, invoiceNumber,
} from './invoice-lines';

interface InvoiceRow {
  id: string;
  booking_id: string;
  kind: InvoiceKind;
  number: string;
  issued_at: Date;
  currency: string;
  lines: Array<{ label: string; amountMinor: number }>;
  subtotal_minor: string;
  vat_minor: string;
  total_minor: string;
  issuer_name: string;
  issuer_detail: string | null;
  recipient_name: string;
  recipient_detail: string | null;
  country_code: 'ZA' | 'ZW';
  reference: string;
}

interface BookingParties {
  client_id: string;
  provider_user_id: string | null;
  staff_user_id: string | null;
}

/**
 * SARS and ZIMRA split invoicing.
 *
 * Two documents per completed job, written in the completion transaction so
 * they exist if and only if the completion did. The figures come from the
 * booking row, which was frozen at checkout and grown only by approved
 * add-ons, so an invoice cannot disagree with what was captured.
 */
@Injectable()
export class InvoicesService {
  private readonly logger = new Logger(InvoicesService.name);

  constructor(
    private readonly db: DatabaseService,
    private readonly markets: MarketsService,
  ) {}

  /**
   * Draft and store both invoices for a booking that is completing.
   *
   * Called from inside BookingsService.complete's transaction. Taking the
   * next number is an upsert on the (country, year) counter row: two
   * completions in the same market serialise on that row's lock, so each
   * gets its own number and neither sees a gap.
   */
  async issueForBooking(tx: TransactionContext, bookingId: string): Promise<void> {
    const already = await tx.queryOne<{ id: string }>(
      'SELECT id FROM invoices WHERE booking_id = $1 LIMIT 1',
      [bookingId],
    );
    if (already) return;

    const b = await tx.queryOne<Record<string, any>>(
      `SELECT b.id, b.reference, b.country_code, b.currency,
              b.subtotal_minor, b.addons_minor, b.travel_fee_minor, b.service_fee_minor,
              b.discount_minor, b.total_minor, b.commission_bps, b.commission_minor,
              b.vat_on_fees_minor, b.travel_distance_km,
              p.display_name AS provider_name,
              pu.phone_e164  AS provider_phone,
              pa.name        AS provider_area,
              cu.full_name   AS client_name,
              cu.phone_e164  AS client_phone,
              ba.name        AS booking_area
         FROM bookings b
         LEFT JOIN providers p ON p.id = b.provider_id
         LEFT JOIN users pu ON pu.id = p.user_id
         LEFT JOIN service_areas pa ON pa.id = p.service_area_id
         JOIN users cu ON cu.id = b.client_id
         LEFT JOIN service_areas ba ON ba.id = b.service_area_id
        WHERE b.id = $1`,
      [bookingId],
    );
    if (!b) throw new NotFoundError('Booking', bookingId);

    const items = await tx.query<{ name_snapshot: string; price_minor: string; quantity: number; is_addon: boolean }>(
      `SELECT name_snapshot, price_minor, quantity, is_addon
         FROM booking_items
        WHERE booking_id = $1 AND (NOT is_addon OR client_approved_at IS NOT NULL)
        ORDER BY is_addon, name_snapshot`,
      [bookingId],
    );

    const market = this.markets.get(b.country_code);
    const drafts = draftInvoices({
      subtotalMinor: Number(b.subtotal_minor),
      addonsMinor: Number(b.addons_minor),
      travelFeeMinor: Number(b.travel_fee_minor),
      serviceFeeMinor: Number(b.service_fee_minor),
      discountMinor: Number(b.discount_minor),
      totalMinor: Number(b.total_minor),
      commissionBps: b.commission_bps,
      commissionMinor: Number(b.commission_minor),
      vatOnFeesMinor: Number(b.vat_on_fees_minor),
      travelDistanceKm: Number(b.travel_distance_km),
      items: items.map((i) => ({
        label: i.name_snapshot,
        amountMinor: Number(i.price_minor) * i.quantity,
        isAddon: i.is_addon,
      })),
      vatLabel: market.vatLabel,
      vatBps: market.vatBps,
    });

    // The year the tax authority will file it under: the market's own, not
    // the server's. A job finished at 23:30 in Harare on New Year's Eve is a
    // 2026 invoice whatever UTC says.
    const yearRow = await tx.queryOne<{ year: number }>(
      `SELECT EXTRACT(YEAR FROM (now() AT TIME ZONE $1))::int AS year`,
      [market.timezone],
    );
    const year = yearRow!.year;

    const providerName = b.provider_name ?? 'Freshly professional';
    const providerDetail = partyDetail(b.provider_area ?? b.booking_area, b.provider_phone);
    const clientDetail = partyDetail(b.booking_area, b.client_phone);

    await this.insert(tx, b, year, drafts.providerToClient, {
      issuerName: providerName,
      issuerDetail: providerDetail,
      recipientName: b.client_name ?? 'Freshly client',
      recipientDetail: clientDetail,
    });
    await this.insert(tx, b, year, drafts.platformToProvider, {
      issuerName: 'Freshly',
      issuerDetail: `Marketplace operator, ${market.name}`,
      recipientName: providerName,
      recipientDetail: providerDetail,
    });
  }

  private async insert(
    tx: TransactionContext,
    b: Record<string, any>,
    year: number,
    draft: InvoiceDraft,
    parties: { issuerName: string; issuerDetail: string | null; recipientName: string; recipientDetail: string | null },
  ): Promise<void> {
    const seq = await tx.queryOne<{ last: number }>(
      `INSERT INTO invoice_sequences (country_code, year, last)
       VALUES ($1::country_code_enum, $2, 1)
       ON CONFLICT (country_code, year) DO UPDATE SET last = invoice_sequences.last + 1
       RETURNING last`,
      [b.country_code, year],
    );
    await tx.query(
      `INSERT INTO invoices (
         booking_id, kind, number, currency, lines, subtotal_minor, vat_minor, total_minor,
         issuer_name, issuer_detail, recipient_name, recipient_detail
       ) VALUES ($1, $2::invoice_kind_enum, $3, $4::currency_code_enum, $5::jsonb, $6, $7, $8, $9, $10, $11, $12)`,
      [
        b.id, draft.kind, invoiceNumber(b.country_code, year, seq!.last), b.currency,
        JSON.stringify(draft.lines), draft.subtotalMinor, draft.vatMinor, draft.totalMinor,
        parties.issuerName, parties.issuerDetail, parties.recipientName, parties.recipientDetail,
      ],
    );
  }

  // ─── Reads ─────────────────────────────────────────────────────────────────

  async listForBooking(user: AuthenticatedUser, bookingId: string) {
    const parties = await this.db.queryOne<BookingParties>(
      `SELECT b.client_id, p.user_id AS provider_user_id, s.user_id AS staff_user_id
         FROM bookings b
         LEFT JOIN providers p ON p.id = b.provider_id
         LEFT JOIN providers s ON s.id = b.assigned_staff_id
        WHERE b.id = $1`,
      [bookingId],
    );
    if (!parties) throw new NotFoundError('Booking', bookingId);
    const kinds = visibleKinds(user, parties);

    const rows = await this.db.query<InvoiceRow>(
      `SELECT id, kind, number, issued_at, currency, total_minor
         FROM invoices
        WHERE booking_id = $1 AND kind = ANY($2::invoice_kind_enum[])
        ORDER BY kind`,
      [bookingId, kinds],
    );
    return rows.map((r) => ({
      id: r.id,
      kind: r.kind,
      number: r.number,
      issuedAt: r.issued_at.toISOString(),
      currency: r.currency,
      totalMinor: Number(r.total_minor),
    }));
  }

  async pdf(user: AuthenticatedUser, invoiceId: string): Promise<{ number: string; pdf: Buffer }> {
    const row = await this.db.queryOne<InvoiceRow & BookingParties>(
      `SELECT i.*, b.reference, b.country_code,
              b.client_id, p.user_id AS provider_user_id, s.user_id AS staff_user_id
         FROM invoices i
         JOIN bookings b ON b.id = i.booking_id
         LEFT JOIN providers p ON p.id = b.provider_id
         LEFT JOIN providers s ON s.id = b.assigned_staff_id
        WHERE i.id = $1`,
      [invoiceId],
    );
    if (!row) throw new NotFoundError('Invoice', invoiceId);
    if (!visibleKinds(user, row).includes(row.kind)) {
      throw new ForbiddenException({ code: 'not_your_booking', message: 'Not permitted' });
    }

    const market = this.markets.get(row.country_code);
    const pdf = await renderInvoicePdf(row, { vatLabel: market.vatLabel, vatBps: market.vatBps, timezone: market.timezone });
    return { number: row.number, pdf };
  }
}

/**
 * Who may see which document. The client gets the invoice addressed to them
 * and nothing about what we charged the provider; the salon or solo provider
 * gets both; a staff member who did the job sees the invoice for the work but
 * not the salon's fee bill; ops sees everything.
 */
function visibleKinds(user: AuthenticatedUser, parties: BookingParties): InvoiceKind[] {
  const both: InvoiceKind[] = ['provider_to_client', 'platform_to_provider'];
  if (user.roles.includes('admin') || user.roles.includes('support')) return both;
  if (parties.provider_user_id === user.userId) return both;
  if (parties.client_id === user.userId || parties.staff_user_id === user.userId) {
    return ['provider_to_client'];
  }
  throw new ForbiddenException({ code: 'not_your_booking', message: 'Not permitted' });
}

/** "Harare Metro, phone ending 0003". Never the whole number. */
function partyDetail(city: string | null, phone: string | null): string | null {
  const parts: string[] = [];
  if (city) parts.push(city);
  if (phone && phone.length >= 4) parts.push(`phone ending ${phone.slice(-4)}`);
  return parts.length ? parts.join(', ') : null;
}

/**
 * One plain A4 page. pdfkit needs neither a browser nor the network, which
 * is the whole reason it was chosen; the layout is deliberately unstyled so
 * it prints on anything and survives being forwarded as an attachment.
 */
function renderInvoicePdf(
  inv: InvoiceRow,
  market: { vatLabel: string; vatBps: number; timezone: string },
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A4', margin: 50, info: { Title: inv.number } });
    const chunks: Buffer[] = [];
    doc.on('data', (c: Buffer) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    const money = (minor: number) => formatMoney(minor, inv.currency);
    const left = 50;
    const right = 545;
    const title = inv.kind === 'provider_to_client' ? 'Invoice' : 'Platform fee invoice';

    doc.font('Helvetica-Bold').fontSize(20).text(title, left, 50);
    doc.font('Helvetica').fontSize(10).fillColor('#444');
    doc.text(`Invoice number: ${inv.number}`, left, 80);
    doc.text(`Date: ${formatDate(inv.issued_at, market.timezone)}`, left, 94);
    doc.text(`Booking reference: ${inv.reference}`, left, 108);
    doc.fillColor('#000');

    const blockTop = 140;
    doc.font('Helvetica-Bold').fontSize(10).text('From', left, blockTop);
    doc.font('Helvetica').text(inv.issuer_name, left, blockTop + 14, { width: 230 });
    if (inv.issuer_detail) doc.fillColor('#444').text(inv.issuer_detail, left, blockTop + 28, { width: 230 });
    doc.fillColor('#000');

    const midX = 310;
    doc.font('Helvetica-Bold').text('To', midX, blockTop);
    doc.font('Helvetica').text(inv.recipient_name, midX, blockTop + 14, { width: 235 });
    if (inv.recipient_detail) doc.fillColor('#444').text(inv.recipient_detail, midX, blockTop + 28, { width: 235 });
    doc.fillColor('#000');

    let y = 210;
    doc.moveTo(left, y).lineTo(right, y).strokeColor('#999').stroke();
    y += 8;
    doc.font('Helvetica-Bold').fontSize(10);
    doc.text('Description', left, y);
    doc.text('Amount', right - 100, y, { width: 100, align: 'right' });
    y += 16;
    doc.moveTo(left, y).lineTo(right, y).strokeColor('#999').stroke();
    y += 8;

    doc.font('Helvetica').fontSize(10);
    for (const line of inv.lines) {
      doc.text(line.label, left, y, { width: 360 });
      doc.text(money(line.amountMinor), right - 100, y, { width: 100, align: 'right' });
      y += 16;
    }

    y += 6;
    doc.moveTo(left, y).lineTo(right, y).strokeColor('#999').stroke();
    y += 10;

    const totalRow = (label: string, value: string, bold = false) => {
      doc.font(bold ? 'Helvetica-Bold' : 'Helvetica');
      doc.text(label, right - 260, y, { width: 150, align: 'right' });
      doc.text(value, right - 100, y, { width: 100, align: 'right' });
      y += 16;
    };
    totalRow('Subtotal', money(Number(inv.subtotal_minor)));
    const vat = Number(inv.vat_minor);
    if (vat > 0) {
      totalRow(`Includes ${market.vatLabel} (${formatBps(market.vatBps)})`, money(vat));
    }
    totalRow('Total', money(Number(inv.total_minor)), true);

    y += 10;
    doc.font('Helvetica').fontSize(9).fillColor('#444');
    if (inv.kind === 'provider_to_client') {
      doc.text(
        'Issued on behalf of the professional named above for services rendered through Freshly. '
        + 'The professional is responsible for their own tax position on this amount.',
        left, y, { width: right - left },
      );
    } else {
      doc.text(
        `Marketplace fees charged by Freshly to the professional named above, inclusive of ${market.vatLabel} where applicable. `
        + 'Settled by deduction from the booking payout.',
        left, y, { width: right - left },
      );
    }

    doc.fontSize(9).fillColor('#888').text('Generated by Freshly', left, 780, { width: right - left, align: 'center' });
    doc.end();
  });
}

function formatDate(date: Date, timezone: string): string {
  return new Intl.DateTimeFormat('en-GB', {
    day: '2-digit', month: 'long', year: 'numeric', timeZone: timezone,
  }).format(date);
}
