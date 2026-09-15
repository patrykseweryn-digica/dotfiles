import js from "@eslint/js";
import globals from "globals";
import ts from "typescript-eslint";

export default [
  js.configs.recommended,
  ...ts.configs.recommended,
  { languageOptions: { globals: globals.node } },
];
