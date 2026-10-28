// Entity-layer rules. In a project, spread these into `forbidden` of .dependency-cruiser.cjs
// and adjust ENT if slices do not live under an `entities/` folder.
// Set `options.tsConfig` so path aliases resolve; unresolved paths cannot match these patterns.
const ENT = '(^|/)entities/';

module.exports = [
  {
    name: 'entity-domain-is-pure',
    comment:
      'domain/ holds entity types, behavior functions and value objects. It never reaches infrastructure, UI or React; pass what it needs as arguments.',
    severity: 'error',
    from: { path: `${ENT}[^/]+/domain/` },
    to: {
      path: [
        `${ENT}[^/]+/(infrastructure|ui)/`,
        '^react(-dom)?$',
        '(^|/)node_modules/react(-dom)?/',
      ],
    },
  },
  {
    name: 'entity-infrastructure-internals',
    comment:
      "DTOs, mappers, URLS and local tables are the server's and the database's formats. Only infrastructure/ uses them; the rest of the app gets entities through the adapter.",
    severity: 'error',
    from: { pathNot: `${ENT}[^/]+/infrastructure/` },
    to: { path: `${ENT}[^/]+/infrastructure/(dto/|mapper/|api/[^/]+\\.url\\.const\\.ts$|db/[^/]+\\.table\\.ts$)` },
  },
  {
    name: 'entity-infrastructure-same-slice',
    comment: "A slice's infrastructure uses its own DTOs and mapper, never another slice's.",
    severity: 'error',
    from: { path: `${ENT}([^/]+)/infrastructure/` },
    to: { path: `${ENT}[^/]+/infrastructure/`, pathNot: `${ENT}$2/infrastructure/` },
  },
  {
    name: 'entity-no-sibling-except-x',
    comment:
      "An entity reaches another entity only through that entity's @x/{consumer}.ts. To fix: store the id, or add the shape to the owner's @x file for this consumer. Another entity's testkit is exempt here; entity-testkit-tests-only limits it to tests and testkits.",
    severity: 'error',
    from: { path: `${ENT}([^/]+)/` },
    to: { path: `${ENT}[^/]+/`, pathNot: [`${ENT}$2/`, `${ENT}[^/]+/@x/`, `${ENT}[^/]+/testkit/`] },
  },
  {
    name: 'entity-x-consumer-only',
    comment: 'entities/{owner}/@x/{consumer}.ts lists what one consumer may import. Only that consumer imports it.',
    severity: 'error',
    from: { path: `${ENT}([^/]+)/` },
    to: { path: `${ENT}[^/]+/@x/`, pathNot: `${ENT}[^/]+/@x/$2\\.tsx?$` },
  },
  {
    name: 'entity-public-api',
    comment: "Outside entities/, import a slice only through its index.ts. Tests may also import its testkit.",
    severity: 'error',
    from: { pathNot: ENT },
    to: {
      path: `${ENT}[^/]+/.+`,
      pathNot: [`${ENT}[^/]+/index\\.tsx?$`, `${ENT}[^/]+/testkit/`],
    },
  },
  {
    name: 'entity-testkit-tests-only',
    comment: 'Testkits build test data. Only test files and other testkits import them.',
    severity: 'error',
    from: { pathNot: ['\\.test\\.tsx?$', '(^|/)testkit/'] },
    to: { path: `${ENT}[^/]+/testkit/` },
  },
];
