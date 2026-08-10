import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createCipheriv, createDecipheriv, createHash, randomBytes, timingSafeEqual } from 'node:crypto';

/**
 * AES-256-GCM envelope for personal information at rest.
 *
 * Applies to: national ID numbers, bank account numbers, message bodies.
 * Ciphertext layout is [12-byte IV][16-byte auth tag][ciphertext], stored in a
 * BYTEA column. The database never holds plaintext, so a dump of the tables —
 * the realistic breach scenario — yields nothing usable without the key, which
 * lives only in the process environment.
 */
@Injectable()
export class PiiCryptoService {
  private readonly key: Buffer;
  private readonly pepper: string;

  constructor(config: ConfigService) {
    const encoded = config.getOrThrow<string>('PII_ENCRYPTION_KEY');
    this.key = Buffer.from(encoded, 'base64');
    if (this.key.length !== 32) {
      throw new Error('PII_ENCRYPTION_KEY must decode to exactly 32 bytes (base64 of 32 random bytes)');
    }
    this.pepper = config.getOrThrow<string>('JWT_SECRET');
  }

  encrypt(plaintext: string): Buffer {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const body = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), body]);
  }

  decrypt(payload: Buffer): string {
    if (payload.length < 29) throw new Error('ciphertext too short to be valid');
    const iv = payload.subarray(0, 12);
    const tag = payload.subarray(12, 28);
    const body = payload.subarray(28);
    const decipher = createDecipheriv('aes-256-gcm', this.key, iv);
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(body), decipher.final()]).toString('utf8');
  }

  /** One-way hash for OTP codes and refresh tokens — never reversible. */
  hash(value: string): string {
    return createHash('sha256').update(`${value}:${this.pepper}`).digest('hex');
  }

  /** Constant-time comparison; short-circuiting here leaks the code. */
  verifyHash(value: string, expectedHash: string): boolean {
    const actual = Buffer.from(this.hash(value), 'hex');
    const expected = Buffer.from(expectedHash, 'hex');
    if (actual.length !== expected.length) return false;
    return timingSafeEqual(actual, expected);
  }

  /** Last four characters, for display without exposing the full value. */
  static last4(value: string): string {
    return value.replace(/\s+/g, '').slice(-4);
  }
}
