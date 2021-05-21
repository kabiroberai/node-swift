#!/usr/bin/env node

const build = require("./build");

function usage() {
    console.log("Usage: npm-build-swift <debug|release>");
    process.exit(1);
}

if (process.argv.length != 3) usage();

const [mode] = process.argv.slice(2);
if (mode !== "debug" && mode !== "release") usage();

const spm = require("import-cwd")("./package.json").spm;
const product = spm.product;
if (typeof product !== 'string') {
    console.log("package.json should contain an 'spm.product' string field.");
    process.exit(1);
}

build(mode, product);
