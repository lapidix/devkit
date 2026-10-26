// Follows rules/frontend/i18n.md: a typed dictionary, so a key that does not exist fails type-checking.
import type { ko } from './locales/ko';

export type TranslationKey = keyof typeof ko;
