// rules/server/domain.md
export abstract class DomainError extends Error {
  abstract readonly code: string;
  abstract readonly kind: 'invalid' | 'unauthorized' | 'forbidden' | 'not_found' | 'conflict';
}
