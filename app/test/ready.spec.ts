import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { DbService } from '../src/db.service';

describe('GET /ready', () => {
  let app: INestApplication;

  beforeAll(async () => {
    delete process.env.DATABASE_URL;
    delete process.env.READY_FAIL;
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleRef.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    delete process.env.READY_FAIL;
    await app.close();
  });

  it('returns 503 when DATABASE_URL is unset', async () => {
    await request(app.getHttpServer())
      .get('/ready')
      .expect(503)
      .expect({ status: 'not_ready' });
  });

  it('returns 503 immediately when READY_FAIL is true', async () => {
    process.env.READY_FAIL = 'true';
    const ping = jest.spyOn(DbService.prototype, 'ping');
    await request(app.getHttpServer())
      .get('/ready')
      .expect(503)
      .expect({ status: 'not_ready' });
    expect(ping).not.toHaveBeenCalled();
    ping.mockRestore();
  });
});
