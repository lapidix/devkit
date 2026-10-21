---
paths:
  - "**/*Form*.{ts,tsx}"
  - "**/*.form.schema.ts"
---

# Forms with react-hook-form and zod

Forms use react-hook-form with the entity's zod form schema (`rules/frontend/entities.md`) through `zodResolver`. Call `useForm` directly in the form hook. The schema's messages are i18n keys translated at render, so a language switch needs no revalidation wrapper.

## The form hook

`features/{d}/hooks/use{Verb}{D}Form.ts` ties the form to the domain's mutation:

```ts
interface UseCreateUserFormOptions {
  organizationId: string;
  onSuccess?: () => void; // a reaction for this screen only, such as closing a drawer
}

export function toCreateUserCommand(values: CreateUserPayload, organizationId: string): CreateUserCommand {
  return { ...values, bio: values.bio || null, organizationId };
}

export function toFieldError(error: unknown) {
  if (error instanceof UserEmailTakenError) return { field: 'email', message: USER_MESSAGES.emailTaken } as const;
  return null;
}

export function useCreateUserForm({ organizationId, onSuccess }: UseCreateUserFormOptions) {
  const create = useMutation(UserMutations.create());
  const form = useForm({
    resolver: zodResolver(userFormSchema()),
    mode: 'onTouched',
    defaultValues: { email: '', nickname: '', bio: '' },
  });

  const handleSubmit = form.handleSubmit((values) =>
    create.mutate(toCreateUserCommand(values, organizationId), {
      onSuccess,
      onError: (error) => {
        const fieldError = toFieldError(error);
        if (fieldError) form.setError(fieldError.field, { message: fieldError.message });
      },
    }),
  );

  return { form, handleSubmit, isPending: create.isPending };
}
```

- It returns `{ form, handleSubmit, isPending }`. `isPending` comes from the mutation: with `mutate`, react-hook-form's `isSubmitting` turns false before the request ends. Resetting goes through `form.reset`.
- Screen reactions come in as options and go to `mutate(…, { onSuccess, onError })` (`rules/frontend/react-query.md`).
- The hook's decisions (building the command, choosing a field for an error) are exported plain functions beside it, so tests cover them without React; the hook only wires them to the form and the mutation (`rules/frontend/testing.md`).
- A field the entity keeps as `null` is `.nullable()` in the schema (`rules/frontend/entities.md`). The form shows it as `''`, and `toCreateUserCommand` turns `''` back into `null` (`values.bio || null`).

## Validation timing and the submit button

- `mode: 'onTouched'`: a field is first validated when it loses focus, then on every change. `mode: 'onBlur'` with `reValidateMode: 'onChange'` is not the same: `reValidateMode` applies only after the first submit.
- An input wrapped in `Controller` wires `onBlur` through its `render` prop, or `onTouched` never fires for it.
- The submit button is always enabled, except while the request is pending. Don't disable it on `isValid` or `isDirty`: a disabled button does not say what is wrong, while pressing it validates every field, shows every error and focuses the first one.

## Sub-components

A component that renders part of the form takes `form` as a prop:

```tsx
interface UserFormFieldsProps {
  form: UseFormReturn<UserFormValues>;
}
```

No `FormProvider` and `useFormContext`: the prop keeps the dependency visible and fully typed. `UserFormValues` is the input type the entity's schema file exports.

## Edit forms

The edit form's data is already loaded when it renders (`useSuspenseQuery`), so pass it to `defaultValues`. Don't call `reset` from a `useEffect` (`rules/frontend/react.md`). Use `values` with `resetOptions: { keepDirtyValues: true }` only when the open form must follow server changes.

## Server errors on fields

When the server rejects a value the user typed, show it on that field instead of in the default failure feedback.

- The domain error extends the shared `ValidationError`: `class UserEmailTakenError extends ValidationError {}` (`rules/frontend/shared.md`). The app's default failure reaction skips every `ValidationError`.
- Which error goes to which field is decided by `toFieldError`, with `instanceof`; `mutate`'s `onError` passes the result to `form.setError`. The message is a key from `{D}_MESSAGES` (`rules/frontend/i18n.md`).
- Don't call `form.setError` in `{D}Mutations`; those options serve every screen.
