# Judgment checklist

Apply the sections whose rule files cover the file under review. Each item names its rule file; the rule has the detail and the reason.

## Every TypeScript file (`typescript/conventions.md`)

- File names are `{subject}.{role}.ts`, except components (`UserCard.tsx`), hooks (`useUserFilter.ts`) and single-function shared helpers (`create-store.ts`).
- Exported names: `as const` objects in `SCREAMING_SNAKE`; instances and namespaces in `PascalCase`; action names verb first (`CreateUserCommand`); `create` only on functions that build a new object; names shared between test files carry `Test`.
- Contracts a function or component receives (props, commands, queries) are `interface`; data shapes are `type`.
- Comments say why, in English; none restate what the code does.

## Layers and slices

- The file sits in the layer and slice its job belongs to (`entities.md`, `features.md`, `widgets.md`, `pages.md`, `app.md`, `shared.md`): domain model and data access in entities, use cases and domain actions in features, screen sections in widgets, screen composition in pages, app-wide setup in app, domain-free code in shared.
- shared names no domain.
- A new slice exports an explicit `index.ts`; nothing outside imports past it.

## shared (`shared.md`, `entity-data-access.md`)

- Nothing in shared names a domain; domain code moves to an entity or above.
- `libs/` holds the HTTP client, library clients and setup, and domain-free behavior; pure functions go in `utils/`, drawn things in `ui/`.
- Environment variables are read only in `config/env.config.ts`.
- Shared error classes live in `libs/error/common.errors.ts`; entity errors extend `NotFoundError` or `ValidationError` where they fit.
- `libs/http` builds `httpClient` with arthron 2.1 or later, with `apiErrors` first in its plugins, and exports `HttpClient`, `unwrap`, `ApiError` and `isApiError`; a project on another client meets the guarantees listed in `entity-data-access.md` ("HTTP client").
- With `bearerAuth`, `tokenOrigins` lists absolute origins (the page's origin when `API_BASE_URL` is a path), and a refresh request through `httpClient` passes `meta: { bearerAuth: false }`.

## entities (`entities.md`, `entity-data-access.md`)

- Run `auditing-entity-slices` for every changed slice.

## features (`features.md`, `react-query.md`)

- Every operation has a use case `{verb}.usecase.ts` exporting `{Verb}{D}UseCase` with `execute(deps, command|query)`.
- `deps` picks only the adapter methods the use case calls (`Pick<UserAdapter, 'create'>`).
- Commands and queries are interfaces extending entity types, adding only call context.
- The use case validates its command with the entity's form schema before calling an adapter, and translates only the server error codes it knows.
- The service binds adapter instances to use cases, one method per use case, named after the use case file.
- `operations/` holds `{D}Queries` (queryOptions) and `{D}Mutations` (mutationOptions with invalidation through `{ client }`); `hooks/` holds only hooks; no hand-written query hooks.
- Screen reactions go in the caller's `mutate(…, { onSuccess, onError })`; data consistency stays in `{D}Mutations`.
- `index.ts` does not export the service or use cases.

## widgets (`widgets.md`)

- The slice is `widgets/{kind}/{name}/`, the component `{Name}{Kind}`.
- Props are identifiers and slots, never fetched data.
- Data comes from `useSuspenseQuery({D}Queries…)`; no widget-local hooks.
- No import from another widget.

## pages and app (`pages.md`, `app.md`)

- A page folder is named after its domain and holds only pages and `index.ts`.
- The page starts the first screen's requests (`usePrefetchQuery` in an SPA, a server prefetch with `HydrationBoundary` in Next.js) and owns the `AsyncBoundary`.
- A page defines no hooks; a Next.js page calls none.
- URL state (tabs, filters, sort, page number) goes through `useSearchParamState`.
- Routes only map URLs to pages; providers wrap what the whole app needs once.

## React (`react.md`)

- Components are `function` declarations with an interface `{Component}Props`, destructuring defaults, `on{Event}` props and `handle{Event}` handlers.
- No component defined inside another; a component file exports only its component, its props type and its constants.
- No nested ternaries; repeated UI uses an array and `map` when two of the three conditions hold.
- Effects only synchronize with external systems; no derived state, no prop copied into state, resets through `key`, async work cancels late results.
- Semantic elements, labelled inputs, buttons with an explicit `type`.

## Forms (`forms-rhf-zod.md`): form hooks and form components

- `useForm` takes `zodResolver` with the entity's form schema; no validation written in the form.
- The form hook returns `{ form, handleSubmit, isPending }` and takes screen reactions as options.
- Its decisions (building the command, choosing a field for an error) are exported plain functions beside it, with tests.
- `mode: 'onTouched'`; the submit button is disabled only while pending.
- Sub-components take `form` as a prop; no `FormProvider`.
- Edit forms pass loaded data to `defaultValues`.
- Server-rejected values extend `ValidationError` and reach the field through the hook's `toFieldError`.

## State (`state.md`)

- One store tool per project; domain stores in `entities/{d}/store/`, domain-free ones in `shared/store/`; file names end in `.store.ts`.
- Server data stays in React Query and URL state in the URL, not in a store.

## i18n (`i18n.md`)

- Every user-visible string goes through `t()`.
- Keys follow `{area}.{purpose}.{name}`, area first.
- Keys passed as data come from `{D}_MESSAGES` or `COMMON_MESSAGES`.
- Module constants hold keys, not translated text; no sentence is built from pieces.
- Every language file gets the same keys; the parity test covers them.

## Styling (`styling.md`)

- Colors and spacing come from tokens.
- Dates, numbers and empty values go through the shared formatters.
- With Tailwind, class names merge through `cn()`.

## Tests (`testing.md`)

- Code that makes decisions in a "Yes" row of the testing table (entity behavior, value objects, mapper, schema, adapter, use cases, hook decisions, `shared/libs`) has tests in the same change.
- Tests sit beside the source, are named after the behavior in English, inject fakes through arguments typed with `satisfies`, and take data from the testkit.
