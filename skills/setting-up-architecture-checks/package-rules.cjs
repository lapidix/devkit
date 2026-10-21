// Monorepo package rules (rules/monorepo/workspace.md). Paths are relative to the repository
// root, where the check runs.
//
//   allowed  { [packageDir]: string[] } the packages each package may import
//   entries  extra entry-point regexes, one per subpath export (src/index.ts is always allowed)
const fs = require('node:fs');

module.exports = function packageRules({ allowed, entries = [], packagesDir = 'packages' }) {
  // A package missing from the table gets no pkg-graph rule and may import anything unnoticed.
  const dirs = fs
    .readdirSync(packagesDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name);
  const missing = dirs.filter((name) => !(name in allowed));
  if (missing.length > 0) {
    throw new Error(`Packages missing from ALLOWED: ${missing.join(', ')}. Add each one so it gets a pkg-graph rule.`);
  }

  return [
    ...Object.entries(allowed).map(([name, deps]) => ({
      name: `pkg-graph-${name}`,
      severity: 'error',
      comment: deps.length
        ? `${name} may import only ${deps.join(', ')}. To add an arrow, change ALLOWED and give the reason in a comment beside it.`
        : `${name} imports no other package.`,
      from: { path: `^${packagesDir}/${name}/` },
      to: { path: `^${packagesDir}/`, pathNot: `^${packagesDir}/(${[name, ...deps].join('|')})/` },
    })),

    {
      name: 'pkg-public-api',
      severity: 'error',
      comment:
        'Enter a package only through the entry points in its package.json exports. A file reached directly becomes API nobody declared.',
      from: { path: '^(apps|packages)/([^/]+)/' },
      to: {
        path: `^${packagesDir}/[^/]+/`,
        pathNot: ['^$1/$2/', `^${packagesDir}/[^/]+/src/index\\.tsx?$`, ...entries],
      },
    },

    {
      name: 'pkg-no-app',
      severity: 'error',
      comment: 'A package never imports an app. The moment it does, a second app cannot use it.',
      from: { path: `^${packagesDir}/` },
      to: { path: '^apps/' },
    },
  ];
};
