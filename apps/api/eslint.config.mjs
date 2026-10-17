// ESLint 9 flat config. The lint script existed from the start but had no
// config to read, so it had never run anywhere, including CI.
import tsParser from '@typescript-eslint/parser';
import tsPlugin from '@typescript-eslint/eslint-plugin';

export default [
  {
    ignores: ['dist/**', 'node_modules/**', 'coverage/**'],
  },
  {
    files: ['src/**/*.ts', 'test/**/*.ts'],
    languageOptions: {
      parser: tsParser,
      parserOptions: { ecmaVersion: 2022, sourceType: 'module' },
    },
    plugins: { '@typescript-eslint': tsPlugin },
    rules: {
      ...tsPlugin.configs.recommended.rules,
      // NestJS leans on decorators and DI; a constructor parameter that is
      // only there to be injected is not unused.
      '@typescript-eslint/no-unused-vars': ['error', {
        argsIgnorePattern: '^_',
        varsIgnorePattern: '^_',
        caughtErrorsIgnorePattern: '^_',
      }],
      // Raw rows from pg are Record<string, any> throughout; typing every
      // column at every call site is a different project.
      '@typescript-eslint/no-explicit-any': 'off',
      // `{}` is the idiomatic empty body type for Nest's own generics.
      '@typescript-eslint/no-empty-object-type': 'off',
      'no-console': 'error',
    },
  },
];
