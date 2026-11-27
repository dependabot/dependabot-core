#!/usr/bin/node
"use strict";

const Module = require("node:module");
const path = require("node:path");

const projectNode = process.env.DEPENDABOT_PROJECT_NODE;

const tool = path.basename(process.argv[1]);
if (!["corepack", "pnpm", "yarn"].includes(tool))
  throw new Error(`Unexpected Corepack tool: ${tool}`);

// Corepack resolves and downloads with the image's proxy-aware Node. Its
// runMain handoff executes the resolved package manager with the project Node.
if (projectNode) {
  Module.runMain = () => {
    process.execve(
      projectNode,
      [projectNode, ...process.argv.slice(1)],
      process.env
    );
  };
}

require(`/usr/bin/${tool}`);
