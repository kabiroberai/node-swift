import { symlink, unlink } from "fs/promises";

async function forceSymlink(target: string, path: string) {
    try {
        await unlink(path);
    } catch {
        // symlink does not exist, no worries
    }
    await symlink(target, path);
}

export { forceSymlink };
