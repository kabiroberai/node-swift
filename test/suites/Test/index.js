const assert = require("assert");

const { File } = require("../../build/Test.node");

assert.strictEqual(File.default().filename, "default.txt")

const file = new File("test.txt");
assert.strictEqual(file.filename, "test.txt")

let err = "";
try {
    file.contents
} catch (e) {
    err = `${e}`;
}
assert(err.includes("NSPOSIXErrorDomain"))

const toAdd = "hello, world!\n"
file.contents = Buffer.from(toAdd);
assert(file.contents.toString().endsWith(toAdd));
file.unlink();

assert(file.reply("hi") == "You said hi");
assert(file.reply(null) == "You said nothing");
