#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Carbon (github.com/crbnos/carbon). Modified or adapted versions of this file,
// including ports, remain AGPLv3; serving them over a network requires releasing their source.

import { execSync } from "node:child_process";
import { basename } from "node:path";

// Mirrors the former bash postinstall: always build documents; skip root
// generate:mcp on Vercel MES deploys and on CI (non-Vercel).
const initCwd = process.env.INIT_CWD ?? "";
const skipMcp =
  (process.env.VERCEL && basename(initCwd) === "mes") ||
  (process.env.CI && !process.env.VERCEL);

const tasks = ["@carbon/documents#build"];
if (!skipMcp) {
  tasks.push("//#generate:mcp");
}

execSync(`turbo run ${tasks.join(" ")} --output-logs=new-only`, {
  stdio: "inherit",
});
