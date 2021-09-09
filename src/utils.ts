import { symlink, unlink } from "fs/promises";

async function forceSymlink(target: string, path: string) {
    try {
        await unlink(path);
    } catch (e) {}
    await symlink(target, path);
}

export { forceSymlink };
