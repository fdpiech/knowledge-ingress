/** Configuration for a single artifact repository */
export interface ArtifactRepoConfig {
  /** Filesystem path to the repo (relative to this project root or absolute) */
  path: string;
  /** Git remote URL */
  remote?: string;
  /** Human-readable description of what this repo contains */
  description: string;
  /** Glob patterns for files this repo manages */
  filePatterns?: string[];
}

/** Top-level repos configuration */
export interface ReposConfig {
  artifacts: Record<string, ArtifactRepoConfig>;
}

/** Status of an artifact repository on disk */
export interface RepoStatus {
  name: string;
  config: ArtifactRepoConfig;
  exists: boolean;
  isGitRepo: boolean;
  resolvedPath: string;
  currentBranch?: string;
  hasUncommittedChanges?: boolean;
}
