const globals = require("globals");
const js = require("@eslint/js");
// eslint-config-prettier 9 exports an eslintrc-shaped `{ rules }` object, which
// is already a valid flat config entry. The dedicated "/flat" entry point only
// exists from v10 onward.
const eslintConfigPrettier = require("eslint-config-prettier");

module.exports = [
  js.configs.recommended,
  {
    languageOptions: {
      globals: {
        ...globals.node,
        ...globals.jest,
      },
      ecmaVersion: "latest",
    },
  },
  {
    rules: {
      "no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", destructuredArrayIgnorePattern: "^_" },
      ],
    },
  },
  eslintConfigPrettier,
  {
    ignores: ["dist/**", "build/**"],
  },
];
