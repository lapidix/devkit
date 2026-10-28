---
paths:
  - "**/entities/**"
  - "**/shared/vo/**"
---

# Frontend entities layer

The entities layer holds each domain's model, its data access, and the small UI that displays it. Data access (`infrastructure/`) has its own rule file: `rules/frontend/entity-data-access.md`.

## Slice structure

```
entities/{domain}/
├── domain/
│   ├── {d}.entity.ts             type {D}Entity + its behavior functions
│   └── {name}.vo.ts              product value objects
├── types/                        read models, aggregates, summaries
├── schema/{d}.form.schema.ts     form schema (projects using zod)
├── constants/
│   ├── {d}.query-key.const.ts    query keys (projects using React Query)
│   ├── {d}.message.const.ts      i18n keys passed as data
│   └── {d}.const.ts              public domain constants
├── errors/{d}.errors.ts          domain errors
├── store/{name}.store.ts         client state that belongs to this domain (rules/frontend/state.md)
├── infrastructure/               adapter, URLs, DTOs, mapper
├── @x/{consumer}.ts              what another entity may import from this one
├── ui/                           domain atoms + {d}.display.ts
├── testkit/                      test data factories
└── index.ts                      public API
```

Create a folder when the slice has something to put in it; most slices have no `@x/`.

## Entity, value object, or reference type

| It is | When | Lives in |
|---|---|---|
| **Entity** | It has an id **and** this app tracks its changes: fetches it on its own, updates or deletes it, or shows it as its own screen | its own slice |
| **Value object** | It is defined entirely by its value and replaced as a whole (`Email`, `Money`, `Nickname`) | see Value objects |
| **Reference type** | It has an id, but here it is only displayed inside something else (`workload.cluster: { id, name }`) | see Cross-entity references |

A status is a string union, not a value object.

## domain/{d}.entity.ts

An entity is a `type`, and its behavior is plain functions in the same file: the functions that would be methods and getters on a class. They take the entity as the first argument and return a new value instead of mutating.

```ts
export type TodoEntity = { id: string; status: TodoStatus; dueDate: string; doneAt: number | null };

export function isOverdue(todo: TodoEntity, today: string): boolean { … }
export function complete(todo: TodoEntity, now: number): TodoEntity {
  return { ...todo, status: 'done', doneAt: now };
}
```

Why no classes: entities pass through React Query caches, `structuredClone` and persisted storage, which strip prototypes, and React state updates need new objects rather than mutated ones.

The data an operation sends is picked from the entity and defined once here as `{Verb}{D}Payload`:

```ts
export type CreateUserPayload = Pick<UserEntity, 'email' | 'nickname' | 'bio'>;
export type UpdateUserPayload = Partial<Pick<UserEntity, 'nickname' | 'bio'>>;
```

When the file passes roughly 200 lines, move the functions to `{d}.behavior.ts` and leave only types in `{d}.entity.ts`. Consumers import from the slice's `index.ts`, so the split changes no import paths.

### Where a function belongs

| The function depends on | Example | Put it in |
|---|---|---|
| Only entity data and its arguments | derived status, whether a transition is allowed, sorting, invariant checks | `domain/{d}.entity.ts` |
| Presentation: translation, colors, formats | status label, status tone | `ui/{d}.display.ts` |
| I/O, or several entities in one use case | fetch then combine, create and charge | a use case in `features` |
| Code the server must share (monorepo) | sync merge rules | a Node-safe domain package |

## Value objects

A value object is a branded type plus the function that creates it, in its own file `{name}.vo.ts`. It imports nothing from other entity files (imports from `shared` are fine), so any file can depend on it without a cycle.

```ts
export type Email = string & { readonly __brand: 'Email' };
export function parseEmail(raw: string): Email {
  if (!EMAIL_PATTERN.test(raw)) throw new Error(`invalid email: ${raw}`);
  return raw as Email;
}
export function emailDomain(email: Email): string { … }
```

Only values that have a validation rule and cross boundaries (form, API, domain) become value objects. With zod 4, `z.email().brand<'Email'>()` defines the same type (`z.string().email()` is deprecated there; it is the zod 3 form).

- **Rule set by an external standard** (`Email`, `PhoneNumber`, `Money`, `Url`, `DateRange`): `shared/vo/{name}.vo.ts`.
- **Rule set by this product** (`Nickname`, `WorkloadName`): `domain/{name}.vo.ts` in the entity that owns the concept. Other entities get it through `@x`.

## types/

Plain types without validation of their own (their fields may use value object types): read models, aggregates, summaries. Query parameters for reads (`{D}ListParams`) live here too.

## schema/{d}.form.schema.ts

In projects using zod, each entity has **one** form schema: the validation of every field a user can provide. A form schema is knowledge about the entity; the form UI that uses it belongs to features.

```ts
export const userFormSchema = (options?: { bioMaxLength?: number }) =>
  z.object({
    email: EmailSchema,
    nickname: NicknameSchema,
    bio: z.string().max(options?.bioMaxLength ?? USER_BIO_MAX_LENGTH, USER_MESSAGES.bioMax).nullable(),
  });

export type UserFormValues = z.input<ReturnType<typeof userFormSchema>>;
```

- `{D}FormValues` is the form's input type; form components type `UseFormReturn<UserFormValues>` with it (`rules/frontend/forms-rhf-zod.md`).
- Validation messages are i18n keys from `{D}_MESSAGES`, not translated text (`rules/frontend/i18n.md`). A check whose message matters passes its own key; any other check gets the generic key from zod's global error map. The form translates them when it renders errors (`t(errors.bio?.message)`). Entities and use cases never see `t`.
- A use case validates its command with this schema, then calls the adapter. The adapter never sees the schema.
- A field the entity keeps as `null` (`bio: string | null`) is `.nullable()` in the schema, not `.optional()`. Payloads pick their types from the entity, so a command carries `null` there, and the use case's validation must accept it.
- Create and edit forms use the same schema. Limits that depend on runtime values come in through `options` (`userFormSchema({ bioMaxLength: plan.bioMaxLength })`); a form that edits only some fields takes them where that form lives: `userFormSchema().pick({ nickname: true, bio: true })`.
- Fields that exist in one form only (a confirm checkbox, one wizard step) are added where that form lives, with `.extend()`.

## constants/

`{d}.const.ts` holds public domain constants. `{d}.message.const.ts` holds `{D}_MESSAGES`, the i18n keys this domain passes as data (`rules/frontend/i18n.md`). In projects using React Query, `{d}.query-key.const.ts` holds the query keys; their rules are in `rules/frontend/react-query.md`.

## errors/{d}.errors.ts

Domain errors: what can go wrong with this domain, in its own words.

```ts
export class UserEmailTakenError extends ValidationError {}   // shared/libs/error
export class UserNotFoundError extends NotFoundError {}       // shared/libs/error
```

- A not-found error extends the shared `NotFoundError`, so the shared `AsyncBoundary` shows the not-found screen for any domain.
- An error a form shows on one of its fields (a value the server rejected) extends the shared `ValidationError`, so the default failure reaction leaves it to the form.

- Name them `{D}{Reason}Error`. Errors are classes, unlike entities, because callers need `instanceof` and a stack trace.
- A use case translates the server errors it knows into these (`409 USER_EMAIL_TAKEN` → `UserEmailTakenError`) and rethrows everything else unchanged.
- They live in entities so every feature that runs the same operation can catch the same error.

## ui/

Domain atoms: pure components that render one entity's values with the generic atoms from `shared/ui` (`UserStatusBadge` = `Badge` + user status tone and label, `UserAvatar`). They receive everything through props. Actions arrive as callback props or slots; data fetching, mutations and reading stores happen in features and widgets. The store itself may live in the entity's `store/`. Presentation helpers go in `ui/{d}.display.ts`.

## Cross-entity references

| Situation | Do this |
|---|---|
| Point at another entity | Store its id as `string` (`post.authorId`) |
| The API embeds another entity's summary | Type it with a `Pick` exported through the owner's `@x` |
| A screen combines two entities | Combine them in `features`, which may import both |
| The definition needs another entity's rule (a value object, a pure function) | Import it through the owner's `@x` |

`entities/{owner}/@x/{consumer}.ts` lists what one consumer entity may import from the owner. Only that consumer imports it. It exports types, value objects, unions and pure functions; never adapters, DTOs, mappers, UI, query keys or stores.

```ts
// entities/user/@x/post.ts
export type PostAuthor = Pick<UserEntity, 'id' | 'nickname' | 'avatarUrl'>;
```

- Use `Pick`. With `Omit`, every field later added to the owner flows into every consumer.
- A shape used by one consumer is defined in that `@x` file and named from the consumer's side (`PostAuthor`).
- A shape used by two or more consumers is defined once in the owner's `domain/{d}.entity.ts` (`UserPreview`), and each `@x` file re-exports it.
- Code outside the consumer names an embedded reference type through indexed access (`PostEntity['author']`); the consumer's `index.ts` does not re-export `@x` types.

## testkit/

Test data factories (`createTestUserEntity(overrides)`) in `testkit/{d}.testkit.ts`. Test files import that file by its full path; production code does not import it.

## index.ts

The public API is an explicit list of named exports; types use `export type`. Code outside the slice imports only from it.

```ts
export type { CreateUserPayload, UpdateUserPayload, UserEntity } from './domain/user.entity';
export { canSuspend } from './domain/user.entity';
export { userFormSchema, type UserFormValues } from './schema/user.form.schema';
export { USER_QUERY_KEYS } from './constants/user.query-key.const';
export { USER_MESSAGES } from './constants/user.message.const';
export { UserEmailTakenError, UserNotFoundError } from './errors/user.errors';
export { UserAdapter } from './infrastructure/api/user.adapter';
export { UserStatusBadge } from './ui/UserStatusBadge';
```

- The adapter is exported as its instance (`UserAdapter`, value and type), never its create function, so no second instance can exist outside the slice. A monorepo package does the opposite and exports only the create function and its type (`rules/frontend/entity-data-access.md`).
- DTOs, the mapper, `URLS`, `testkit` and `@x` stay out of it. Why explicit: one `export *` from `infrastructure/` publishes every DTO.

## Enforcement

dependency-cruiser enforces the boundaries above: domain purity, DTO and mapper isolation, `@x` consumers, the public API and test-only testkits. The rule set is `entity-rules.cjs` in the `setting-up-architecture-checks` skill, alongside the layer and package rules.
