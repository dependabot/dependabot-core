const globals = require("globals");
const { defineConfig } = require("eslint/config");
const js = require("@eslint/js");
const eslintConfigPrettier = require("eslint-config-prettier/flat");

// Rules not included before upgrading to ESLint 9. Can be enabled later
const temporaryDisabledRules = {
    rules: {
        "no-unused-vars": "off",
        "no-extra-boolean-cast": "off",
        "no-undef": "off"
    },
}

module.exports = defineConfig([
    js.configs.recommended,
    {
        languageOptions: {
            globals: {
                ...globals.node,
                ...globals.jest
            }
        },
    },
    temporaryDisabledRules,
    eslintConfigPrettier
])