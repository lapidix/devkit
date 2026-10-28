// Follows rules/frontend/entities.md, "Value objects" (a standard one, in shared/vo); z.email() is zod 4's z.string().email().
import { z } from 'zod';

export type Email = z.infer<typeof EmailSchema>;
export const EmailSchema = z.email().brand<'Email'>();
