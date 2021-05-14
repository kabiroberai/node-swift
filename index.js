console.log("JS: startup");

const res = require("./build/Debug/NativeStuff.node");
console.log("JS: called require()");
console.log(`JS: exports = ${res}`);
console.log(res());

setTimeout(() => {
    console.log("JS: setTimeout() called back");
}, 1000);
