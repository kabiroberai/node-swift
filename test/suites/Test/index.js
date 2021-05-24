const assert = require("assert");

const test = require("./build/Test.node");
const file = new test.File("test.txt");

const toAdd = "hello, world!\n"
file.contents = toAdd;
assert(file.contents.endsWith(toAdd));
file.unlink();
