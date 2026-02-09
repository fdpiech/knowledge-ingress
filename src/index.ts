export {
  loadConfig,
  saveConfig,
  resolveRepoPath,
  getRepoStatus,
  getAllRepoStatuses,
  registerRepo,
  initRepo,
  writeArtifact,
  readArtifact,
} from "./artifact-repos.js";

export type {
  ArtifactRepoConfig,
  ReposConfig,
  RepoStatus,
} from "./types.js";
