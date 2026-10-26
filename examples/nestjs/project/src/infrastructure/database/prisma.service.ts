// rules/database/prisma.md: extends the generated client; the module that provides it passes the driver adapter
import { PrismaClient } from '@/generated/prisma/client';

export class PrismaService extends PrismaClient {}
