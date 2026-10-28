---
paths:
  - "**/*.tsx"
  - "**/*.{ios,android,native,web}.ts"
  - "**/shared/libs/**"
---

# Platform differences

## Files, not branches

| The difference | Where it goes |
|---|---|
| A component that looks or behaves differently | Platform files: `DatePicker.tsx` and `DatePicker.web.tsx`, or `.ios.tsx` and `.android.tsx` |
| A platform capability (notifications, storage, the database, window control) | One interface, one implementation per platform file, in `shared/libs/{subject}/` |

- Metro picks the file for the platform it bundles (`.ios`, `.android`, then `.native`, then the plain file; `.web` for web), so the other files never reach that bundle.
- Every platform file of a module exports the same names with the same types. The plain file is the one TypeScript reads; a type that differs only in a platform file is not checked.
- Component bodies do not branch on `Platform.OS`. A branch keeps the other platform's code and imports in every bundle.

## React Native for Web

A component that also runs on web renders through React Native for Web, where some props mean something else. The ones that bit (react-native-web 0.21):

- `hitSlop` is read only by the old `Touchable`; `Pressable` ignores it, with no warning. A larger touch area comes from padding with an equal negative margin.
- `flex: 0` becomes CSS `flex: 0`, a basis of `0%`, so a view with a fixed height shrinks to its border. Turn off growing and shrinking with `flexGrow: 0` and `flexShrink: 0` and leave the basis.
- `onPress` passes the DOM `click` event: `nativeEvent` is a `MouseEvent`, with no `locationX` or `locationY`. A position comes from `clientX` and `clientY` minus `event.currentTarget.getBoundingClientRect()`. react-native-gesture-handler's `event.x` and `event.y` are already relative to the view.
