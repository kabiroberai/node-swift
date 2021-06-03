const { promises: { symlink, unlink } } = require("fs");

async function forceSymlink(target, path) {
    try {
        await unlink(path);
    } catch (e) {}
    await symlink(target, path);
}

module.exports = { forceSymlink };
