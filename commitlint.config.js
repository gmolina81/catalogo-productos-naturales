/** @type {import('@commitlint/types').UserConfig} */
export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    // Scopes sugeridos en CLAUDE.md §12.1. `scope-enum` en level 1 = warning.
    'scope-enum': [
      1,
      'always',
      [
        'catalogo',
        'checkout',
        'admin',
        'sync',
        'db',
        'rls',
        'auth',
        'spec',
        'ci',
        'config',
        'docs',
        'tests',
        'deps',
      ],
    ],
    'body-max-line-length': [1, 'always', 120],
  },
}
