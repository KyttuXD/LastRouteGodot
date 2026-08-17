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

    assert.deepEqual(relay.relayStatus(), {
      enabled: true,
      listening: true,
      port: relayPort,
      hosts: 1,
      sessions: 1,
      error: undefined,
    });
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
