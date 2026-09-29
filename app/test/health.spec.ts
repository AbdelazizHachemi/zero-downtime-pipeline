import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { Pool } from 'pg';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('GET /health', () => {
  let app: INestApplication;
  const query = jest.spyOn(Pool.prototype, 'query');
  const connect = jest.spyOn(Pool.prototype, 'connect');

  beforeAll(async () => {
    delete process.env.DATABASE_URL;
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleRef.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    await app.close();
    query.mockRestore();
    connect.mockRestore();
  });

  it('returns 200 and does not open a database connection', async () => {
    await request(app.getHttpServer())
      .get('/health')
      .expect(200)
      .expect({ status: 'ok' });
    expect(query).not.toHaveBeenCalled();
    expect(connect).not.toHaveBeenCalled();
  });
});
