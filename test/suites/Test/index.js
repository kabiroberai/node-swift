const assert = require("assert");

const test = require("../../build/Test.node");
const file = new test.File("test.txt");

const toAdd = "hello, world!\n"
file.contents = Buffer.from(toAdd);
assert(file.contents.toString().endsWith(toAdd));
file.unlink();
