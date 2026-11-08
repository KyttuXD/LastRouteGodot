// Server entry point. Load the deployment's backend/.env before
// importing modules that read process.env. A root .env remains a convenient
// local fallback, while real process environment variables always win.
import { loadEnvironmentFile } from "./backend/env_file.mjs";

await loadEnvironmentFile(new URL("./backend/.env", import.meta.url));
await loadEnvironmentFile(new URL("./.env", import.meta.url));

const [serverModule, releaseSyncModule, sourceWatchModule] = await Promise.all([
  import("./backend/server.mjs"),
  import("./backend/github_release_sync.mjs"),
  import("./backend/github_source_watch.mjs"),
]);
const { startLastRouteServerFromEnvironment } = serverModule;
const { githubReleaseSyncEnabled, syncGithubReleaseFromEnvironment } = releaseSyncModule;
const { checkGithubSourceFromEnvironment, githubSourceWatchEnabled } = sourceWatchModule;

let syncRunning = false;
async function syncUpdates() {
  if (syncRunning) return;
  syncRunning = true;
  try {
    await syncGithubReleaseFromEnvironment();
  } catch (error) {
    // A transient GitHub outage must not take accounts and room discovery down.
    // The backend will continue with the last fully verified local update set.
    console.error(`GitHub release sync failed: ${error.message}`);
  } finally {
    syncRunning = false;
  }
}

await syncUpdates();
const server = startLastRouteServerFromEnvironment();

if (githubReleaseSyncEnabled()) {
  const requestedSeconds = Number(process.env.LASTROUTE_UPDATE_POLL_SECONDS);
  // Release assets are the client's update source. Five-minute freshness made
  // an already-open game honestly report UP TO DATE after a new build was
  // published, then stay wrong until the next manual check/restart. A PAT gets
  // 5,000 GitHub API requests/hour; four lightweight checks/minute is well
  // inside that budget while keeping debug iteration responsive.
  const pollSeconds = Math.max(10, Number.isFinite(requestedSeconds) ? requestedSeconds : 15);
  const updateTimer = setInterval(syncUpdates, pollSeconds * 1000);
  updateTimer.unref();
  server.once("close", () => clearInterval(updateTimer));
  console.log(`GitHub release sync: every ${pollSeconds}s`);
}

if (githubSourceWatchEnabled()) {
  const requestedSeconds = Number(process.env.LASTROUTE_SOURCE_POLL_SECONDS);
  const pollSeconds = Math.max(15, Number.isFinite(requestedSeconds) ? requestedSeconds : 30);
  let sourceCheckRunning = false;
  let restartRequested = false;
  const checkSource = async () => {
    if (sourceCheckRunning || restartRequested) return;
    sourceCheckRunning = true;
    try {
      const result = await checkGithubSourceFromEnvironment();
      if (result.changed) {
        restartRequested = true;
        console.log(`GitHub source changed (${result.local.slice(0, 12)} -> ${result.remote.slice(0, 12)}); requesting hosting-panel restart`);
        server.close(() => process.exit(75));
        setTimeout(() => process.exit(75), 10_000).unref();
      }
    } catch (error) {
      console.error(`GitHub source check failed: ${error.message}`);
    } finally {
      sourceCheckRunning = false;
    }
  };
  const sourceTimer = setInterval(checkSource, pollSeconds * 1000);
  sourceTimer.unref();
  server.once("close", () => clearInterval(sourceTimer));
  console.log(`GitHub source restart watch: every ${pollSeconds}s`);
  checkSource();
}
