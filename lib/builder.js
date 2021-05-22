const { promises: { mkdir, rm, stat }, existsSync } = require("fs");
const { spawnSync } = require("child_process");
const { forceSymlink } = require("./utils");
const path = require("path");

const buildDir = "build";

function runSync(cmd, ...args) {
    const result = spawnSync(cmd, args, { stdio: "inherit" });
    if (result.status !== 0) {
        process.exit(result.status);
    }
}

async function clean() {
    await rm(buildDir, { recursive: true, force: true });
}

async function build(mode, product) {
    const ctor = path.join(buildDir, `ctor-v1.o`);
    const static = path.join(buildDir, mode, `lib${product}.a`);
    const output = path.join(buildDir, mode, `${product}.node`);

    if (!existsSync(ctor)) {
        if (!existsSync(buildDir)) await mkdir(buildDir);
        runSync("cc", "-c", path.join(__dirname, "..", "src", "ctor.c"), "-o", ctor);
    }

    let ldflags;
    switch (process.platform) {
        case "darwin":
            ldflags = [
                "-Xlinker", "-undefined",
                "-Xlinker", "dynamic_lookup"
            ];
            break;
        case "linux":
            ldflags = [
                "-Xlinker", "-undefined"
            ];
            break;
        case "win32":
            // TODO: Figure out which flags we need on Windows
            ldflags = [];
            break;
        default:
            throw new Error(
                `The platform ${process.platform} is currently unsupported by node-swift.`
            );
    }

    runSync("swift", "build", "-c", mode, "--product", product, "--build-path", buildDir);

    // SPM creates a static library (intentionally, because we
    // don't want clients to have to worry about linking). Our
    // next swift invocation turns the lib into a dynamic library,
    // also linking the constructor which registers the module
    // with Node.

    let needsLink = true;
    try {
        const outputStat = await stat(output);
        const staticStat = await stat(static);
        // Make-esque check; only recreate the dylib if it's
        // older than the static lib (i.e. if SPM decided to
        // build the static lib right now)
        if (outputStat.mtime > staticStat.mtime) {
            needsLink = false;
        }
    } catch {}

    if (needsLink) {
        runSync("swiftc", "-emit-library", ctor, static, "-o", output, ...ldflags);
    }

    await forceSymlink(
        path.join(mode, `${product}.node`), 
        path.join(buildDir, `${product}.node`)
    );
}

module.exports = { clean, build };
