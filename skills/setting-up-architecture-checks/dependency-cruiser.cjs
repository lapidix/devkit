/**
 * Architecture checks. Copy to the repository root as `.dependency-cruiser.cjs`, with the rule
 * files in `.dependency-cruiser/`. It runs once from the root:
 *
 *   monorepo     depcruise apps packages --config .dependency-cruiser.cjs
 *   single app   depcruise src --config .dependency-cruiser.cjs   (delete the package section)
 *
 * Keep the rule sets the repository needs: fsd and entity rules for frontend apps, server rules for
 * a server (rules/server/architecture.md). A monorepo with both keeps all of them.
 */
const fsdRules = require('./.dependency-cruiser/fsd-rules.cjs');
const entityRules = require('./.dependency-cruiser/entity-rules.cjs');
const serverRules = require('./.dependency-cruiser/server-rules.cjs');
const packageRules = require('./.dependency-cruiser/package-rules.cjs');

// --- packages (monorepo only) ---------------------------------------------------------------

/**
 * The package directories each directory under packages/ may import, keyed by directory name
 * (`ui`, not `@repo/ui`). Every package directory must appear, with a comment saying what it is for.
 */
const ALLOWED = {
  // ui: [], // design-system components; knows no domain
  // user: ['ui'], // user screens and their data access
};

/** The source file of each subpath export, as a regex. src/index.ts is always allowed. */
const ENTRIES = [
  // '^packages/ui/src/icons/index\\.ts$',
];

// ---------------------------------------------------------------------------------------------

module.exports = {
  forbidden: [
    ...fsdRules,
    ...entityRules,
    ...serverRules,
    ...packageRules({ allowed: ALLOWED, entries: ENTRIES }),

    {
      name: 'no-circular',
      severity: 'error',
      comment: 'A cycle leaves no order in which the modules make sense. Break it by moving the shared piece down.',
      from: {},
      to: { circular: true },
    },
    {
      name: 'not-to-unresolvable',
      severity: 'error',
      comment:
        "An import that does not resolve: a path outside a package's exports, an undeclared workspace dependency, or an alias the tsconfig below does not map.",
      from: {},
      to: { couldNotResolve: true },
    },
  ],

  options: {
    // A generated client stays in the graph, so the server rules can forbid importing it, but its
    // internals are not followed: Prisma's generated client imports itself in cycles.
    doNotFollow: { path: ['node_modules', '(^|/)src/generated/'] },
    tsPreCompilationDeps: true,
    // Maps every app's path alias (rules/monorepo/workspace.md). A single app can point at tsconfig.json.
    tsConfig: { fileName: 'tsconfig.depcruise.json' },
    enhancedResolveOptions: {
      exportsFields: ['exports'],
      conditionNames: ['import', 'require', 'default'],
    },
  },
};
