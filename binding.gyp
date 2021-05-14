{
    "targets": [
        {
            "target_name": "NativeStuff",
            # TODO: Pull this stuff out into a gypi file?
            "libraries": ["<!@(node spmtool.js ldflags <(_target_name))"],
            "actions": [
                {
                    "action_name": "Build Swift Package",
                    "inputs": ["<!@(node spmtool.js inputs)"],
                    "outputs": ["<!(node spmtool.js output <(_target_name))"],
                    "action": [
                        "node", "spmtool.js", "build",
                        "<(CONFIGURATION_NAME)", "<(_target_name)"
                    ]
                }
            ]
        }
    ],
}
