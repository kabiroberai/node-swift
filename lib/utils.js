const { promises: { symlink, unlink }, existsSync } = require('fs');

async function forceSymlink(target, path) {
    if (existsSync(path)) await unlink(path);
    await symlink(target, path);
}

module.exports = { forceSymlink };
