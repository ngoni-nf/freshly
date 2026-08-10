import 'reflect-metadata';
import { Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from 'helmet';

import { AppModule } from './app.module';

async function bootstrap(): Promise<void> {
  // rawBody is what gateway webhook signatures are computed over. Re-encoding
  // the parsed JSON changes key order and whitespace, and every signature
  // check then fails for reasons that look like a vendor problem.
  const app = await NestFactory.create(AppModule, { bufferLogs: false, rawBody: true });
  const logger = new Logger('Bootstrap');

  app.use(helmet({ contentSecurityPolicy: false }));
  app.enableCors({
    origin: process.env.NODE_ENV === 'production'
      ? ['https://admin.freshly.africa', 'https://freshly.africa']
      : true,
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
