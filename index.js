// Pterodactyl-friendly entry point. The backend remains implemented as ES
// modules in server.mjs; package.json's "type": "module" lets a standard
// Node.js egg launch this file directly with `node index.js`.
import { startLastRouteServerFromEnvironment } from "./backend/server.mjs";
import {
  githubReleaseSyncEnabled,
  syncGithubReleaseFromEnvironment,
} from "./backend/github_release_sync.mjs";
import {
  checkGithubSourceFromEnvironment,
  githubSourceWatchEnabled,
} from "./backend/github_source_watch.mjs";

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
  const pollSeconds = Math.max(60, Number.isFinite(requestedSeconds) ? requestedSeconds : 300);
  const updateTimer = setInterval(syncUpdates, pollSeconds * 1000);
  updateTimer.unref();
  server.once("close", () => clearInterval(updateTimer));
  console.log(`GitHub release sync: every ${pollSeconds}s`);
}

if (githubSourceWatchEnabled()) {
  const requestedSeconds = Number(process.env.LASTROUTE_SOURCE_POLL_SECONDS);
  const pollSeconds = Math.max(60, Number.isFinite(requestedSeconds) ? requestedSeconds : 120);
  let sourceCheckRunning = false;
  let restartRequested = false;
  const checkSource = async () => {
    if (sourceCheckRunning || restartRequested) return;
    sourceCheckRunning = true;
    try {
      const result = await checkGithubSourceFromEnvironment();
      if (result.changed) {
        restartRequested = true;
        console.log(`GitHub source changed (${result.local.slice(0, 12)} -> ${result.remote.slice(0, 12)}); requesting Pterodactyl restart`);
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
