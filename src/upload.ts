import fs from "node:fs";
import path from "node:path";
import { bold, cyan, green, red, yellow } from "./colors.ts";
import type { ChunkReviewResult, RemoteManifestEntry, UploadOptions } from "./types.ts";
import { REJECT_FILE, REMOTE_MANIFEST_CACHE_FILE, REMOTE_MANIFEST_FILE } from "./types.ts";
import { runCommandPassthrough } from "./process.ts";
import { loadReviewFile } from "./review-state.ts";
import { downloadRemoteManifest, loadLocalManifest, readWorkspaceConfig, workspacePath } from "./workspace.ts";

function loadRejectSet(workspace: string): Set<string> {
  const file = workspacePath(workspace, REJECT_FILE);
  if (!fs.existsSync(file)) return new Set();
  return new Set(fs.readFileSync(file, "utf-8").split("\n").map((line) => line.trim()).filter(Boolean));
}

export async function runUpload(options: UploadOptions): Promise<void> {
  const config = readWorkspaceConfig(options.workspace);
  const repo = config.repo;

  const localManifest = loadLocalManifest(workspacePath(options.workspace, "manifest.local.jsonl"));
  if (localManifest.size === 0) {
    console.log(`No local manifest entries found in ${workspacePath(options.workspace, "manifest.local.jsonl")}`);
    return;
  }

  const rejectedByUser = loadRejectSet(options.workspace);
  const entries = [...localManifest.values()].sort((a, b) => a.file.localeCompare(b.file));
  let approved = 0;
  let rejected = 0;
  let rejectedManual = 0;
  let noReview = 0;
  let missingLocal = 0;
  let unchanged = 0;

  const remoteManifestPath = workspacePath(options.workspace, REMOTE_MANIFEST_CACHE_FILE);
  const remoteManifest = await downloadRemoteManifest(repo, remoteManifestPath);

  for (const entry of entries) {
    const reviewFile = loadReviewFile(workspacePath(options.workspace, "review", `${entry.file}.review.json`));
    const localFile = workspacePath(options.workspace, "redacted", entry.file);

    if (rejectedByUser.has(entry.file)) {
      rejectedManual++;
      continue;
    }

    if (!fs.existsSync(localFile)) {
      missingLocal++;
      continue;
    }
    if (!reviewFile) {
      noReview++;
      continue;
    }
    if (!isUploadApproved(reviewFile.aggregate)) {
      rejected++;
      continue;
    }

    const remoteEntry = remoteManifest.get(entry.file);
    if (remoteEntry?.redacted_hash === entry.redacted_hash) {
      unchanged++;
      continue;
    }

    approved++;
  }

  console.log(`${bold("Total sessions:")} ${cyan(String(entries.length))}`);
  console.log(`${bold("Approved by review:")} ${green(String(approved))}`);
  console.log(`${bold("Rejected by review:")} ${yellow(String(rejected))}`);
  console.log(`${bold("Rejected manually:")} ${yellow(String(rejectedManual))}`);
  console.log(`${bold("No review data:")} ${noReview > 0 ? red(String(noReview)) : String(noReview)}`);
  console.log(`${bold("Already uploaded (unchanged):")} ${unchanged}`);
  console.log(`${bold("Missing local redacted file:")} ${missingLocal}`);

  if (noReview > 0) {
    console.log(`\n${red(`Refusing to upload: ${noReview} session(s) have no review data. Run review first.`)}`);
    return;
  }
  if (options.dryRun) {
    console.log(`\n${yellow("Dry run, not uploading.")}`);
    return;
  }
  if (approved === 0) {
    console.log(`\n${yellow("Nothing to upload.")}`);
    return;
  }

  const uploadDir = workspacePath(options.workspace, "_upload_staging");
  fs.rmSync(uploadDir, { recursive: true, force: true });
  fs.mkdirSync(uploadDir, { recursive: true });

  const updatedManifest = new Map(remoteManifest);
  let staged = 0;

  for (const entry of entries) {
    const reviewFile = loadReviewFile(workspacePath(options.workspace, "review", `${entry.file}.review.json`));
    if (rejectedByUser.has(entry.file)) continue;
    if (!reviewFile || !isUploadApproved(reviewFile.aggregate)) continue;

    const remoteEntry = remoteManifest.get(entry.file);
    if (remoteEntry?.redacted_hash === entry.redacted_hash) continue;

    const localFile = workspacePath(options.workspace, "redacted", entry.file);
    if (!fs.existsSync(localFile)) continue;

    fs.copyFileSync(localFile, path.join(uploadDir, entry.file));
    updatedManifest.set(entry.file, {
      file: entry.file,
      source_hash: entry.source_hash,
      redacted_hash: entry.redacted_hash,
    });
    staged++;
  }

  const manifestContents = [...updatedManifest.values()]
    .sort((a, b) => a.file.localeCompare(b.file))
    .map((entry) => JSON.stringify(entry))
    .join("\n");
  fs.writeFileSync(path.join(uploadDir, REMOTE_MANIFEST_FILE), manifestContents.length > 0 ? `${manifestContents}\n` : "");

  console.log(`${bold("Staged for upload:")} ${cyan(String(staged))}`);
  console.log(green("Uploading..."));

  await uploadFolder(repo, uploadDir);

  fs.copyFileSync(path.join(uploadDir, REMOTE_MANIFEST_FILE), workspacePath(options.workspace, REMOTE_MANIFEST_FILE));
  fs.rmSync(uploadDir, { recursive: true, force: true });

  console.log(`${bold("Uploaded:")} ${green(String(staged))}`);
  console.log(`${bold("Updated remote manifest:")} ${REMOTE_MANIFEST_FILE}`);
}

function isUploadApproved(result: ChunkReviewResult): boolean {
  if (result.shareable !== "yes") return false;
  if (result.missed_sensitive_data !== "no") return false;
  if (result.about_project === "no") return false;
  return true;
}

async function uploadFolder(repo: string, localDir: string): Promise<void> {
  const code = await runCommandPassthrough("huggingface-cli", [
    "upload",
    repo,
    localDir,
    ".",
    "--repo-type",
    "dataset",
    "--commit-message",
    `pi-share-hf upload ${new Date().toISOString()}`,
  ]);
  if (code !== 0) {
    throw new Error(`Upload failed with exit code ${code}`);
  }
}
