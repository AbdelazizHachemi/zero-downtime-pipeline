import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { NextFunction, Request, Response } from 'express';
import { AppModule } from './app.module';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, { logger: ['error'] });
  app.enableShutdownHooks();
  app.use((req: Request, res: Response, next: NextFunction) => {
    const start = Date.now();
    res.on('finish', () => {
      process.stdout.write(
        `${JSON.stringify({
          time: new Date().toISOString(),
          method: req.method,
          path: req.path,
          status: res.statusCode,
          ms: Date.now() - start,
        })}\n`,
      );
    });
    next();
  });
  await app.listen(process.env.PORT ?? 3000);
}

void bootstrap();
