#!/usr/bin/env node
import { readFileSync, existsSync } from "node:fs";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import path from "node:path";
import { execSync } from "node:child_process";

async function resolveMmdlint(searchDirs = []) {
  const dirsToSearch = [
    ...searchDirs,
    process.cwd(),
    path.dirname(new URL(import.meta.url).pathname),
  ].filter(Boolean);

  for (const dir of dirsToSearch) {
    try {
      const pkgPath = path.join(dir, "package.json");
      const req = createRequire(existsSync(pkgPath) ? pkgPath : path.join(dir, "dummy.js"));
      const resolved = req.resolve("@sysid/mmdlint");
      if (resolved) {
        return await import(pathToFileURL(resolved).href);
      }
    } catch {
      // Continue to next directory
    }
  }

  // Try direct import (NODE_PATH or standard node_modules traversal)
  try {
    return await import("@sysid/mmdlint");
  } catch {
    // Continue
  }

  // Try global npm root
  try {
    const globalRoot = execSync("npm root -g", { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
    if (globalRoot && existsSync(path.join(globalRoot, "@sysid/mmdlint"))) {
      const req = createRequire(path.join(globalRoot, "dummy.js"));
      const resolved = req.resolve("@sysid/mmdlint");
      return await import(pathToFileURL(resolved).href);
    }
  } catch {
    // Continue
  }

  return null;
}

async function readAllStdin() {
  return new Promise((resolve, reject) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => {
      data += chunk;
    });
    process.stdin.on("end", () => {
      resolve(data);
    });
    process.stdin.on("error", (err) => {
      reject(err);
    });
  });
}

async function main() {
  let rawInput;
  try {
    rawInput = await readAllStdin();
  } catch (err) {
    console.error(JSON.stringify({
      ok: false,
      error_type: "STDIN_READ_ERROR",
      message: err.message
    }));
    process.exit(1);
  }

  if (!rawInput || rawInput.trim().length === 0) {
    console.log(JSON.stringify({
      ok: true,
      type: "empty",
      blocks: [],
      errors: []
    }));
    process.exit(0);
  }

  let payload;
  try {
    payload = JSON.parse(rawInput);
  } catch (err) {
    console.error(JSON.stringify({
      ok: false,
      error_type: "INVALID_JSON_INPUT",
      message: `Failed to parse input JSON: ${err.message}`
    }));
    process.exit(1);
  }

  const { type = "diagram", content = "", working_directory } = payload;
  const searchDirs = working_directory ? [working_directory] : [];
  const mmdlint = await resolveMmdlint(searchDirs);

  if (!mmdlint) {
    console.error(JSON.stringify({
      ok: false,
      error_type: "DEPENDENCY_NOT_FOUND",
      message: "Could not resolve @sysid/mmdlint. Please install it with 'npm install @sysid/mmdlint' or 'npm install -g @sysid/mmdlint'."
    }));
    process.exit(2);
  }

  try {
    if (type === "diagram") {
      const res = await mmdlint.validateMermaid(content);
      const errors = res.ok ? [] : [res.error || "Mermaid parse error"];
      const blocks = [
        {
          index: 1,
          startLine: 1,
          code: content,
          ok: res.ok,
          error: res.ok ? null : res.error
        }
      ];

      console.log(JSON.stringify({
        ok: res.ok,
        type: "diagram",
        blocks,
        errors
      }));
      process.exit(0);
    } else if (type === "markdown") {
      const blockResults = await mmdlint.validateMarkdown(content);
      const errors = [];
      const blocks = blockResults.map((b) => {
        if (!b.ok && b.error) {
          errors.push(b.error);
        }
        return {
          index: b.index,
          startLine: b.startLine,
          code: b.code,
          ok: b.ok,
          error: b.error || null
        };
      });

      const allOk = blocks.every((b) => b.ok);
      console.log(JSON.stringify({
        ok: allOk,
        type: "markdown",
        blocks,
        errors
      }));
      process.exit(0);
    } else {
      console.error(JSON.stringify({
        ok: false,
        error_type: "UNKNOWN_VALIDATION_TYPE",
        message: `Unknown validation type: '${type}'. Expected 'diagram' or 'markdown'.`
      }));
      process.exit(1);
    }
  } catch (err) {
    console.error(JSON.stringify({
      ok: false,
      error_type: "EXECUTION_ERROR",
      message: err instanceof Error ? err.message : String(err)
    }));
    process.exit(1);
  }
}

main();
