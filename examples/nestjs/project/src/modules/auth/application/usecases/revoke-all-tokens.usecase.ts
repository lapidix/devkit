// rules/server/application.md; a stub: the example only calls it
import { Injectable } from '@nestjs/common';

export interface RevokeAllTokensCommand {
  userId: string;
}
export type RevokeAllTokensResult = void;

@Injectable()
export class RevokeAllTokensUseCase {
  async execute(_command: RevokeAllTokensCommand): Promise<RevokeAllTokensResult> {}
}
