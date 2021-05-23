#!/usr/bin/env node

const builder = require("./builder");

function usage() {
    console.log("Usage: node-swift <rebuild [--debug] | build [--debug] | clean>");
    process.exit(1);
}

async function doClean(checkArgs) {
    if (checkArgs && process.argv.length !== 3) usage();
    await builder.clean();
}

async function doBuild() {
    let mode;
    if (process.argv.length === 3) {
        mode = "release";
    } else if (process.argv.length === 4 && process.argv[3] === "--debug") {
        mode = "debug";
    } else {
        usage();
    }
    const config = require("import-cwd")("./package.json").swift || {};
    const product = config.product;
    if (typeof product !== "undefined" && typeof product !== "string") {
        console.log("The swift.product field in package.json should be of type string, if present");
        process.exit(1);
    }
    await builder.build(mode, product);
}

if (process.argv.length < 3) usage();

(async () => {
    switch (process.argv[2]) {
        case "build":
            await doBuild();
            break;
        case "clean":
            await doClean(true);
            break;
        case "rebuild":
            await doClean();
            await doBuild();
            break;
        default:
            usage();
    }
})();
