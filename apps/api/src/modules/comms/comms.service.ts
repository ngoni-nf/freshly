import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

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
    // Gupshup and Twilio adapters slot in here; the mock keeps local
    // development free of credentials and free of spend.
    this.adapter = new MockCommsAdapter();
    this.logger.log(`comms provider: ${provider}`);
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
