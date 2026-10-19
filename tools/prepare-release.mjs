// Build an existing-server release bundle from the CURRENT WORKING TREE plus an existing Flutter Web build.
// The bundle contains source + web + upgrade-server.sh + DEPLOY.md + release.json only.
// Server secrets (.env), the database and the API image are never included: the server builds the image itself.
//
// Usage:
//   node tools/prepare-release.mjs --release-id=20261018-1500-db61017 --api-origin=https://47.116.63.161
//
// Output:
//   output/releases/<release-id>/                       unpacked release directory
//   output/releases/study-planner-<release-id>.tar.gz  upload bundle
//   output/releases/study-planner-<release-id>.tar.gz.sha256
import { cp, mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { basename, join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const options = Object.fromEntries(process.argv.slice(2).flatMap(argument => {
  if (!argument.startsWith("--")) return [];
  const index = argument.indexOf("=");
  return index === -1 ? [[argument.slice(2), "true"]] : [[argument.slice(2, index), argument.slice(index + 1)]];
}));

const apiOrigin = options["api-origin"];
if (!apiOrigin || !/^https?:\/\/[^/\s]+$/.test(apiOrigin)) {
  console.error("Missing or invalid --api-origin, for example --api-origin=https://47.116.63.161");
  process.exit(1);
}
const releaseId = options["release-id"];
if (!releaseId || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(releaseId)) {
  console.error("Missing or invalid --release-id (letters, digits, dot, underscore and dash only).");
  process.exit(1);
}

const outputRoot = join(root, "output", "releases");
const releaseDir = join(outputRoot, releaseId);
const templateDir = join(root, "tools", "server-release");
const webSource = join(root, "apps", "flutter_client", "build", "web");

const commit = execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
const dirty = execFileSync("git", ["status", "--porcelain"], { cwd: root, encoding: "utf8" }).trim().length > 0;

await stat(join(webSource, "index.html"));
await stat(join(webSource, "main.dart.js"));
const mainJs = await readFile(join(webSource, "main.dart.js"), "utf8");
if (!mainJs.includes(apiOrigin)) {
  throw new Error(`web/main.dart.js does not embed ${apiOrigin}; rebuild the Web client with --dart-define=API_BASE_URL=${apiOrigin}`);
}

await mkdir(outputRoot, { recursive: true });
// Release IDs are immutable. Never remove an existing release directory.
await mkdir(releaseDir);

const source = join(releaseDir, "source");
const inputs = [
  "package.json",
  "package-lock.json",
  "tsconfig.json",
  "apps/api/package.json",
  "apps/api/tsconfig.json",
  "apps/api/Dockerfile",
  "apps/api/docker-compose.server.yml",
  "apps/api/src",
  "apps/api/db",
  "packages/planner-engine/package.json",
];
for (const input of inputs) {
  const destination = join(source, input);
  await mkdir(resolve(destination, ".."), { recursive: true });
  await cp(join(root, input), destination, { recursive: true, errorOnExist: false });
}
await writeFile(
  join(source, ".dockerignore"),
  [".env", "**/.env", "**/.env.*", "**/node_modules", "**/build", "**/.dart_tool", ".git", ""].join("\n"),
);

const webOutput = join(releaseDir, "web");
await cp(webSource, webOutput, { recursive: true, errorOnExist: false });

const builtAt = new Date().toISOString();
const apiHost = new URL(apiOrigin).host;
const replacements = {
  __RELEASE_ID__: releaseId,
  __API_ORIGIN__: apiOrigin,
  __API_ORIGIN_HOST__: apiHost,
  __BASE_COMMIT__: commit,
  __BUILT_AT__: builtAt,
};
for (const name of ["DEPLOY.md", "upgrade-server.sh"]) {
  let text = await readFile(join(templateDir, name), "utf8");
  for (const [key, value] of Object.entries(replacements)) text = text.replaceAll(key, value);
  await writeFile(join(releaseDir, name), text);
}
await writeFile(
  join(releaseDir, "release.json"),
  `${JSON.stringify({
    release_id: releaseId,
    base_commit: commit,
    working_tree_dirty: dirty,
    api_origin: apiOrigin,
    web_build: `flutter build web --release --no-pub --no-web-resources-cdn --dart-define=API_BASE_URL=${apiOrigin}`,
    prepared_at: builtAt,
    note: "Release is built from the current working tree; base_commit identifies the committed revision.",
  }, null, 2)}\n`,
);

const bundle = join(outputRoot, `study-planner-${releaseId}.tar.gz`);
execFileSync("tar", ["-czf", bundle, "-C", releaseDir, "source", "web", "release.json", "upgrade-server.sh", "DEPLOY.md"], { cwd: root, stdio: "inherit" });
const hash = createHash("sha256").update(await readFile(bundle)).digest("hex");
await writeFile(`${bundle}.sha256`, `${hash}  ${basename(bundle)}\n`);

const size = (await stat(bundle)).size;
console.log("");
console.log(`Release:  ${releaseId}`);
console.log(`Origin:   ${apiOrigin}`);
console.log(`Commit:   ${commit}${dirty ? " (working tree has uncommitted changes)" : ""}`);
console.log(`Bundle:   ${bundle} (${(size / 1024 / 1024).toFixed(1)} MB)`);
console.log(`SHA256:   ${hash}`);
