import {
  initRepo,
  getAllRepoStatuses,
  loadConfig,
  resolveRepoPath,
} from "./artifact-repos.js";
import type { ArtifactRepoConfig } from "./types.js";

const [command, ...args] = process.argv.slice(2);

async function run() {
  switch (command) {
    case "init-repo":
      await handleInitRepo(args);
      break;
    case "list-repos":
      await handleListRepos();
      break;
    case "validate-repos":
      await handleValidateRepos();
      break;
    default:
      console.error(
        `Usage: cli.ts <init-repo|list-repos|validate-repos> [args]`,
      );
      console.error(`\nCommands:`);
      console.error(
        `  init-repo <name> <path> <description> [remote]   Create and register an artifact repo`,
      );
      console.error(
        `  list-repos                                        List all configured artifact repos`,
      );
      console.error(
        `  validate-repos                                    Check that all repos exist and are valid`,
      );
      process.exit(1);
  }
}

async function handleInitRepo(args: string[]) {
  const [name, path, description, remote] = args;
  if (!name || !path || !description) {
    console.error("Usage: init-repo <name> <path> <description> [remote]");
    process.exit(1);
  }

  const config: ArtifactRepoConfig = { path, description };
  if (remote) config.remote = remote;

  const resolvedPath = await initRepo(name, config);
  console.log(`Initialized artifact repo "${name}" at ${resolvedPath}`);
}

async function handleListRepos() {
  const config = await loadConfig();
  const names = Object.keys(config.artifacts);

  if (names.length === 0) {
    console.log("No artifact repos configured.");
    console.log("See config/repos.example.json for an example configuration.");
    return;
  }

  console.log("Configured artifact repos:\n");
  for (const [name, repo] of Object.entries(config.artifacts)) {
    console.log(`  ${name}`);
    console.log(`    path:        ${resolveRepoPath(repo.path)}`);
    console.log(`    description: ${repo.description}`);
    if (repo.remote) console.log(`    remote:      ${repo.remote}`);
    if (repo.filePatterns)
      console.log(`    patterns:    ${repo.filePatterns.join(", ")}`);
    console.log();
  }
}

async function handleValidateRepos() {
  const statuses = await getAllRepoStatuses();

  if (statuses.length === 0) {
    console.log("No artifact repos configured.");
    return;
  }

  let allValid = true;
  for (const status of statuses) {
    const icon = status.exists && status.isGitRepo ? "ok" : "MISSING";
    console.log(`[${icon}] ${status.name}`);
    console.log(`       path: ${status.resolvedPath}`);

    if (!status.exists) {
      console.log(`       ERROR: directory does not exist`);
      allValid = false;
    } else if (!status.isGitRepo) {
      console.log(`       ERROR: exists but is not a git repository`);
      allValid = false;
    } else {
      console.log(`       branch: ${status.currentBranch}`);
      if (status.hasUncommittedChanges) {
        console.log(`       WARNING: has uncommitted changes`);
      }
    }
    console.log();
  }

  if (!allValid) {
    console.error("Some artifact repos are missing or invalid.");
    process.exit(1);
  }
  console.log("All artifact repos are valid.");
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
