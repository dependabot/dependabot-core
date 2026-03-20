const globals = require("globals");
const { defineConfig } = require("eslint/config");
const js = require("@eslint/js");
const eslintConfigPrettier = require("eslint-config-prettier/flat");

module.exports = defineConfig([
  js.configs.recommended,
  {
    languageOptions: {
      globals: {
        ...globals.node,
        ...globals.jest,
      },
    },
  },
  eslintConfigPrettier,
  {
    ignores: ["dist/**"],
  },
]);
