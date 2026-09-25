const globals = require("globals");
const js = require("@eslint/js");
const eslintConfigPrettier = require("eslint-config-prettier/flat");

module.exports = [
  js.configs.recommended,
  {
    languageOptions: {
      globals: {
        ...globals.node,
        afterEach: "readonly",
        beforeEach: "readonly",
        describe: "readonly",
        expect: "readonly",
        fdescribe: "readonly",
        it: "readonly",
        test: "readonly",
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
