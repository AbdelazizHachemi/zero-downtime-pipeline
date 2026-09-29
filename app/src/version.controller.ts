import { Controller, Get } from '@nestjs/common';

@Controller()
export class VersionController {
  @Get('version')
  version(): { sha: string; builtAt: string } {
    return {
      sha: process.env.GIT_SHA || 'dev',
      builtAt: process.env.BUILT_AT || 'unknown',
    };
  }
}
