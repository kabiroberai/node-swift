const { promises: { mkdir }, existsSync } = require("fs");
const { spawnSync } = require("child_process");
const { forceSymlink } = require("./utils");
const path = require("path");

function runSync(cmd, ...args) {
    const result = spawnSync(cmd, args, { stdio: "inherit" });
    if (result.status !== 0) {
        process.exit(result.status);
    }
}

module.exports = async function build(mode, product) {
    const ctor = path.join(".build", `ctor-v1.o`);
    const static = path.join(".build", mode, `lib${product}.a`);
    const output = path.join(".build", mode, `${product}.node`);

    if (!existsSync(ctor)) {
        if (!existsSync(".build")) await mkdir(".build");
        runSync("cc", "-c", path.join(__dirname, "ctor.c"), "-o", ctor);
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

    runSync("swift", "build", "-c", mode, "--product", product);

    // SPM creates a static library (intentionally, because we
    // don't want clients to have to worry about linking). This
    // next command turns the lib into a dynamic library, also
    // linking the constructor which registers the module with
    // Node.
    runSync("swiftc", "-emit-library", ctor, static, "-o", output, ...ldflags);

    await forceSymlink(mode, path.join(".build", "curr"));
}
