// FSD layer rules. Paths match from the `src/` segment, so one set covers a single app
// (src/...) and every app and package of a monorepo (apps/web/src/..., packages/user/src/...).
// Entity-specific rules live in entity-rules.cjs.
const SRC = '(^|/)src/';

/** The layers each layer must not import: everything above it. */
const ABOVE = {
  shared: '(entities|features|widgets|pages|app)',
  entities: '(features|widgets|pages|app)',
  features: '(widgets|pages|app)',
  widgets: '(pages|app)',
  pages: '(app)',
};

/** One slice per layer: a folder, except widgets, whose slice is {kind}/{name}. */
const SLICE = {
  features: '[^/]+',
  widgets: '[^/]+/[^/]+',
  pages: '[^/]+',
};

module.exports = [
  ...Object.entries(ABOVE).map(([layer, above]) => ({
    name: `fsd-layer-direction-${layer}`,
    severity: 'error',
    comment: `${layer} imports only the layers below it. Move what both sides need down to ${layer} or lower, or pass it in from above as props, slots or arguments.`,
    from: { path: `${SRC}${layer}/` },
    to: { path: `${SRC}${above}/` },
  })),

  ...Object.entries(SLICE).map(([layer, slice]) => ({
    name: `fsd-no-sibling-slice-${layer}`,
    severity: 'error',
    comment: `A ${layer} slice never imports another ${layer} slice. Move what both need down a layer.`,
    from: { path: `${SRC}${layer}/(${slice})/` },
    to: { path: `${SRC}${layer}/${slice}/`, pathNot: `${SRC}${layer}/$2/` },
  })),

  ...Object.entries(SLICE).map(([layer, slice]) => ({
    name: `fsd-public-api-${layer}`,
    severity: 'error',
    comment: `Outside a ${layer} slice, import only its index.ts. A file reached directly becomes API the slice never chose to export.`,
    from: { pathNot: `${SRC}${layer}/` },
    to: { path: `${SRC}${layer}/${slice}/.+`, pathNot: `${SRC}${layer}/${slice}/index\\.tsx?$` },
  })),
];
