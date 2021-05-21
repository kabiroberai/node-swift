const { promises: { copyFile } } = require('fs');
const { spawnSync } = require('child_process');
const { forceSymlink } = require("./utils");

module.exports = async function build(mode, product) {
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
                `The platform ${process.platform} is currently unsupported by npm-build-swift.`
            );
    }

    const { status } = spawnSync(
        "swift", ["build", "-c", mode, "--product", product],
        { stdio: [process.stdin, process.stdout, process.stderr] }
    );
    console.log();
    if (status !== 0) process.exit(status);

    await Promise.all([
        copyFile(`.build/${mode}/${lib}`, `.build/${mode}/${product}.node`),
        forceSymlink(mode, `.build/curr`)
    ]);
}
