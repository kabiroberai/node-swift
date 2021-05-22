#!/usr/bin/env node

function usage() {
    console.log("Usage: node-swift build [--debug]");
    process.exit(1);
}

function doBuild(mode) {
    const spm = require("import-cwd")("./package.json").spm;
    const product = spm.product;
    if (typeof product !== "string") {
        console.log("package.json should contain an 'spm.product' string field.");
        process.exit(1);
    }
    require("./build")(mode, product);
}

if (process.argv.length < 3) usage();

switch (process.argv[2]) {
    case "build":
        let mode;
        if (process.argv.length === 3) {
            mode = "release";
        } else if (process.argv.length === 4 && process.argv[3] === "--debug") {
            mode = "debug";
        } else {
            usage();
        }
        doBuild(mode);
        break;
    default:
        usage();
}
