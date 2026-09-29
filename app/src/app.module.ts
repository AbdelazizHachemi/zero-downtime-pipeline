import { Module } from '@nestjs/common';
import { DbService } from './db.service';
import { HealthController } from './health.controller';
import { ReadyController } from './ready.controller';
import { VersionController } from './version.controller';

@Module({
  controllers: [HealthController, ReadyController, VersionController],
  providers: [DbService],
})
export class AppModule {}
