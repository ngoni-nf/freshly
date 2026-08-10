import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { randomUUID } from 'node:crypto';

interface ErrorBody {
  code: string;
  message: string;
  details?: unknown;
  traceId: string;
}

/**
 * One error shape for the whole API. Unhandled exceptions are logged with a
 * trace id and returned as a generic 500 — internal messages and stack traces
 * never cross the network boundary.
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger('ExceptionFilter');

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();
    const traceId = (request.headers['x-request-id'] as string) ?? randomUUID();

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let body: ErrorBody = { code: 'internal_error', message: 'Something went wrong on our side', traceId };

    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const payload = exception.getResponse();
      if (typeof payload === 'string') {
        body = { code: slug(exception.name), message: payload, traceId };
      } else {
        const obj = payload as Record<string, unknown>;
        body = {
          code: (obj.code as string) ?? slug(exception.name),
          message: Array.isArray(obj.message)
            ? (obj.message as string[]).join('; ')
            : ((obj.message as string) ?? exception.message),
          details: obj.details,
          traceId,
        };
      }
    } else {
      this.logger.error(
        `unhandled ${request.method} ${request.url} [${traceId}]`,
        exception instanceof Error ? exception.stack : String(exception),
      );
    }

    if (status >= 500) {
      this.logger.error(`${status} ${request.method} ${request.url} [${traceId}] ${body.message}`);
    }

    response.status(status).json(body);
  }
}

function slug(name: string): string {
  return name
    .replace(/Exception$/, '')
    .replace(/([a-z])([A-Z])/g, '$1_$2')
    .toLowerCase();
}
