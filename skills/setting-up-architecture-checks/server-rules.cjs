// Server rules (rules/server/architecture.md). Paths match from the `src/` segment, so they cover a
// single server (src/...) and a server app in a monorepo (apps/server/src/...).
const MOD = '(^|/)src/modules/';

/** Frameworks, ORMs and generated ORM clients that the domain and shared kernel never import. */
const FRAMEWORK_AND_ORM = [
  '(^|/)node_modules/(@nestjs|@prisma|prisma|drizzle-orm|typeorm|mongoose|express|fastify)/',
  '(^|/)src/generated/',
];

module.exports = [
  {
    name: 'server-domain-is-pure',
    severity: 'error',
    comment:
      'domain/ is plain TypeScript: no framework, ORM, infrastructure or framework glue. Pass what it needs in as arguments or ports.',
    from: { path: `${MOD}[^/]+/domain/` },
    to: { path: ['(^|/)src/(infrastructure|common)/', ...FRAMEWORK_AND_ORM] },
  },
  {
    name: 'server-domain-own-module-only',
    severity: 'error',
    comment: "domain/ imports only its own module's domain and shared. Use cases combine modules, through ports.",
    from: { path: `${MOD}([^/]+)/domain/` },
    to: { path: MOD, pathNot: [`${MOD}$2/domain/`, `${MOD}$2/testkit/`] }, // testkits are limited to tests by server-testkit-tests-only
  },
  {
    name: 'server-application-only-domain',
    severity: 'error',
    comment:
      'application/ depends on the domain and its own ports. Adapters, infrastructure and framework glue stay outside; from the framework only @nestjs/common (for @Injectable) is allowed.',
    from: { path: `${MOD}([^/]+)/application/` },
    to: {
      path: [
        `${MOD}$2/adapters/`,
        '(^|/)src/(infrastructure|common|generated)/',
        '(^|/)node_modules/@nestjs/(?!common/)',
        '(^|/)node_modules/(@prisma|prisma|drizzle-orm|typeorm|mongoose|express|fastify)/',
      ],
    },
  },
  {
    name: 'server-application-no-other-modules',
    severity: 'error',
    comment:
      'A use case never imports another module. Declare a port in application/ports and implement it with an adapter in adapters/out.',
    from: { path: `${MOD}([^/]+)/application/` },
    to: { path: MOD, pathNot: `${MOD}$2/` },
  },
  {
    name: 'server-inbound-no-domain-model',
    severity: 'error',
    comment:
      "Inbound adapters build on use case results, never on the domain model. From the domain they import only {d}.const.ts (value lists for request and response schemas).",
    from: { path: `${MOD}([^/]+)/adapters/in/` },
    to: { path: `${MOD}$2/domain/`, pathNot: `${MOD}$2/domain/[^/]+\\.const\\.ts$` },
  },
  {
    name: 'server-inbound-only-application',
    severity: 'error',
    comment:
      'Inbound adapters call use cases. They never query through infrastructure or an ORM, and never reach another module.',
    from: { path: `${MOD}([^/]+)/adapters/in/` },
    to: {
      path: [
        '(^|/)src/(infrastructure|generated)/',
        '(^|/)node_modules/(@prisma|prisma|drizzle-orm|typeorm|mongoose)/',
        MOD,
      ],
      pathNot: `${MOD}$2/`,
    },
  },
  {
    name: 'server-outbound-no-common',
    severity: 'error',
    comment: 'Outbound adapters implement ports; framework glue (filters, guards, interceptors) is not theirs to use.',
    from: { path: `${MOD}[^/]+/adapters/out/` },
    to: { path: '(^|/)src/common/' },
  },
  {
    name: 'server-adapters-do-not-cross',
    severity: 'error',
    comment: 'Inbound and outbound adapters never import each other; both meet only at the application.',
    from: { path: `${MOD}([^/]+)/adapters/(in|out)/` },
    to: { path: `${MOD}$2/adapters/`, pathNot: `${MOD}$2/adapters/$3/` },
  },
  {
    name: 'server-no-cross-module-internals',
    severity: 'error',
    comment: "Another module is reached only through its index.ts.",
    from: { path: `${MOD}([^/]+)/` },
    to: { path: `${MOD}[^/]+/.+`, pathNot: [`${MOD}$2/`, `${MOD}[^/]+/index\\.ts$`] },
  },
  {
    name: 'server-platform-no-modules',
    severity: 'error',
    comment: 'shared, infrastructure and common serve every module, so they never import one.',
    from: { path: '(^|/)src/(shared|infrastructure|common)/' },
    to: { path: MOD },
  },
  {
    name: 'server-shared-is-pure',
    severity: 'error',
    comment:
      'The shared kernel holds base types every domain imports, so it imports no framework, ORM, infrastructure or framework glue; otherwise the domain reaches them through it.',
    from: { path: '(^|/)src/shared/' },
    to: { path: ['(^|/)src/(infrastructure|common)/', ...FRAMEWORK_AND_ORM] },
  },
  {
    name: 'server-testkit-tests-only',
    severity: 'error',
    comment: "Testkits build test data. Only the module's own tests and testkits import them; another module meets this one through its index.ts, never its test data.",
    from: { pathNot: ['\\.test\\.ts$', '(^|/)testkit/'] },
    to: { path: `${MOD}[^/]+/testkit/` },
  },
];
