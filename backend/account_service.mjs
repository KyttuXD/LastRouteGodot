import { randomBytes, scrypt, timingSafeEqual } from "node:crypto";
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

const USERNAME_PATTERN = /^[A-Z0-9_]{3,24}$/;
const RESERVED_USERNAME_PATTERN = /yttu/i;
const MIN_PASSWORD_LENGTH = 6;
const MAX_PASSWORD_LENGTH = 200;
const MAX_PROGRESS_BYTES = 32 * 1024;
const SCRYPT_KEY_LENGTH = 64;

function derive(password, salt) {
  return new Promise((resolve, reject) => {
    scrypt(String(password), salt, SCRYPT_KEY_LENGTH, (error, result) => {
      if (error) reject(error);
      else resolve(result);
    });
  });
}

async function passwordRecord(password) {
  const salt = randomBytes(16).toString("hex");
  return { salt, hash: (await derive(password, salt)).toString("hex") };
}

async function passwordMatches(password, salt, hash) {
  const expected = Buffer.from(String(hash || ""), "hex");
  const actual = await derive(password, String(salt || ""));
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

function usernameOf(value) {
  return String(value || "").trim().toUpperCase().slice(0, 24);
}

export function createAccountService({ storePath = null, logger = console, now = Date.now } = {}) {
  const accounts = new Map();
  const sessions = new Map();

  if (storePath) {
    try {
      const parsed = JSON.parse(readFileSync(storePath, "utf8"));
      for (const value of Array.isArray(parsed?.accounts) ? parsed.accounts : []) {
        const username = usernameOf(value?.username);
        if (USERNAME_PATTERN.test(username) && value?.salt && value?.hash) {
          accounts.set(username, { ...value, username });
        }
      }
    } catch (error) {
      if (error?.code !== "ENOENT") logger.warn?.(`Account store was not loaded: ${error?.message || error}`);
    }
  }

  function persist() {
    if (!storePath) return;
    try {
      mkdirSync(dirname(storePath), { recursive: true });
      const temporaryPath = `${storePath}.tmp`;
      writeFileSync(temporaryPath, JSON.stringify({ version: 1, accounts: [...accounts.values()] }));
      renameSync(temporaryPath, storePath);
    } catch (error) {
      logger.error?.(`Account store write failed: ${error?.message || error}`);
    }
  }

  function issueSession(username) {
    const token = randomBytes(24).toString("hex");
    sessions.set(token, username);
    return token;
  }

  function validPassword(password) {
    return typeof password === "string" && password.length >= MIN_PASSWORD_LENGTH && password.length <= MAX_PASSWORD_LENGTH;
  }

  async function register(body = {}, { allowDeveloperNames = false } = {}) {
    const username = usernameOf(body.username);
    if (!USERNAME_PATTERN.test(username)) {
      return [400, { ok: false, code: "INVALID_USERNAME", error: "Username must be 3-24 characters: letters, numbers, underscore" }];
    }
    if (RESERVED_USERNAME_PATTERN.test(username) && !allowDeveloperNames) {
      return [403, { ok: false, code: "RESERVED_USERNAME", error: "That username is reserved" }];
    }
    if (!validPassword(body.password)) {
      return [400, { ok: false, code: "WEAK_PASSWORD", error: "Password must be 6-200 characters" }];
    }
    if (accounts.has(username)) {
      return [409, { ok: false, code: "USERNAME_TAKEN", error: "That username is already taken" }];
    }
    const credentials = await passwordRecord(body.password);
    accounts.set(username, { username, ...credentials, progress: null, savedAt: 0 });
    persist();
    return [200, { ok: true, username, admin: RESERVED_USERNAME_PATTERN.test(username), sessionToken: issueSession(username) }];
  }

  async function login(body = {}) {
    const username = usernameOf(body.username);
    const account = accounts.get(username);
    const valid = account
      ? await passwordMatches(body.password, account.salt, account.hash)
      : (await derive(body.password, "last-route-decoy-salt"), false);
    if (!valid) return [401, { ok: false, code: "INVALID_CREDENTIALS", error: "Incorrect username or password" }];
    return [200, {
      ok: true,
      username,
      admin: RESERVED_USERNAME_PATTERN.test(username),
      sessionToken: issueSession(username),
      progress: account.progress,
      savedAt: account.savedAt,
    }];
  }

  function sessionUsername(token) {
    return sessions.get(String(token || "")) || null;
  }

  function save(body = {}) {
    const username = sessionUsername(body.sessionToken);
    if (!username) return [401, { ok: false, code: "NO_SESSION", error: "Sign in to save progress" }];
    let serialized;
    try {
      serialized = JSON.stringify(body.progress ?? null);
    } catch {
      return [400, { ok: false, code: "INVALID_PROGRESS", error: "Progress must be serializable" }];
    }
    if (Buffer.byteLength(serialized) > MAX_PROGRESS_BYTES) {
      return [413, { ok: false, code: "PROGRESS_TOO_LARGE", error: "Save data is too large" }];
    }
    const account = accounts.get(username);
    account.progress = body.progress ?? null;
    account.savedAt = now();
    persist();
    return [200, { ok: true, savedAt: account.savedAt }];
  }

  function loadProgress(body = {}) {
    const username = sessionUsername(body.sessionToken);
    if (!username) return [401, { ok: false, code: "NO_SESSION", error: "Sign in to load progress" }];
    const account = accounts.get(username);
    return [200, { ok: true, progress: account.progress, savedAt: account.savedAt }];
  }

  function logout(body = {}) {
    sessions.delete(String(body.sessionToken || ""));
    return [200, { ok: true }];
  }

  async function changePassword(body = {}) {
    const username = sessionUsername(body.sessionToken);
    if (!username) return [401, { ok: false, code: "NO_SESSION", error: "Sign in to change your password" }];
    if (!validPassword(body.password)) {
      return [400, { ok: false, code: "WEAK_PASSWORD", error: "Password must be 6-200 characters" }];
    }
    Object.assign(accounts.get(username), await passwordRecord(body.password));
    persist();
    return [200, { ok: true, username }];
  }

  function rename(body = {}, { allowDeveloperNames = false } = {}) {
    const currentUsername = sessionUsername(body.sessionToken);
    if (!currentUsername) return [401, { ok: false, code: "NO_SESSION", error: "Sign in to rename your account" }];
    const username = usernameOf(body.username);
    if (!USERNAME_PATTERN.test(username)) {
      return [400, { ok: false, code: "INVALID_USERNAME", error: "Username must be 3-24 characters: letters, numbers, underscore" }];
    }
    if (RESERVED_USERNAME_PATTERN.test(username) && !allowDeveloperNames) {
      return [403, { ok: false, code: "RESERVED_USERNAME", error: "That username is reserved" }];
    }
    if (username !== currentUsername && accounts.has(username)) {
      return [409, { ok: false, code: "USERNAME_TAKEN", error: "That username is already taken" }];
    }
    const account = accounts.get(currentUsername);
    if (username !== currentUsername) {
      accounts.delete(currentUsername);
      account.username = username;
      accounts.set(username, account);
      for (const [token, owner] of sessions) if (owner === currentUsername) sessions.set(token, username);
      persist();
    }
    return [200, { ok: true, username, admin: RESERVED_USERNAME_PATTERN.test(username), sessionToken: String(body.sessionToken) }];
  }

  return { register, login, save, loadProgress, logout, changePassword, rename, sessionUsername };
}
