import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { TransactionContext } from '../../common/database/database.service';

export type LedgerAccount =
  | 'client_source'
  | 'escrow'
  | 'provider_payable'
  | 'platform_commission'
  | 'platform_service_fee'
  | 'payment_processing'
  | 'tax_payable'
  | 'promotions'
  | 'bank_settlement';

export interface LedgerEntryInput {
  account: LedgerAccount;
  direction: 'debit' | 'credit';
  amountMinor: number;
  description: string;
  providerId?: string | null;
  userId?: string | null;
}

export interface LedgerWrite {
  currency: string;
  bookingId?: string | null;
  payoutId?: string | null;
  entries: LedgerEntryInput[];
  /** Supply one to write several balanced sets under a shared key. */
  groupKey?: string;
}

/**
 * The single door every movement of money goes through.
 *
 * Escrow and payouts are different domains but they write to the same ledger,
 * and the property that makes the ledger worth having — every group nets to
 * zero — only holds if there is exactly one writer enforcing it. A second
 * hand-rolled INSERT somewhere else is how a ledger stops reconciling, so
 * this is deliberately the only place that inserts ledger_entries.
 *
 * The balance assertion runs in the database, inside the caller's transaction.
 * If it fires, the change that provoked it is wrong — not the assertion.
 */
@Injectable()
export class LedgerService {
  async write(tx: TransactionContext, write: LedgerWrite): Promise<string> {
    const groupKey = write.groupKey ?? randomUUID();

    for (const entry of write.entries) {
      // A zero part is normal — no VAT in a zero-rated market, no fee on a
      // batch payout — and skipping it keeps the CHECK (amount_minor > 0)
      // constraint meaningful for the amounts that are real.
      if (entry.amountMinor === 0) continue;
      if (entry.amountMinor < 0) {
        throw new Error(
          `ledger entries are unsigned; express direction with debit/credit, not ${entry.amountMinor}`,
        );
      }

      await tx.query(
        `INSERT INTO ledger_entries
           (booking_id, payout_id, account, direction, amount_minor, currency,
            description, group_key, counterparty_provider_id, counterparty_user_id)
         VALUES ($1, $2, $3::ledger_account_enum, $4::ledger_direction_enum, $5,
                 $6::currency_code_enum, $7, $8, $9, $10)`,
        [
          write.bookingId ?? null,
          write.payoutId ?? null,
          entry.account,
          entry.direction,
          entry.amountMinor,
          write.currency,
          entry.description,
          groupKey,
          entry.providerId ?? null,
          entry.userId ?? null,
        ],
      );
    }

    await tx.query('SELECT fn_assert_ledger_balanced($1)', [groupKey]);
    return groupKey;
  }
}
