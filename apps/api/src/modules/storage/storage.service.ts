import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { DomainError } from '../../common/errors/domain.errors';

/**
 * What a file is for. The purpose decides the bucket, who may read it back,
 * and how long a link lives — not the caller, because the caller is a phone.
 */
export type UploadPurpose = 'kyc_document' | 'kyc_selfie' | 'credential_document' | 'portfolio' | 'avatar';

interface PurposeRule {
  bucket: string;
  /** Private buckets are only ever reachable through a short-lived signed URL. */
  isPublic: boolean;
  maxBytes: number;
  contentTypes: string[];
  /** Seconds a download link stays valid. */
  readTtl: number;
}

/**
 * Identity documents are the most sensitive thing this platform touches, and
 * the shortest-lived. A portfolio photo is meant to be seen; a passport scan
 * is meant to be looked at once by a reviewer and never again.
 */
const RULES: Record<UploadPurpose, PurposeRule> = {
  kyc_document: {
    bucket: 'kyc-documents',
    isPublic: false,
    maxBytes: 8 * 1024 * 1024,
    contentTypes: ['image/jpeg', 'image/png', 'image/heic', 'application/pdf'],
    readTtl: 300,
  },
  kyc_selfie: {
    bucket: 'kyc-documents',
    isPublic: false,
    maxBytes: 8 * 1024 * 1024,
    contentTypes: ['image/jpeg', 'image/png', 'image/heic'],
    readTtl: 300,
  },
  credential_document: {
    bucket: 'kyc-documents',
    isPublic: false,
    maxBytes: 8 * 1024 * 1024,
    contentTypes: ['image/jpeg', 'image/png', 'image/heic', 'application/pdf'],
    readTtl: 300,
  },
  portfolio: {
    bucket: 'portfolio',
    isPublic: true,
    maxBytes: 5 * 1024 * 1024,
    contentTypes: ['image/jpeg', 'image/png', 'image/webp'],
    readTtl: 3600,
  },
  avatar: {
    bucket: 'avatars',
    isPublic: true,
    maxBytes: 2 * 1024 * 1024,
    contentTypes: ['image/jpeg', 'image/png', 'image/webp'],
    readTtl: 3600,
  },
};

export interface SignedUpload {
  bucket: string;
  /** Store this on the row. It is what the KYC submission already expects. */
  key: string;
  uploadUrl: string;
  /** Supabase wants this back as the Authorization header on the PUT. */
  token?: string;
  expiresIn: number;
  maxBytes: number;
  contentTypes: string[];
}

interface StorageAdapter {
  readonly name: string;
  signUpload(bucket: string, key: string, ttl: number): Promise<{ uploadUrl: string; token?: string }>;
  signDownload(bucket: string, key: string, ttl: number): Promise<string>;
}

/**
 * Local development. Hands back a URL that goes nowhere on purpose — a mock
 * that pretended to accept a file would let the whole upload path ship
 * untested against anything real.
 */
class MockStorageAdapter implements StorageAdapter {
  readonly name = 'mock';
  private readonly logger = new Logger('MockStorage');

  async signUpload(bucket: string, key: string): Promise<{ uploadUrl: string }> {
    this.logger.log(`[mock] would accept an upload to ${bucket}/${key}`);
    return { uploadUrl: `mock://storage/${bucket}/${key}` };
  }

  async signDownload(bucket: string, key: string): Promise<string> {
    return `mock://storage/${bucket}/${key}`;
  }
}

/**
 * Supabase Storage over its REST API, authenticated with the service role key.
 *
 * The service key never leaves this process. The app receives a single-object,
 * short-lived signed URL and nothing else — which is the whole reason uploads
 * are brokered here rather than letting the client hold a key and talk to
 * Storage directly.
 */
class SupabaseStorageAdapter implements StorageAdapter {
  readonly name = 'supabase';

  constructor(
    private readonly baseUrl: string,
    private readonly serviceKey: string,
  ) {}

  private headers() {
    return {
      Authorization: `Bearer ${this.serviceKey}`,
      apikey: this.serviceKey,
      'Content-Type': 'application/json',
    };
  }

  async signUpload(bucket: string, key: string): Promise<{ uploadUrl: string; token?: string }> {
    const response = await fetch(
      `${this.baseUrl}/storage/v1/object/upload/sign/${bucket}/${encodeURI(key)}`,
      { method: 'POST', headers: this.headers() },
    );
    if (!response.ok) {
      throw new Error(`storage sign-upload failed with ${response.status}: ${await response.text()}`);
    }
    const body = (await response.json()) as { url?: string; token?: string };
    if (!body.url) throw new Error('storage sign-upload returned no url');
    return { uploadUrl: `${this.baseUrl}/storage/v1${body.url}`, token: body.token };
  }

  async signDownload(bucket: string, key: string, ttl: number): Promise<string> {
    const response = await fetch(
      `${this.baseUrl}/storage/v1/object/sign/${bucket}/${encodeURI(key)}`,
      { method: 'POST', headers: this.headers(), body: JSON.stringify({ expiresIn: ttl }) },
    );
    if (!response.ok) {
      throw new Error(`storage sign-download failed with ${response.status}`);
    }
    const body = (await response.json()) as { signedURL?: string };
    if (!body.signedURL) throw new Error('storage sign-download returned no signedURL');
    return `${this.baseUrl}/storage/v1${body.signedURL}`;
  }
}

@Injectable()
export class StorageService {
  private readonly logger = new Logger(StorageService.name);
  private readonly adapter: StorageAdapter;

  constructor(private readonly config: ConfigService) {
    const baseUrl = this.config.get<string>('SUPABASE_URL');
    const serviceKey = this.config.get<string>('SUPABASE_SERVICE_ROLE_KEY');

    if (baseUrl && serviceKey) {
      this.adapter = new SupabaseStorageAdapter(baseUrl.replace(/\/$/, ''), serviceKey);
    } else {
      this.adapter = new MockStorageAdapter();
      this.logger.warn('storage is mocked; set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY to store files');
    }
    this.logger.log(`storage adapter: ${this.adapter.name}`);
  }

  /**
   * Broker an upload.
   *
   * The key is derived here and never taken from the caller. A client-supplied
   * path is a directory traversal and an overwrite of somebody else's identity
   * document waiting to happen — every object is namespaced under the owner's
   * id, so the worst a caller can do is overwrite their own file.
   */
  async signUpload(
    ownerId: string,
    purpose: UploadPurpose,
    contentType: string,
    fileName?: string,
  ): Promise<SignedUpload> {
    const rule = RULES[purpose];
    if (!rule) {
      throw new DomainError('unknown_purpose', 'That upload type is not supported', HttpStatus.BAD_REQUEST);
    }
    if (!rule.contentTypes.includes(contentType)) {
      throw new DomainError(
        'unsupported_file_type',
        `Upload a ${rule.contentTypes.map(shortType).join(', ')} file`,
        HttpStatus.UNPROCESSABLE_ENTITY,
        { allowed: rule.contentTypes },
      );
    }

    const key = `${ownerId}/${purpose}/${randomUUID()}${extensionFor(contentType, fileName)}`;

    try {
      const { uploadUrl, token } = await this.adapter.signUpload(rule.bucket, key, 600);
      return {
        bucket: rule.bucket,
        key,
        uploadUrl,
        token,
        expiresIn: 600,
        maxBytes: rule.maxBytes,
        contentTypes: rule.contentTypes,
      };
    } catch (err) {
      this.logger.error(`sign upload failed for ${purpose}: ${(err as Error).message}`);
      throw new DomainError(
        'storage_unavailable',
        'We could not start your upload. Please try again.',
        HttpStatus.BAD_GATEWAY,
      );
    }
  }

  /**
   * A link to look at a stored object. Private buckets only ever produce a
   * short-lived signed URL, so a leaked link expires instead of becoming a
   * permanent handle on somebody's passport.
   */
  async signDownload(bucket: string, key: string): Promise<{ url: string; expiresIn: number }> {
    const rule = Object.values(RULES).find((r) => r.bucket === bucket);
    const ttl = rule?.readTtl ?? 300;
    const url = await this.adapter.signDownload(bucket, key, ttl);
    return { url, expiresIn: ttl };
  }

  /** Guards a caller trying to read a key that is not theirs. */
  static isOwnedBy(key: string, ownerId: string): boolean {
    return key.startsWith(`${ownerId}/`);
  }
}

function shortType(contentType: string): string {
  return contentType.split('/')[1]?.toUpperCase() ?? contentType;
}

function extensionFor(contentType: string, fileName?: string): string {
  const known: Record<string, string> = {
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/webp': '.webp',
    'image/heic': '.heic',
    'application/pdf': '.pdf',
  };
  if (known[contentType]) return known[contentType];
  const fromName = fileName?.match(/(\.[a-z0-9]{1,5})$/i)?.[1];
  return fromName ?? '';
}
