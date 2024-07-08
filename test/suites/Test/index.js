const assert = require("assert");

const { File, SomeIterable } = require("../../.build/Test.node");

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

assert.strictEqual(file.reply("hi"), "You said hi");
assert.strictEqual(file.reply(null), "You said nothing");
assert.strictEqual(file.reply(undefined), "You said nothing");

const iterable = new SomeIterable()
const expected = ["one", "two", "three"]
assert.deepStrictEqual(Array.from(iterable), expected)
assert.deepStrictEqual([...iterable], expected)
let index = 0
for (const item of iterable) {
    assert.strictEqual(item, expected[index])
    index++
}