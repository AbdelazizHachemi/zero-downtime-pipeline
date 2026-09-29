import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('GET /version', () => {
  let app: INestApplication;

  beforeAll(async () => {
    process.env.GIT_SHA = 'abc123def';
    process.env.BUILT_AT = '2026-09-29T00:00:00Z';
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleRef.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    delete process.env.GIT_SHA;
    delete process.env.BUILT_AT;
    await app.close();
  });

  it('returns GIT_SHA', async () => {
    await request(app.getHttpServer()).get('/version').expect(200).expect({
      sha: 'abc123def',
      builtAt: '2026-09-29T00:00:00Z',
    });
  });
});
