// Follows rules/frontend/entity-data-access.md, "HTTP client".
import { type ArthronClient, arthron } from 'arthron';
import { retry } from 'arthron/plugins';
import { ENV } from '@/shared/config/env.config';
import { apiErrors } from './api.errors';

export type HttpClient = ArthronClient;

export const httpClient: HttpClient = arthron({
  baseURL: ENV.API_BASE_URL,
  plugins: [apiErrors, retry()], // apiErrors first: it wraps retry, so it sees each call's final outcome
});
