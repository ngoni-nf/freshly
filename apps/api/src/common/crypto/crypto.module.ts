import { Global, Module } from '@nestjs/common';
import { PiiCryptoService } from './pii-crypto.service';

/**
 * Global because PII encryption is cross-cutting: auth hashes OTP codes and
 * refresh tokens, bookings encrypt completion PINs, KYC encrypts identity
 * numbers, messaging encrypts bodies. Re-providing it per feature module would
 * mean several instances each holding the same key material in memory.
 */
@Global()
@Module({ providers: [PiiCryptoService], exports: [PiiCryptoService] })
export class CryptoModule {}
