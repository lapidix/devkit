// Boots UserModule as rules/server/nestjs.md wires it, under ClsModule with the Prisma adapter of
// rules/database/prisma.md. PrismaService is replaced by a fake, so no database is needed.
import { Module } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ClsPluginTransactional } from '@nestjs-cls/transactional';
import { TransactionalAdapterPrisma } from '@nestjs-cls/transactional-adapter-prisma';
import { ClsModule } from 'nestjs-cls';
import { describe, expect, it, vi } from 'vitest';
import { PrismaService } from '@/infrastructure/database/prisma.service';
import { GetUserDetailUseCase, UserModule, UserNotFoundError } from '@/modules/user';
import { WithdrawUserUseCase } from '@/modules/user/application/usecases/withdraw.usecase';

@Module({ providers: [PrismaService], exports: [PrismaService] })
class DatabaseModule {}

function boot(prisma: object) {
  return Test.createTestingModule({
    imports: [
      ClsModule.forRoot({
        global: true,
        plugins: [
          new ClsPluginTransactional({
            imports: [DatabaseModule],
            adapter: new TransactionalAdapterPrisma({ prismaInjectionToken: PrismaService }),
          }),
        ],
      }),
      UserModule,
    ],
  })
    .overrideProvider(PrismaService)
    .useValue(prisma)
    .compile();
}

const row = {
  id: 'user-1',
  nickname: 'kim',
  status: 'active',
  createdAt: new Date('2026-10-01T00:00:00Z'),
  updatedAt: new Date('2026-10-01T00:00:00Z'),
  withdrawnAt: null,
};

describe('UserModule', () => {
  it('resolves its use cases with the repository bound to Prisma', async () => {
    const prisma = { user: { findUnique: vi.fn().mockResolvedValue(null) } };
    const moduleRef = await boot(prisma);

    await expect(moduleRef.get(GetUserDetailUseCase).execute({ userId: 'nobody' })).rejects.toThrow(UserNotFoundError);
  });

  it('saves a withdrawal through the transaction that TransactionRunner opens', async () => {
    const tx = { user: { upsert: vi.fn().mockResolvedValue(row) } };
    const prisma = {
      user: { findUnique: vi.fn().mockResolvedValue(row), upsert: vi.fn() },
      $transaction: (fn: (client: typeof tx) => Promise<unknown>) => fn(tx),
    };
    const moduleRef = await boot(prisma);

    await moduleRef.get(WithdrawUserUseCase).execute({ userId: 'user-1', reason: 'moved' });

    expect(tx.user.upsert).toHaveBeenCalledOnce();
    expect(prisma.user.upsert).not.toHaveBeenCalled();
  });
});
