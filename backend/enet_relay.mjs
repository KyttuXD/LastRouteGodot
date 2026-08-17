import { randomBytes, timingSafeEqual } from "node:crypto";
import { createSocket } from "node:dgram";

// A tiny authenticated UDP tunnel for Godot's existing ENet transport.
// Both players make outbound UDP connections to this public socket, so a
// player hosting behind CGNAT (notably Starlink Residential) never needs an
// inbound port, UPnP, or router configuration.
export const RELAY_MAGIC = Buffer.from("LRR1", "ascii");
export const RELAY_HEADER_BYTES = 14;
export const RELAY_MAX_DATAGRAM_BYTES = 1472;
export const RelayFrame = Object.freeze({
  HOST_REGISTER: 1,
  HOST_ACK: 2,
  GUEST_JOIN: 3,
  GUEST_ACK: 4,
  GUEST_DATA: 5,
  HOST_DATA: 6,
  ERROR: 7,
});

const ROOM_CODE_PATTERN = /^[A-HJ-NP-Z2-9]{5}$/;

function safeEqual(leftValue, rightValue) {
  const left = Buffer.from(String(leftValue || ""));
  const right = Buffer.from(String(rightValue || ""));
  const length = Math.max(left.length, right.length, 1);
  const paddedLeft = Buffer.alloc(length);
  const paddedRight = Buffer.alloc(length);
  left.copy(paddedLeft);
  right.copy(paddedRight);
  return timingSafeEqual(paddedLeft, paddedRight) && left.length === right.length;
}

export function encodeRelayFrame(type, sessionId, code, payload = Buffer.alloc(0)) {
  const roomCode = String(code || "").trim().toUpperCase();
  if (!ROOM_CODE_PATTERN.test(roomCode)) throw new Error("INVALID RELAY ROOM CODE");
  const body = Buffer.isBuffer(payload) ? payload : Buffer.from(payload);
  const frame = Buffer.alloc(RELAY_HEADER_BYTES + body.length);
  RELAY_MAGIC.copy(frame, 0);
  frame.writeUInt8(type, 4);
  frame.writeUInt32LE(sessionId >>> 0, 5);
  frame.write(roomCode, 9, 5, "ascii");
  body.copy(frame, RELAY_HEADER_BYTES);
  return frame;
}

export function decodeRelayFrame(frame) {
  if (!Buffer.isBuffer(frame) || frame.length < RELAY_HEADER_BYTES
      || frame.length > RELAY_MAX_DATAGRAM_BYTES
      || !frame.subarray(0, 4).equals(RELAY_MAGIC)) return null;
  const code = frame.toString("ascii", 9, 14);
  if (!ROOM_CODE_PATTERN.test(code)) return null;
  return {
    type: frame.readUInt8(4),
    sessionId: frame.readUInt32LE(5),
    code,
    payload: frame.subarray(RELAY_HEADER_BYTES),
  };
}

function endpointKey(address, port) {
  return `${address}:${port}`;
}

function newSessionId(sessions) {
  for (;;) {
    const id = randomBytes(4).readUInt32LE(0);
    if (id !== 0 && !sessions.has(id)) return id;
  }
}

export function createEnetRelay({
  roomByCode,
  now = Date.now,
  logger = console,
  hostTtlMs = 15_000,
  sessionTtlMs = 45_000,
  maximumGuestsPerRoom = 15,
  guestAllocationWindowMs = 10_000,
  maximumGuestAllocationsPerAddress = 4,
} = {}) {
  if (typeof roomByCode !== "function") throw new TypeError("roomByCode is required");

  const socket = createSocket("udp4");
  const hosts = new Map();
  const sessions = new Map();
  const guestSessions = new Map();
  const guestEndpoints = new Map();
  const guestAllocationRates = new Map();
  let listening = false;
  let relayPort = 0;
  let lastError = "";

  function send(type, sessionId, code, payload, endpoint) {
    if (!endpoint || !listening) return;
    const frame = encodeRelayFrame(type, sessionId, code, payload);
    socket.send(frame, endpoint.port, endpoint.address);
  }

  function sendError(code, endpoint, message) {
    send(RelayFrame.ERROR, 0, code, Buffer.from(String(message).slice(0, 160)), endpoint);
  }

  function removeSession(sessionId) {
    const session = sessions.get(sessionId);
    if (!session) return;
    sessions.delete(sessionId);
    guestSessions.delete(session.guestKey);
    guestEndpoints.delete(session.endpointKey);
  }

  function allowGuestAllocation(code, address) {
    const timestamp = now();
    const key = `${code}|${address}`;
    const existing = guestAllocationRates.get(key);
    const rate = !existing || timestamp >= existing.resetAt
      ? { count: 0, resetAt: timestamp + guestAllocationWindowMs }
      : existing;
    rate.count += 1;
    guestAllocationRates.set(key, rate);
    return rate.count <= maximumGuestAllocationsPerAddress;
  }

  function removeHost(code) {
    hosts.delete(code);
    for (const [sessionId, session] of sessions) {
      if (session.code === code) removeSession(sessionId);
    }
  }

  function prune() {
    const timestamp = now();
    for (const [code, host] of hosts) {
      if (!roomByCode(code) || timestamp - host.lastSeen > hostTtlMs) removeHost(code);
    }
    for (const [sessionId, session] of sessions) {
      if (!roomByCode(session.code) || timestamp - session.lastSeen > sessionTtlMs) {
        removeSession(sessionId);
      }
    }
    for (const [key, rate] of guestAllocationRates) {
      if (timestamp >= rate.resetAt) guestAllocationRates.delete(key);
    }
  }

  socket.on("message", (packet, remote) => {
    const frame = decodeRelayFrame(packet);
    if (!frame) return;
    const endpoint = { address: remote.address, port: remote.port };
    const room = roomByCode(frame.code);

    if (frame.type === RelayFrame.HOST_REGISTER) {
      if (!room || !safeEqual(frame.payload.toString("utf8"), room.token)) {
        sendError(frame.code, endpoint, "HOST AUTHORIZATION FAILED");
        return;
      }
      hosts.set(frame.code, { ...endpoint, lastSeen: now() });
      send(RelayFrame.HOST_ACK, 0, frame.code, Buffer.alloc(0), endpoint);
      return;
    }

    if (frame.type === RelayFrame.GUEST_JOIN) {
      const host = hosts.get(frame.code);
      if (!room || !host || now() - host.lastSeen > hostTtlMs) {
        sendError(frame.code, endpoint, "ROOM HOST HAS NOT REACHED THE RELAY");
        return;
      }
      if (frame.payload.length < 8 || frame.payload.length > 32) {
        sendError(frame.code, endpoint, "INVALID GUEST NONCE");
        return;
      }
      const guestKey = `${frame.code}|${endpointKey(remote.address, remote.port)}|${frame.payload.toString("hex")}`;
      const endpointSessionKey = `${frame.code}|${endpointKey(remote.address, remote.port)}`;
      let sessionId = guestSessions.get(guestKey);
      // A retrying client may regenerate its nonce, but one UDP endpoint is
      // still one guest. Rebind that endpoint's existing session instead of
      // consuming another room slot for every nonce.
      if (!sessionId) sessionId = guestEndpoints.get(endpointSessionKey);
      if (!sessionId) {
        if (!allowGuestAllocation(frame.code, remote.address)) {
          sendError(frame.code, endpoint, "TOO MANY RELAY JOIN ATTEMPTS");
          return;
        }
        let roomGuests = 0;
        for (const session of sessions.values()) if (session.code === frame.code) roomGuests += 1;
        if (roomGuests >= maximumGuestsPerRoom) {
          sendError(frame.code, endpoint, "ROOM RELAY IS FULL");
          return;
        }
        sessionId = newSessionId(sessions);
        guestSessions.set(guestKey, sessionId);
        guestEndpoints.set(endpointSessionKey, sessionId);
        sessions.set(sessionId, {
          code: frame.code,
          guest: endpoint,
          guestKey,
          endpointKey: endpointSessionKey,
          lastSeen: now(),
        });
      } else {
        const session = sessions.get(sessionId);
        guestSessions.delete(session.guestKey);
        session.guestKey = guestKey;
        guestSessions.set(guestKey, sessionId);
        session.guest = endpoint;
        session.lastSeen = now();
      }
      send(RelayFrame.GUEST_ACK, sessionId, frame.code, Buffer.alloc(0), endpoint);
      return;
    }

    const session = sessions.get(frame.sessionId);
    if (!session || session.code !== frame.code || !room) return;

    if (frame.type === RelayFrame.GUEST_DATA) {
      if (session.guest.address !== remote.address || session.guest.port !== remote.port) return;
      const host = hosts.get(frame.code);
      if (!host || now() - host.lastSeen > hostTtlMs) return;
      session.lastSeen = now();
      send(RelayFrame.GUEST_DATA, frame.sessionId, frame.code, frame.payload, host);
    } else if (frame.type === RelayFrame.HOST_DATA) {
      const host = hosts.get(frame.code);
      if (!host || host.address !== remote.address || host.port !== remote.port) return;
      host.lastSeen = now();
      session.lastSeen = now();
      send(RelayFrame.HOST_DATA, frame.sessionId, frame.code, frame.payload, session.guest);
    }
  });

  socket.on("listening", () => {
    listening = true;
    relayPort = socket.address().port;
    lastError = "";
    logger.log(`ENet gameplay relay: UDP ${relayPort}`);
  });
  socket.on("error", (error) => {
    lastError = error.message;
    logger.error(`ENet gameplay relay error: ${error.message}`);
  });
  socket.on("close", () => {
    listening = false;
    hosts.clear();
    sessions.clear();
    guestSessions.clear();
    guestEndpoints.clear();
    guestAllocationRates.clear();
  });

  const pruneTimer = setInterval(prune, Math.max(1000, Math.min(hostTtlMs, sessionTtlMs) / 3));
  pruneTimer.unref();
  socket.once("close", () => clearInterval(pruneTimer));

  socket.relayStatus = () => ({
    enabled: true,
    listening,
    port: relayPort,
    hosts: hosts.size,
    sessions: sessions.size,
    error: lastError || undefined,
  });
  return socket;
}
