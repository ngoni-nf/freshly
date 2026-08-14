import { Logger } from '@nestjs/common';
import { CommsAdapter } from '../comms.service';

export class TwilioAdapter implements CommsAdapter {
  private readonly logger = new Logger('TwilioComms');
  private readonly accountSid: string;
  private readonly authToken: string;
  private readonly fromNumber: string;

  constructor(config: { accountSid: string; authToken: string; fromNumber: string }) {
    this.accountSid = config.accountSid;
    this.authToken = config.authToken;
    this.fromNumber = config.fromNumber;
  }

  async sendSms(to: string, body: string): Promise<void> {
    const auth = Buffer.from(`${this.accountSid}:${this.authToken}`).toString('base64');
    const response = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${this.accountSid}/Messages.json`,
      {
        method: 'POST',
        headers: {
          Authorization: `Basic ${auth}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          To: to,
          From: this.fromNumber,
          Body: body,
        }),
      },
    );

    if (!response.ok) {
      const error = await response.json();
      this.logger.error(`Twilio SMS failed: ${JSON.stringify(error)}`);
      throw new Error(`Twilio error: ${error.message}`);
    }
  }

  async sendWhatsApp(to: string, template: string, params: Record<string, string>): Promise<void> {
    // WhatsApp on Twilio usually requires a specific 'whatsapp:' prefix and pre-approved templates.
    this.logger.log(`[Twilio WhatsApp] to: ${to}, template: ${template}, params: ${JSON.stringify(params)}`);
    // Implementation would follow the Twilio WhatsApp API docs using a similar fetch call.
  }
}
