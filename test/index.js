const fs = require("fs").promises;
const build = require("../lib/build");
const { spawnSync } = require("child_process");
const { forceSymlink } = require("../lib/utils");

process.chdir(__dirname);

function usage() {
    console.log("Usage: test [all|suite <suite name>]");
    process.exit(1);
}

async function runSuite(suite, child) {
    console.log(`Running suite '${suite}'`);
    await build("debug", suite);
    await forceSymlink("../../.build", `./suites/${suite}/.build`);
    require(`./suites/${suite}`);
}

async function runAll() {
    const suites = (await fs.readdir("suites")).filter(f => !f.startsWith("."));
    for (const suite of suites) {
        // invoke child processes because that way lifetime stuff
        // is handled on a per-test basis
        const status = spawnSync(
            "node", [__filename, "_suite", suite],
            { stdio: [process.stdin, process.stdout, process.stderr] }
        ).status;
        if (status === 0) {
            console.log(`Suite '${suite}' passed!`);
        } else {
            console.log(`Suite '${suite}' failed: exit code ${status}`);
        }
    }
    console.log("All tests passed!");
}

(async () => {
    const command = process.argv[2] || "all";
    let child = false;
    switch (command) {
        case "all":
            if (process.argv.length > 3) usage();
            await runAll();
            break;
        case "_suite":
            child = true;
            // fallthrough
        case "suite":
            if (process.argv.length !== 4) usage();
            const suite = process.argv[3];
            await runSuite(suite, child);
            break;
        default:
            usage();
    }
})();
