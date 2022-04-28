# NodeSwift

Bridge Node.js and Swift code.

## What is it?

NodeSwift allows you to write Swift code that talks to Node.js libraries, and vice versa. This enables possibilities such as

- Using native macOS APIs and SPM in an Electron app.
- Interacting with the vast array of NPM APIs from a Swift program (e.g. a macOS app, iOS app, or a Vapor server).
- Speeding up your JS code by writing performance critical bits in Swift.

## Example

**MyModule.swift**
```swift
import NodeAPI

@main struct MyModule: NodeModule {
    let exports: NodeValueConvertible

    init() throws {
        exports = try [
            "nums": [Double.pi.rounded(.down), Double.pi.rounded(.up)],
            "str": String(repeating: "NodeSwift! ", count: 3),
            "add": NodeFunction { (a: Double, b: Double) in
                "\(a) + \(b) = \(a + b)"
            },
        ]
    }
}
```

**index.js**
```js
const { nums, str, add } = require("./build/MyModule.node");
console.log(nums); // [ 3, 4 ]
console.log(str); // NodeSwift! NodeSwift! NodeSwift!
console.log(add(5, 10)); // 5.0 + 10.0 = 15.0
```

## Features

- **Safe**: NodeSwift makes use of Swift's memory safety and automatic reference counting. This means that, unlike with the C-based Node-API, you never have to think about memory management while writing NodeSwift modules.
- **Simple**: With progressive disclosure, you can decide whether you want to use simpler or more advanced NodeSwift APIs to suit whatever your needs might be.
- **Idiomatic**: NodeSwift's APIs feel right at home in idiomatic Swift code. For example, to make a Swift class usable from Node.js you literally declare a `class` in Swift that conforms to `NodeClass`. We also use several Swift features like Dynamic Member Lookup that are designed precisely to make this sort of interop easy.
- **Versatile**: You have access to the full set of Node.js APIs in Swift, from JavaScript object manipulation to event loop scheduling.
- **Cross-platform**: NodeSwift works not only on macOS, but also on Linux, Windows, and even iOS!

## How?

A NodeSwift module consists of an [SPM](https://swift.org/package-manager/) package and [NPM](https://www.npmjs.com) package in the same folder, both of which express NodeSwift as a dependency.

The Swift package is exposed to JavaScript as a native Node.js module, which can be `require`'d by the JS code. The two sides communicate via [Node-API](https://nodejs.org/api/n-api.html), which is wrapped by the `NodeAPI` module on the Swift side.

## Get started

For details, see the example in [/example](/example).

<!-- For details, refer to the documentation and examples:

- [example](/example)
- node-vision
- swift-puppeteer
- fast-js -->
<!-- TODO: More ideas -->

## Alternatives

**WebAssembly**

While WebAssembly is great for performance, it still runs in a virtual machine, which means it can't access native Darwin/Win32/GNU+Linux APIs. NodeSwift runs your Swift code on the bare metal, which should be even faster than WASM, in addition to unlocking access to the operating system's native APIs.

On the other hand, if you want to run Swift code in the browser, WebAssembly might be the right choice since NodeSwift requires a Node.js runtime.

**Other NAPI wrappers**

NAPI, NAN, Neon etc. are all other options for building native Node.js modules, each with its own strengths. For example, NAPI is written in C and thus affords great portability at the cost of memory unsafety. NodeSwift is a great option if you want to enhance your JS tool on Apple platforms, if you want to bring Node.js code into your existing Swift program, or if you simply prefer Swift to C/C++/Rust/etc.
