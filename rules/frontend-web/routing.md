---
paths:
  - "**/pages/**"
  - "**/libs/router/**"
---

# URL state

A web app's address is state the user can share and reload. The page decides what goes in it (`rules/frontend/pages.md`).

## State in the URL

| In the URL: must survive sharing a link and reloading | In the component |
|---|---|
| The page's tab (`?tab=usage`) | Tabs inside a drawer or dialog |
| List filters, sort and page number | Form wizard steps |
| | Momentary state such as expanded or collapsed |

## libs/router

URL state (a page's tab, list filters, sort, page number) goes through one hook in `shared/libs/router`:

```ts
const [tab, setTab] = useSearchParamState('tab', { defaultValue: 'overview' });
```

It owns the rules every URL state shares: the default value is not written to the URL, changing state replaces the history entry instead of pushing one, and numbers are parsed.
