const { nums, str, add } = require("./build/module.node");
console.log(nums); // [ 3, 4 ]
console.log(str); // NodeSwift! NodeSwift! NodeSwift!
add(5, 10).then(console.log); // 5.0 + 10.0 = 15.0
