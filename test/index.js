const fs = require("fs").promises;
const builder = require("../lib/builder");
const { spawnSync } = require("child_process");

process.chdir(__dirname);

function usage() {
    console.log("Usage: test [all | suite <suite name> | _suite <suite name>]");
    console.log("     all: clean & run all tests");
    console.log("   suite: clean & run suite with given name");
    console.log("  _suite: run suite with given name without cleaning");
    process.exit(1);
}

async function runSuite(suite, isChild) {
    console.log(`Running suite '${suite}'`);
    await builder.build("debug", { product: suite });
    require(`./suites/${suite}`);
}

async function runAll() {
    const suites = (await fs.readdir("suites")).filter(f => !f.startsWith("."));
    let hasFailure = false;
    for (const suite of suites) {
        // invoke isChild processes because that way lifetime stuff
        // is handled on a per-test basis
        const status = spawnSync(
            "node", [__filename, "_suite", suite],
            { stdio: [process.stdin, process.stdout, process.stderr] }
        ).status;
        if (status === 0) {
            console.log(`Suite '${suite}' passed!`);
        } else {
            hasFailure = true;
            console.log(`Suite '${suite}' failed: exit code ${status}`);
        }
    }
    if (!hasFailure) console.log("All tests passed!");
}

(async () => {
    const command = process.argv[2] || "all";
    let isChild = false;
    switch (command) {
        case "all":
            if (process.argv.length > 3) usage();
            await builder.clean();
            await runAll();
            break;
        case "_suite":
            isChild = true;
            // fallthrough
        case "suite":
            if (process.argv.length !== 4) usage();
            const suite = process.argv[3];
            if (!isChild) await builder.clean();
            await runSuite(suite, isChild);
            break;
        default:
            usage();
    }
})();
