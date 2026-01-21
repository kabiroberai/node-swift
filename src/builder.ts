import { rm, rename, realpath } from "fs/promises";
import { spawn, spawnSync } from "child_process";
import { forceSymlink } from "./utils";
import path from "path";
import { isDeepStrictEqual } from "util";

const defaultBuildPath = path.join(process.cwd(), ".build");

// the name of the binary that the DLL loader *expects* to find
// (probably doesn't need to be changed)
const winHost = "node.exe";

export type BuildMode = "release" | "debug";

export type ConfigFlags = string | string[];

export interface SwiftPMBuilder {
    type?: "swiftpm"
    // flags passed directly to `swift build`
    settings?: ConfigFlags
    // --triple flag
    // warning: cross-compilation triples break macros as of Swift 5.9
    triple?: string
}

export interface XcodeBuilder {
    type: "xcode"
    // flags passed directly to `xcodebuild`
    settings?: ConfigFlags
    // -destination parameters
    destinations?: string[]
}

export type Builder = SwiftPMBuilder | XcodeBuilder;

export interface Config {
    buildPath?: string
    packagePath?: string
    product?: string

    napi?: number | "experimental"

    static?: boolean

    cFlags?: ConfigFlags
    swiftFlags?: ConfigFlags
    cxxFlags?: ConfigFlags
    linkerFlags?: ConfigFlags

    // flags passed to `swift package dump-package`
    dumpFlags?: ConfigFlags

    builder?: Builder | Builder["type"]
}

export async function clean(config: Config = {}) {
    await rm(
        config.buildPath || defaultBuildPath, 
        { recursive: true, force: true }
    );
}

async function getWinLib(): Promise<string> {
    let filename;
    switch (process.arch) {
        case "x64":
            filename = "node-win32-x64.lib";
            break;
        case "arm64":
            filename = "node-win32-arm64.lib";
            break;
        default:
            throw new Error(
                `The arch ${process.arch} is currently unsupported by node-swift on Windows.`
            );
    }
    return path.join(__dirname, "..", "vendored", "node", "lib", filename);
}

function getFlags<C>(config: C, name: keyof C & string): string[] {
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
    let dumpFlags = getFlags(config, "dumpFlags");
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

    const buildDir = config.buildPath || defaultBuildPath;

    let napi = config.napi;

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

    const nonSPMFlags = [
        ...cFlags.flatMap(f => ["-Xcc", f]),
        ...swiftFlags.flatMap(f => ["-Xswiftc", f]),
        ...cxxFlags.flatMap(f => ["-Xcxx", f]),
        ...linkerFlags.flatMap(f => ["-Xlinker", f]),
    ];

    process.stdout.write("[1/2] Initializing...");

    const dump = spawnSync(
        "swift",
        [
            "package",
            "dump-package",
            "--package-path", packagePath,
            ...dumpFlags,
            ...nonSPMFlags,
        ],
        { stdio: ["inherit", "pipe", "inherit"] }
    );
    if (dump.status !== 0) {
        throw new Error(`swift package dump-package exited with status ${dump.status}`);
    }
    const parsedPackage = JSON.parse(dump.stdout.toString());
    const products = parsedPackage.products as any[];
    let dylib;
    if (typeof config.product === "undefined") {
        const dylibs = products.filter(p => isDeepStrictEqual(p.type, { library: ["dynamic"] }));
        if (dylibs.length === 0) {
            throw new Error("No .dynamic products found in Swift Package");
        } else if (dylibs.length === 1) {
            dylib = dylibs[0];
        } else {
            throw new Error(
                "Found more than 1 dynamic library in the Swift Package. Consider " +
                "specifying which product should be built via the swift.product " +
                "field in package.json."
            );
        }
    } else if (typeof config.product === "string") {
        dylib = products.find(p => p.name === config.product);
        if (!dylib) {
            throw new Error(`Could not find a product named '${config.product}'`);
        }
        if (!isDeepStrictEqual(dylib.type, { library: ["dynamic"] })) {
            throw new Error(`Product '${config.product}' must be a .dynamic library`);
        }
    } else {
        throw new Error("The config product field should be of type string, if present");
    }
    const product: string = dylib.name;

    const targetNames = new Set(dylib.targets as string[]);
    const hasSupportLib = !!parsedPackage.targets.find((t: any) => (
        targetNames.has(t.name) &&
            t.dependencies?.find((d: any) => isDeepStrictEqual(
                d?.product?.slice(0, 2), ["NodeModuleSupport", "node-swift"]
            ))
    ));
    if (!hasSupportLib) throw new Error(`Product '${product}' must have '.product(name: "NodeModuleSupport", package: "node-swift")' as a dependency`);

    let libName;
    let ldflags;
    switch (process.platform) {
        case "darwin":
            libName = `lib${product}.dylib`;
            ldflags = [
                "-Xlinker", "-undefined",
                "-Xlinker", "dynamic_lookup",
            ];
            break;
        case "linux":
            libName = `lib${product}.so`;
            ldflags = [
                "-Xlinker", "-undefined",
            ];
            break;
        case "win32":
            libName = `${product}.dll`;
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

    process.stdout.write("\r[2/2] Initializing...");
    console.log();

    const binaryDir = path.join(buildDir, mode);
    const binaryPath = path.join(binaryDir, `${product}.node`);
    if (config.builder === "xcode" || (typeof config.builder === "object" && config.builder.type === "xcode")) {
        const xcode = typeof config.builder === "object" ? config.builder : ({ type: "xcode" } as XcodeBuilder);
        const settings = getFlags(xcode, "settings");
        const destinations = xcode.destinations || ["generic/platform=macOS"];
        const derivedDataPath = path.join(buildDir, "DerivedData");

        if (isDynamic) {
            // add the framework's parent directory to the rpath
            ldflags.push("-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../..");
        }

        const originalBinary = path.join(binaryDir, `${product}.framework`, "Versions", "A", product);
        await rm(originalBinary, { force: true });

        const result = spawnSync(
            "xcodebuild",
            [
                "install",
                "-configuration", mode === "debug" ? "Debug" : "Release",
                "-derivedDataPath", derivedDataPath,
                "-workspace", path.join(packagePath, ".swiftpm", "xcode", "package.xcworkspace"),
                "-scheme", product,
                ...destinations.flatMap(d => ["-destination", d]),
                "INSTALL_PATH=/",
                `DSTROOT=${binaryDir}`, // install prefix
                // TODO: escape args
                `OTHER_LDFLAGS=$(inherited) ${[...linkerFlags, ...ldflags].join(" ")}`,
                `OTHER_CFLAGS=$(inherited) ${cFlags.join(" ")}`,
                `OTHER_SWIFT_FLAGS=$(inherited) ${swiftFlags.join(" ")}`,
                `OTHER_CPLUSPLUSFLAGS=$(inherited) ${cxxFlags.join(" ")}`,
                ...settings,
            ],
            {
                stdio: "inherit",
                env: {
                    ...process.env,
                    "NODE_SWIFT_BUILD_DYNAMIC": isDynamic ? "1" : "0",
                },
            }
        );

        if (result.status !== 0) {
            throw new Error(`xcodebuild exited with status ${result.status}`);
        }

        // the exec realpath must end with .node for it to be considered a native module.
        await Promise.all([
            rename(
                originalBinary,
                path.join(binaryDir, `${product}.framework`, "Versions", "A", `${product}.node`)
            ),
            rm(path.join(binaryDir, `${product}.framework`, `${product}`), { force: true }),
            forceSymlink(
                path.join("Versions", "Current", `${product}.node`),
                path.join(binaryDir, `${product}.framework`, `${product}.node`)
            ),
            forceSymlink(
                path.join(`${product}.framework`, `${product}.node`),
                binaryPath
            ),
            spawn(
                "/usr/libexec/PlistBuddy",
                [
                    "-c",
                    `Set :CFBundleExecutable ${product}.node`,
                    path.join(binaryDir, `${product}.framework`, "Resources", "Info.plist"),
                ],
                {
                    stdio: "inherit",
                }
            ),
        ]);
    } else {
        const swiftPM = typeof config.builder === "object" ? config.builder : {};
        const swiftPMFlags = getFlags(swiftPM, "settings");
        if (typeof swiftPM.triple === "string") {
            swiftPMFlags.push("--triple", swiftPM.triple);
        }
        const result = spawnSync(
            "swift",
            [
                "build",
                "-c", mode,
                "--product", product,
                "--build-path", buildDir,
                "--package-path", packagePath,
                ...ldflags,
                ...swiftPMFlags,
                ...nonSPMFlags,
            ],
            {
                stdio: "inherit",
                env: {
                    ...process.env,
                    "NODE_SWIFT_BUILD_DYNAMIC": isDynamic ? "1" : "0",
                },
            }
        );

        if (result.status !== 0) {
            throw new Error(`swift build exited with status ${result.status}`);
        }

        await rename(
            path.join(buildDir, mode, libName),
            binaryPath
        );
    
        if (process.platform === "darwin") {
            spawnSync(
                "codesign",
                ["-fs", "-", binaryPath],
                { stdio: "inherit" }
            );
        }
    }

    await forceSymlink(
        path.join(mode, `${product}.node`),
        path.join(buildDir, `${product}.node`)
    );

    return binaryPath;
}
