import 'reflect-metadata';
import { Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from 'helmet';

import { AppModule } from './app.module';
import { RedisIoAdapter } from './modules/realtime/redis-io.adapter';

async function bootstrap(): Promise<void> {
  // rawBody is what gateway webhook signatures are computed over. Re-encoding
  // the parsed JSON changes key order and whitespace, and every signature
  // check then fails for reasons that look like a vendor problem.
  const app = await NestFactory.create(AppModule, { bufferLogs: false, rawBody: true });
  const logger = new Logger('Bootstrap');

  app.use(helmet({ contentSecurityPolicy: false }));
  // Origins are configuration, not code. They were hardcoded, which meant
  // changing the domain — or standing up a staging host — was a source edit
  // and a redeploy of the wrong shape. Comma-separated in CORS_ORIGINS.
  //
  // Production with nothing configured allows nothing rather than everything:
  // a permissive default is how a browser on any origin ends up holding a
  // session token, and an empty allowlist fails visibly instead of silently.
  const isProduction = process.env.NODE_ENV === 'production';
  const configuredOrigins = (process.env.CORS_ORIGINS ?? '')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);

  if (isProduction && configuredOrigins.length === 0) {
    logger.warn('CORS_ORIGINS is not set; the console and web will be refused by the browser');
  }

  app.enableCors({
    origin: isProduction ? configuredOrigins : true,
    credentials: true,
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: true },
    }),
  );

  app.enableShutdownHooks();

  // Before listen: the adapter must be in place when the gateway's server is
  // created, or that server keeps the in-process default and fans out nowhere.
  const realtimeAdapter = new RedisIoAdapter(app);
  await realtimeAdapter.connectToRedis(process.env.REDIS_URL ?? 'redis://localhost:6379');
  app.useWebSocketAdapter(realtimeAdapter);

  if (process.env.NODE_ENV !== 'production') {
    const config = new DocumentBuilder()
      .setTitle('Freshly API')
      .setDescription('On-demand beauty and grooming marketplace — South Africa and Zimbabwe')
      .setVersion('0.1.0')
      .addBearerAuth()
      .build();
    SwaggerModule.setup('docs', app, SwaggerModule.createDocument(app, config));
  }

  const port = Number(process.env.PORT ?? 3000);
  await app.listen(port, '0.0.0.0');
  logger.log(`Freshly API listening on :${port}`);
  if (process.env.NODE_ENV !== 'production') {
    logger.log(`API docs at http://localhost:${port}/docs`);
  }
}

void bootstrap();
