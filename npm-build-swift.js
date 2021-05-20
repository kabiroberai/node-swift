#!/usr/bin/env node

const package = require("./package.json");

const { promises: { copyFile, symlink, unlink }, existsSync } = require('fs');
const { spawnSync } = require('child_process');
const { exit } = require("process");

async function forceSymlink(target, path) {
    if (existsSync(path)) await unlink(path);
    await symlink(target, path);
}

function usage() {
    console.log("Usage: npm-build-swift <debug|release>");
    process.exit(1);
}

if (process.argv.length != 3) usage();

const [mode] = process.argv.slice(2);
if (mode !== "debug" && mode !== "release") usage();

const product = package.spm.product;
if (typeof product !== 'string') {
    console.log("package.json should contain an 'spm.product' string field.");
    exit(1);
}

let lib;
switch (process.platform) {
    case "darwin":
        lib = `lib${product}.dylib`;
        break;
    case "linux":
        lib = `lib${product}.so`;
        break;
    case "win32":
        lib = `${product}.dll`;
        break;
    default:
        throw new Error(
            `The platform ${process.platform} is currently unsupported by NodeAPI-Swift.`
        );
}

const { status } = spawnSync(
    "swift", ["build", "-c", mode, "--product", product],
    { stdio: [process.stdin, process.stdout, process.stderr] }
);
if (status !== 0) process.exit(status);

Promise.all([
    copyFile(`.build/${mode}/${lib}`, `.build/${mode}/${product}.node`),
    forceSymlink(mode, `.build/curr`)
]);
