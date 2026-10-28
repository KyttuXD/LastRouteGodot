import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { createSocket } from "node:dgram";
import {
  createEnetRelay,
  decodeRelayFrame,
  encodeRelayFrame,
  RelayFrame,
} from "./enet_relay.mjs";

async function udpSocket() {
  const socket = createSocket("udp4");
  socket.bind(0, "127.0.0.1");
  await once(socket, "listening");
  return socket;
}

function receive(socket, timeoutMs = 1000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.off("message", onMessage);
      reject(new Error("UDP receive timed out"));
    }, timeoutMs);
    const onMessage = (message, remote) => {
      clearTimeout(timer);
      resolve({ frame: decodeRelayFrame(message), remote });
    };
    socket.once("message", onMessage);
  });
}

async function waitFor(check, timeoutMs = 1000) {
  const deadline = Date.now() + timeoutMs;
  while (!check()) {
    if (Date.now() > deadline) throw new Error("condition not reached");
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

function send(socket, port, frame) {
  socket.send(frame, port, "127.0.0.1");
}

test("authenticated relay tunnels ENet datagrams through one public UDP port", async () => {
  const room = { code: "ABCDE", token: "host-secret" };
  const relay = createEnetRelay({
    roomByCode: (code) => code === room.code ? room : null,
    logger: { log() {}, error() {} },
  });
  relay.bind(0, "127.0.0.1");
  await once(relay, "listening");
  const relayPort = relay.address().port;
  const host = await udpSocket();
  const guest = await udpSocket();
  const attacker = await udpSocket();

  try {
    send(attacker, relayPort, encodeRelayFrame(
      RelayFrame.HOST_REGISTER, 0, room.code, Buffer.from("wrong-secret")));
    assert.equal((await receive(attacker)).frame.type, RelayFrame.ERROR);

    send(host, relayPort, encodeRelayFrame(
      RelayFrame.HOST_REGISTER, 0, room.code, Buffer.from(room.token)));
    assert.equal((await receive(host)).frame.type, RelayFrame.HOST_ACK);

    send(guest, relayPort, encodeRelayFrame(
      RelayFrame.GUEST_JOIN, 0, room.code, Buffer.from("guest-01")));
    const joined = (await receive(guest)).frame;
    assert.equal(joined.type, RelayFrame.GUEST_ACK);
    assert.notEqual(joined.sessionId, 0);

    // A retrying client may rotate its nonce, but its one UDP endpoint must
    // never consume another room slot for that retry.
    for (let index = 0; index < 20; index += 1) {
      send(guest, relayPort, encodeRelayFrame(
        RelayFrame.GUEST_JOIN, 0, room.code,
        Buffer.from(`retry-${String(index).padStart(3, "0")}`)));
      const retried = (await receive(guest)).frame;
      assert.equal(retried.type, RelayFrame.GUEST_ACK);
      assert.equal(retried.sessionId, joined.sessionId);
    }

    const request = Buffer.from("raw-enet-connect-packet");
    send(guest, relayPort, encodeRelayFrame(
      RelayFrame.GUEST_DATA, joined.sessionId, room.code, request));
    const atHost = (await receive(host)).frame;
    assert.equal(atHost.type, RelayFrame.GUEST_DATA);
    assert.equal(atHost.sessionId, joined.sessionId);
    assert.deepEqual(atHost.payload, request);

    const response = Buffer.from("raw-enet-ack-packet");
    send(host, relayPort, encodeRelayFrame(
      RelayFrame.HOST_DATA, joined.sessionId, room.code, response));
    const atGuest = (await receive(guest)).frame;
    assert.equal(atGuest.type, RelayFrame.HOST_DATA);
    assert.deepEqual(atGuest.payload, response);

    const { counters, socketBuffers, ...status } = relay.relayStatus();
    assert.deepEqual(status, {
      enabled: true,
      listening: true,
      port: relayPort,
      hosts: 1,
      sessions: 1,
      error: undefined,
    });
    assert.equal(counters.forwardedGuest, 1);
    assert.equal(counters.forwardedHost, 1);
    assert.equal(counters.forwardedBytes, request.length + response.length);
    assert.ok(socketBuffers.receive > 0 && socketBuffers.send > 0, "buffer sizes are reported");

    // Every datagram the relay refuses is counted, so a deploy shows where co-op traffic goes.
    send(attacker, relayPort, encodeRelayFrame(
      RelayFrame.GUEST_DATA, joined.sessionId, room.code, request));
    send(attacker, relayPort, encodeRelayFrame(
      RelayFrame.GUEST_DATA, joined.sessionId ^ 1, room.code, request));
    send(attacker, relayPort, Buffer.from("not a relay packet"));
    await waitFor(() => {
      const seen = relay.relayStatus().counters;
      return seen.droppedWrongEndpoint === 1 && seen.droppedUnknownSession === 1 && seen.droppedInvalid === 1;
    });
    assert.equal(relay.relayStatus().counters.forwardedGuest, 1, "refused frames are not forwarded");
  } finally {
    host.close();
    guest.close();
    attacker.close();
    relay.close();
    await Promise.all([once(host, "close"), once(guest, "close"),
      once(attacker, "close"), once(relay, "close")]);
  }
});

test("relay protocol rejects malformed and oversized frames", () => {
  assert.equal(decodeRelayFrame(Buffer.from("not a relay packet")), null);
  assert.throws(() => encodeRelayFrame(RelayFrame.GUEST_JOIN, 0, "O0I1L"),
    /INVALID RELAY ROOM CODE/);
  const oversized = Buffer.alloc(1473);
  Buffer.from("LRR1").copy(oversized);
  oversized.write("ABCDE", 9, 5, "ascii");
  assert.equal(decodeRelayFrame(oversized), null);
});

test("oldest active guest is promoted and remaining relay sessions survive host loss", async () => {
  let timestamp = 0;
  const room = { code: "ABCDE", token: "host-secret" };
  const relay = createEnetRelay({
    roomByCode: (code) => code === room.code ? room : null,
    promoteRoomHost: () => {
      room.token = "migrated-host-secret";
      return { token: room.token };
    },
    now: () => timestamp,
    hostTtlMs: 100,
    sessionTtlMs: 1000,
    logger: { log() {}, error() {} },
  });
  relay.bind(0, "127.0.0.1");
  await once(relay, "listening");
  const relayPort = relay.address().port;
  const host = await udpSocket();
  const firstGuest = await udpSocket();
  const secondGuest = await udpSocket();

  try {
    send(host, relayPort, encodeRelayFrame(
      RelayFrame.HOST_REGISTER, 0, room.code, Buffer.from("host-secret")));
    assert.equal((await receive(host)).frame.type, RelayFrame.HOST_ACK);
    send(firstGuest, relayPort, encodeRelayFrame(
      RelayFrame.GUEST_JOIN, 0, room.code, Buffer.from("first-guest")));
    const firstSession = (await receive(firstGuest)).frame.sessionId;
    timestamp += 1;
    send(secondGuest, relayPort, encodeRelayFrame(
      RelayFrame.GUEST_JOIN, 0, room.code, Buffer.from("second-guest")));
    const secondSession = (await receive(secondGuest)).frame.sessionId;

    timestamp = 200;
    const promotionPromise = receive(firstGuest);
    const migrationPromise = receive(secondGuest);
    relay.pruneNow();
    const promotion = (await promotionPromise).frame;
    assert.equal(promotion.type, RelayFrame.HOST_PROMOTE);
    assert.equal(promotion.sessionId, firstSession);
    assert.equal(promotion.payload.toString("utf8"), "migrated-host-secret");
    assert.equal((await migrationPromise).frame.type, RelayFrame.HOST_MIGRATING);

    const acknowledgementPromise = receive(firstGuest);
    const rejoinPromise = receive(secondGuest);
    send(firstGuest, relayPort, encodeRelayFrame(
      RelayFrame.HOST_REGISTER, 0, room.code, promotion.payload));
    assert.equal((await acknowledgementPromise).frame.type, RelayFrame.HOST_ACK);
    // The new host registration sends another migration notice. Consume it
    // before proving that the old guest session now routes to the replacement.
    assert.equal((await rejoinPromise).frame.type, RelayFrame.HOST_MIGRATING);
    const request = Buffer.from("enet-reconnect-packet");
    const replacementPacketPromise = receive(firstGuest);
    send(secondGuest, relayPort, encodeRelayFrame(
      RelayFrame.GUEST_DATA, secondSession, room.code, request));
    const atReplacement = (await replacementPacketPromise).frame;
    assert.equal(atReplacement.type, RelayFrame.GUEST_DATA);
    assert.equal(atReplacement.sessionId, secondSession);
    assert.deepEqual(atReplacement.payload, request);
  } finally {
    host.close();
    firstGuest.close();
    secondGuest.close();
    relay.close();
    await Promise.all([once(host, "close"), once(firstGuest, "close"),
      once(secondGuest, "close"), once(relay, "close")]);
  }
});
