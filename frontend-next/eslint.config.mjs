import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
  ]),
  {
    // The app's content is Italian, which uses apostrophes constantly
    // (l'autenticità, dell'ordine, c'è...). frontend/'s eslint config never
    // enforced this rule either; disabling it project-wide rather than
    // escaping every apostrophe across the entire copied and future-ported
    // Italian-language JSX content.
    rules: {
      "react/no-unescaped-entities": "off",
    },
  },
  {
    // Next 16's bundled eslint-config-next adds React Compiler-era purity
    // rules that frontend/ (the source of these copied files) does not
    // enforce. The flagged patterns (Math.random() in useMemo, setState in
    // an effect body, a local accumulator variable) are pre-existing and
    // already validated in frontend/'s CI - fixing them would mean
    // rewriting component logic, which is out of scope for a "copia
    // invariata" migration phase. Revisit when these components are
    // actually adapted in a later phase.
    files: [
      "src/components/ui/**/*.tsx",
      "src/components/vinea/**/*.tsx",
      "src/hooks/**/*.tsx",
    ],
    rules: {
      "react-hooks/purity": "off",
      "react-hooks/set-state-in-effect": "off",
      "react-hooks/immutability": "off",
    },
  },
]);

export default eslintConfig;
