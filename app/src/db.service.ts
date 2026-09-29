import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { Pool } from 'pg';

@Injectable()
export class DbService implements OnModuleDestroy {
  private pool: Pool | null = null;

  async ping(): Promise<boolean> {
    const url = process.env.DATABASE_URL;
    if (!url) return false;

    if (!this.pool) {
      this.pool = new Pool({
        connectionString: url,
        connectionTimeoutMillis: 1000,
        query_timeout: 1000,
        statement_timeout: 1000,
      });
      // pg emits 'error' on an idle client when Postgres dies. Without a
      // listener Node exits, and a database blip becomes a restart loop.
      this.pool.on('error', (err: Error) => {
        process.stderr.write(
          `${JSON.stringify({
            time: new Date().toISOString(),
            msg: 'db pool error',
            error: err.message,
          })}\n`,
        );
      });
    }

    try {
      await this.pool.query('SELECT 1');
      return true;
    } catch {
      return false;
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.pool?.end();
  }
}
