// rules/server/nestjs.md: exports only the use case another module's adapter injects
import { Module } from '@nestjs/common';
import { RevokeAllTokensUseCase } from './application/usecases/revoke-all-tokens.usecase';

@Module({
  providers: [RevokeAllTokensUseCase],
  exports: [RevokeAllTokensUseCase],
})
export class AuthModule {}
