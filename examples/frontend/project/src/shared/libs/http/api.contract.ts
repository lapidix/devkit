// Follows rules/frontend/entity-data-access.md, "Mapper" (required throws a contract error naming the field).
export class ApiContractError extends Error {
  override readonly name = 'ApiContractError';
}

export function required<T>(value: T | null | undefined, path: string): T {
  if (value === null || value === undefined) throw new ApiContractError(`the response is missing ${path}`);
  return value;
}
