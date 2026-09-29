import { Controller, Get, HttpStatus, Res } from '@nestjs/common';
import { Response } from 'express';
import { DbService } from './db.service';

@Controller()
export class ReadyController {
  constructor(private readonly db: DbService) {}

  @Get('ready')
  async ready(
    @Res({ passthrough: true }) res: Response,
  ): Promise<{ status: string }> {
    if (process.env.READY_FAIL === 'true' || !(await this.db.ping())) {
      res.status(HttpStatus.SERVICE_UNAVAILABLE);
      return { status: 'not_ready' };
    }
    return { status: 'ready' };
  }
}
