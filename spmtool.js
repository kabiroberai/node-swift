const { resolve, extname } = require('path');
const { existsSync, promises: { readdir, symlink, unlink } } = require('fs');
const { spawnSync } = require('child_process');

async function* getFiles(dir) {
    const dirents = await readdir(dir, { withFileTypes: true });
    for (const dirent of dirents) {
        const res = resolve(dir, dirent.name);
        if (dirent.isDirectory()) {
            yield* getFiles(res);
        } else {
            yield res;
        }
    }
}

let libExt;
switch (process.platform) {
    case "darwin":
        libExt = "dylib";
        break;
    case "linux":
        libExt = "so";
        break;
    case "win32":
        libExt = "dll";
        break;
    default:
        throw new Error("node-gyp + SPM is not yet supported on this platform.");
}

const sourceExts = ["swift", "c", "cc", "cpp"];

function outputPath(productName) {
    return `./build/lib${productName}.${libExt}`;
}

(async () => {
    const mode = process.argv[2];
    if (mode === 'inputs') {
        console.log(`./Package.swift`);
        const sourceExtSet = new Set(sourceExts.map(e => `.${e}`));
        for await (const f of getFiles(`./Sources`)) {
            const ext = extname(f);
            if (!sourceExtSet.has(ext)) continue;
            console.log(f + ' ');
        }
    } else if (mode === 'build') {
        const config = process.argv[3];
        const productName = process.argv[4];
        const args = ["build", "--product", productName, "-c", config.toLowerCase(), "--build-path", "build/spm"];
        spawnSync("swift", args, { stdio: [process.stdin, process.stdout, process.stderr] });
        args.push("--show-bin-path");
        const dir = spawnSync("swift", args).stdout.toString().trim();
        const output = outputPath(productName);
        if (existsSync(output)) await unlink(output);
        await symlink(`${dir}/lib${productName}.${libExt}`, output);
    } else if (mode === 'output') {
        const productName = process.argv[3];
        console.log(outputPath(productName));
    } else if (mode === 'ldflags') {
        const productName = process.argv[3];
        console.log(`-L. -l${productName} -rpath @loader_path/..`)
    }
})();
