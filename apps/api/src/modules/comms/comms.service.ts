import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { formatMoney } from '../../common/money/money';
import { TwilioAdapter } from './adapters/twilio.adapter';

/**
 * Outbound messaging.
 *
 * OTP delivery goes over SMS rather than WhatsApp: WhatsApp template approval
 * takes days and a first-time user may not have it installed, whereas every
 * handset in both markets receives SMS. Transactional booking updates then
 * move to WhatsApp where available, because it is cheaper per message and
 * users actually read it.
 */
export interface CommsAdapter {
  sendSms(to: string, body: string): Promise<void>;
  sendWhatsApp(to: string, template: string, params: Record<string, string>): Promise<void>;
}

class MockCommsAdapter implements CommsAdapter {
  private readonly logger = new Logger('MockComms');
  async sendSms(to: string, body: string): Promise<void> {
    this.logger.log(`[sms] ${to}: ${body}`);
  }
  async sendWhatsApp(to: string, template: string, params: Record<string, string>): Promise<void> {
    this.logger.log(`[whatsapp] ${to}: ${template} ${JSON.stringify(params)}`);
  }
}

@Injectable()
export class CommsService {
  private readonly logger = new Logger(CommsService.name);
  private readonly adapter: CommsAdapter;

  constructor(private readonly config: ConfigService) {
    const provider = this.config.get<string>('COMMS_PROVIDER') ?? 'mock';

    if (provider === 'twilio') {
      this.adapter = new TwilioAdapter({
        accountSid: this.config.get<string>('TWILIO_ACCOUNT_SID')!,
        authToken: this.config.get<string>('TWILIO_AUTH_TOKEN')!,
        fromNumber: this.config.get<string>('TWILIO_FROM_NUMBER')!,
      });
    } else {
      this.adapter = new MockCommsAdapter();
      this.logger.warn('comms is mocked; SMS and WhatsApp will not be sent');
    }

    this.logger.log(`comms provider: ${this.adapter.constructor.name}`);
  }

  async sendOtp(phoneE164: string, code: string, countryCode: 'ZA' | 'ZW'): Promise<void> {
    const brand = 'Freshly';
    // The code goes first: both Android SMS Retriever and iOS one-time-code
    // autofill scan the leading digits, and burying it behind marketing copy
    // is what breaks autofill in practice.
    const body = `${code} is your ${brand} code. It expires in 5 minutes. Never share it with anyone.`;
    await this.adapter.sendSms(phoneE164, body);
    this.logger.log(`otp dispatched to ${mask(phoneE164)} (${countryCode})`);
  }

  async notifyBookingAccepted(phoneE164: string, providerName: string, etaMinutes: number): Promise<void> {
    await this.adapter.sendWhatsApp(phoneE164, 'booking_accepted', {
      provider: providerName,
      eta: String(etaMinutes),
    });
  }

  /**
   * Sent when money has actually landed, never when it was merely requested.
   * A provider who gets "your payout is on the way" and then finds nothing in
   * their account stops trusting the wallet screen entirely.
   */
  async notifyPayoutSettled(phoneE164: string, netMinor: number, currency: string): Promise<void> {
    await this.adapter.sendSms(
      phoneE164,
      `${formatMoney(netMinor, currency)} from Freshly has been paid into your account.`,
    );
  }

  /**
   * SMS, never WhatsApp. An emergency contact may not have WhatsApp installed,
   * may be out of data, and a template message would need approval we cannot
   * get at 2am. SMS reaches every handset in both markets.
   */
  async sendSafetyAlert(phoneE164: string, personName: string, mapLink: string): Promise<void> {
    await this.adapter.sendSms(
      phoneE164,
      `${personName} triggered an emergency alert on Freshly and listed you as a contact. Their location: ${mapLink}`,
    );
  }

  async notifyProviderArrived(phoneE164: string, providerName: string): Promise<void> {
    await this.adapter.sendSms(
      phoneE164,
      `${providerName} has arrived for your Freshly booking. Share your 4-digit code when the service is done.`,
    );
  }
}

function mask(e164: string): string {
  return e164.length < 6 ? e164 : `${e164.slice(0, 5)}***${e164.slice(-2)}`;
}
