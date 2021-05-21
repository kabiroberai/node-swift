console.log("JS: startup");

const assert = require("assert");
const res = require("./.build/curr/Integration.node");
console.log("JS: called require()");
console.log(`JS: exports = ${res}`);
const r = res();
assert.strictEqual(r, 5);

setTimeout(() => {
    console.log("JS: setTimeout() called back");
}, 2000);
