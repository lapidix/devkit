---
paths:
  - "**/*.tsx"
---

# Web accessibility

- Use semantic elements (`button`, `a`, `nav`), give every input a label, and give every `<button>` an explicit `type`.

Why the explicit `type`: a `<button>` without one is a submit button, so inside a form it submits the form.
