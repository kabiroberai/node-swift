const assert = require("assert");

const { File } = require("../../build/Test.node");
const file = new File("test.txt");

let err = "";
try {
    file.contents
} catch (e) {
    err = `${e}`;
}
assert(err.includes('NSPOSIXErrorDomain'))

const toAdd = "hello, world!\n"
file.contents = Buffer.from(toAdd);
assert(file.contents.toString().endsWith(toAdd));
file.unlink();
