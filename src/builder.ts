import { rm, rename, realpath } from "fs/promises";
import { spawnSync } from "child_process";
import { forceSymlink } from "./utils";
import path from "path";

const buildDir = "build";

// the name of the binary that the DLL loader *expects* to find
// (probably doesn't need to be changed)
const winHost = "node.exe";

export type BuildMode = "release" | "debug";

export type ConfigFlags = string | string[];

export interface Config {
    packagePath?: string
    product?: string

    triple?: string
    macVersion?: string
    napi?: number | "experimental"

    static?: boolean
    spmFlags?: ConfigFlags
    cFlags?: ConfigFlags
    swiftFlags?: ConfigFlags
    cxxFlags?: ConfigFlags
    linkerFlags?: ConfigFlags
}

export async function clean() {
    await rm(buildDir, { recursive: true, force: true });
}

async function getWinLib(): Promise<string> {
    let filename;
    switch (process.arch) {
        case "x64":
            filename = "node-win32-x64.lib";
            break;
        default:
            throw new Error(
                `The arch ${process.arch} is currently unsupported by node-swift.`
            );
    }
    return path.join(__dirname, "..", "vendored", "node", "lib", filename);
}

function getFlags(config: Config, name: string) {
    const flags = (config as any)[name];
    if (typeof flags === "undefined") {
        return [];
    } else if (typeof flags === "string") {
        return flags.split(" ");
    } else if (Array.isArray(flags) && flags.every(t => (typeof t) === "string")) {
        return flags;
    } else {
        throw new Error(`Invalid value for ${name}`);
    }
}

export async function build(mode: BuildMode, config: Config = {}): Promise<string> {
    let spmFlags = getFlags(config, "spmFlags");
    let cFlags = getFlags(config, "cFlags");
    let swiftFlags = getFlags(config, "swiftFlags");
    let cxxFlags = getFlags(config, "cxxFlags");
    let linkerFlags = getFlags(config, "linkerFlags");

    let isDynamic: boolean;
    if (typeof config.static === "boolean") {
        isDynamic = !config.static;
    } else if (typeof config.static === "undefined") {
        isDynamic = true;
    } else {
        throw new Error("Invalid value for static option");
    }

    let packagePath;
    if (typeof config.packagePath === "string") {
        packagePath = await realpath(config.packagePath);
    } else if (typeof config.packagePath === "undefined") {
        packagePath = process.cwd();
    } else {
        throw new Error("Invalid value for packagePath option.");
    }

    let macVersion;
    if (typeof config.macVersion === "string") {
        macVersion = config.macVersion;
    } else if (typeof config.macVersion === "undefined") {
        macVersion = "10.10";
    } else {
        throw new Error("Invalid value for macVersion option.");
    }

    let product = config.product;

    let napi = config.napi;

    if (typeof config.triple === "string") {
        spmFlags.push("--triple", config.triple);
    } else if (typeof config.triple !== "undefined") {
        throw new Error("Invalid value for triple option.");
    }

    if (typeof napi === "number") {
        cFlags.push(`-DNAPI_VERSION=${napi}`);
        swiftFlags.push("-DNAPI_VERSIONED");
        for (let i = 1; i <= napi; i++) {
            swiftFlags.push(`-DNAPI_GE_${i}`);
        }
    } else if (typeof napi === "string" && napi === "experimental") {
        cFlags.push("-DNAPI_EXPERIMENTAL");
        swiftFlags.push("-DNAPI_EXPERIMENTAL");
    } else if (typeof napi !== "undefined") {
        throw new Error("Invalid value for napi option.");
    }

    const allFlags = spmFlags.concat(
        cFlags.flatMap(f => ["-Xcc", f]),
        swiftFlags.flatMap(f => ["-Xswiftc", f]),
        cxxFlags.flatMap(f => ["-Xcxx", f]),
        linkerFlags.flatMap(f => ["-Xlinker", f])
    );

    const dump = spawnSync(
        "swift",
        [
            "package",
            "dump-package",
            "--package-path", packagePath,
            ...allFlags,
        ],
        { stdio: ["inherit", "pipe", "inherit"] }
    );
    if (dump.status !== 0) {
        throw new Error(`swift package dump-package exited with status ${dump.status}`);
    }
    const parsedPackage = JSON.parse(dump.stdout.toString());
    if (typeof product === "undefined") {
        const products = parsedPackage.products;
        if (products.length === 0) {
            throw new Error("No products found in Swift Package");
        } else if (products.length === 1) {
            product = products[0].name;
        } else {
            throw new Error(
                "Found more than 1 product in the Swift Package. Consider " +
                "specifying which product should be built via the swift.product " +
                "field in package.json."
            );
        }
    } else if (typeof product !== "string") {
        throw new Error("The config product field should be of type string, if present");
    }

    let libName;
    let ldflags;
    switch (process.platform) {
        case "darwin":
            libName = "libNodeSwiftHost.dylib";
            ldflags = [
                "-Xlinker", "-undefined",
                "-Xlinker", "dynamic_lookup",
            ];
            break;
        case "linux":
            libName = "libNodeSwiftHost.so";
            ldflags = [
                "-Xlinker", "-undefined",
            ];
            break;
        case "win32":
            libName = "NodeSwiftHost.dll";
            ldflags = [
                "-Xlinker", await getWinLib(),
                "-Xlinker", "delayimp.lib",
                "-Xlinker", `/DELAYLOAD:${winHost}`,
            ];
            break;
        default:
            throw new Error(
                `The platform ${process.platform} is currently unsupported by node-swift.`
            );
    }

    // the NodeSwiftHost package acts as a "host" which uses the user's
    // package as a dependency (passed via env vars). This allows us to
    // move any flags and boilerplate that we need into the host package,
    // keeping the user's package simple.
    // TODO: Maybe simplify this by making NodeAPI a dynamic target, which
    // can serve as where we put the flags?
    const result = spawnSync(
        "swift",
        [
            "build",
            "-c", mode,
            "--product", "NodeSwiftHost",
            "--build-path", buildDir,
            "--package-path", path.join(__dirname, "..", "NodeSwiftHost"),
            ...ldflags,
            ...allFlags,
        ],
        {
            stdio: "inherit",
            env: {
                "NODE_SWIFT_TARGET_PACKAGE": parsedPackage.name,
                "NODE_SWIFT_TARGET_PATH": packagePath,
                "NODE_SWIFT_TARGET_NAME": product,
                "NODE_SWIFT_HOST_BINARY": winHost,
                "NODE_SWIFT_TARGET_MAC_VERSION": macVersion,
                "NODE_SWIFT_BUILD_DYNAMIC": isDynamic ? "1" : "0",
                ...process.env,
            },
        }
    );
    if (result.status !== 0) {
        throw new Error(`swift build exited with status ${result.status}`);
    }

    const binaryPath = path.join(buildDir, mode, `${product}.node`);

    await rename(
        path.join(buildDir, mode, libName),
        binaryPath
    );

    await forceSymlink(
        path.join(mode, `${product}.node`),
        path.join(buildDir, `${product}.node`)
    );

    return binaryPath;
}
