import { execFile } from "node:child_process";
import { readFile, writeFile, access, mkdir } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { promisify } from "node:util";
import type { ArtifactRepoConfig, ReposConfig, RepoStatus } from "./types.js";

const exec = promisify(execFile);

/** Resolve the config file path relative to project root */
function configPath(): string {
  return resolve(import.meta.dirname, "..", "config", "repos.json");
}

/** Load the repos configuration */
export async function loadConfig(): Promise<ReposConfig> {
  const raw = await readFile(configPath(), "utf-8");
  return JSON.parse(raw) as ReposConfig;
}

/** Save the repos configuration */
export async function saveConfig(config: ReposConfig): Promise<void> {
  const path = configPath();
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, JSON.stringify(config, null, 2) + "\n", "utf-8");
}

/** Resolve a repo path relative to the project root */
export function resolveRepoPath(repoPath: string): string {
  const projectRoot = resolve(import.meta.dirname, "..");
  return resolve(projectRoot, repoPath);
}

/** Run a git command in a given directory */
async function git(
  cwd: string,
  ...args: string[]
): Promise<{ stdout: string; stderr: string }> {
  return exec("git", args, { cwd });
}

/** Check the status of a single artifact repo */
export async function getRepoStatus(
  name: string,
  config: ArtifactRepoConfig,
): Promise<RepoStatus> {
  const resolvedPath = resolveRepoPath(config.path);

  let exists = false;
  try {
    await access(resolvedPath);
    exists = true;
  } catch {
    // directory doesn't exist
  }

  if (!exists) {
    return { name, config, exists: false, isGitRepo: false, resolvedPath };
  }

  let isGitRepo = false;
  let currentBranch: string | undefined;
  let hasUncommittedChanges: boolean | undefined;

  try {
    await git(resolvedPath, "rev-parse", "--git-dir");
    isGitRepo = true;

    const branchResult = await git(
      resolvedPath,
      "rev-parse",
      "--abbrev-ref",
      "HEAD",
    );
    currentBranch = branchResult.stdout.trim();

    const statusResult = await git(resolvedPath, "status", "--porcelain");
    hasUncommittedChanges = statusResult.stdout.trim().length > 0;
  } catch {
    // not a git repo or git not available
  }

  return {
    name,
    config,
    exists,
    isGitRepo,
    resolvedPath,
    currentBranch,
    hasUncommittedChanges,
  };
}

/** Get status for all configured artifact repos */
export async function getAllRepoStatuses(): Promise<RepoStatus[]> {
  const config = await loadConfig();
  const entries = Object.entries(config.artifacts);
  return Promise.all(
    entries.map(([name, repoConfig]) => getRepoStatus(name, repoConfig)),
  );
}

/** Register a new artifact repo in the configuration */
export async function registerRepo(
  name: string,
  repoConfig: ArtifactRepoConfig,
): Promise<void> {
  const config = await loadConfig();
  if (config.artifacts[name]) {
    throw new Error(`Artifact repo "${name}" is already registered`);
  }
  config.artifacts[name] = repoConfig;
  await saveConfig(config);
}

/** Initialize a new artifact repo on disk (create dir + git init) */
export async function initRepo(
  name: string,
  repoConfig: ArtifactRepoConfig,
): Promise<string> {
  const resolvedPath = resolveRepoPath(repoConfig.path);

  await mkdir(resolvedPath, { recursive: true });
  await git(resolvedPath, "init");

  // Write a minimal README
  const readme = `# ${name}\n\n${repoConfig.description}\n\nThis is an artifact repository managed by [knowledge-ingress](../knowledge-ingress).\n`;
  await writeFile(resolve(resolvedPath, "README.md"), readme, "utf-8");

  // Write a .gitignore
  const gitignore = `node_modules/\n.DS_Store\n*.tmp\n`;
  await writeFile(resolve(resolvedPath, ".gitignore"), gitignore, "utf-8");

  await git(resolvedPath, "add", ".");
  await git(resolvedPath, "commit", "-m", "Initial commit");

  // Set remote if provided
  if (repoConfig.remote) {
    await git(resolvedPath, "remote", "add", "origin", repoConfig.remote);
  }

  // Register in config
  await registerRepo(name, repoConfig);

  return resolvedPath;
}

/** Write content to a file in an artifact repo */
export async function writeArtifact(
  repoName: string,
  filePath: string,
  content: string,
): Promise<string> {
  const config = await loadConfig();
  const repoConfig = config.artifacts[repoName];
  if (!repoConfig) {
    throw new Error(
      `Artifact repo "${repoName}" not found in configuration`,
    );
  }

  const resolvedBase = resolveRepoPath(repoConfig.path);
  const fullPath = resolve(resolvedBase, filePath);

  // Ensure the file stays within the repo directory
  if (!fullPath.startsWith(resolvedBase)) {
    throw new Error("File path escapes the artifact repo directory");
  }

  await mkdir(dirname(fullPath), { recursive: true });
  await writeFile(fullPath, content, "utf-8");

  return fullPath;
}

/** Read content from a file in an artifact repo */
export async function readArtifact(
  repoName: string,
  filePath: string,
): Promise<string> {
  const config = await loadConfig();
  const repoConfig = config.artifacts[repoName];
  if (!repoConfig) {
    throw new Error(
      `Artifact repo "${repoName}" not found in configuration`,
    );
  }

  const resolvedBase = resolveRepoPath(repoConfig.path);
  const fullPath = resolve(resolvedBase, filePath);

  if (!fullPath.startsWith(resolvedBase)) {
    throw new Error("File path escapes the artifact repo directory");
  }

  return readFile(fullPath, "utf-8");
}
