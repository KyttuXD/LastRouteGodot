#!/usr/bin/env python3
"""Claude-facing playtest client (stdlib only): talk to a game started with --playtest=PORT.

    client = PlaytestClient("127.0.0.1", 47600)      # an SSH tunnel to the test machine works: ssh -L 47600:127.0.0.1:47600 <host>
    client.hello()
    client.start_run(game="last_route", seed="ALPHA")
    obs = client.observe()
    client.step(30, act={"move": [0, 1], "look": [0.2, 0]})      # advance 30 physics frames while walking forward and turning
    client.screenshot("/tmp/shot.png")                           # windowed runs only

Run this file directly for the example agent loop (walks toward the nearest relay with a tiny policy):  python3 client.py --port 47600
Protocol: one JSON object per line each way, see docs/PLAYTEST.md.
"""
import argparse
import json
import math
import socket
import time


class PlaytestClient:
    def __init__(self, host: str = "127.0.0.1", port: int = 47600, timeout: float = 120.0):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.buf = b""
        self._id = 0

    def call(self, cmd: str, **fields) -> dict:
        self._id += 1
        message = {"cmd": cmd, "id": self._id, **fields}
        self.sock.sendall((json.dumps(message) + "\n").encode())
        while b"\n" not in self.buf:
            chunk = self.sock.recv(1 << 16)
            if not chunk:
                raise ConnectionError("game closed the connection")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        reply = json.loads(line)
        if not reply.get("ok", False):
            raise RuntimeError(f"{cmd}: {reply.get('error', reply)}")
        return reply

    def hello(self) -> dict:
        return self.call("hello")

    def start_run(self, game: str = "last_route", seed: str = "PLAYTEST", difficulty: str = "standard", **extra) -> dict:
        return self.call("start_run", game=game, seed=seed, difficulty=difficulty, **extra)

    def observe(self) -> dict:
        return self.call("observe")["obs"]

    def act(self, **act) -> None:
        self.call("act", act=act)

    def step(self, frames: int = 1, act: dict | None = None) -> dict:
        fields = {"frames": frames}
        if act is not None:
            fields["act"] = act
        return self.call("step", **fields).get("obs", {})

    def ui(self) -> dict:
        return self.call("ui")

    def press(self, name: str) -> dict:
        return self.call("press", name=name)

    def admin(self, name: str, **args) -> dict:
        return self.call("admin", name=name, **args)

    def screenshot(self, path: str) -> dict:
        return self.call("screenshot", path=path)

    def log(self, since: int = 0) -> dict:
        return self.call("log", since=since)

    def quit(self, code: int = 0) -> None:
        try:
            self.call("quit", code=code)
        except (ConnectionError, OSError):
            pass


def example_loop(client: PlaytestClient, seconds: float = 60.0) -> None:
    """Tiny agent: face the nearest uncollected relay, walk to it, press interact when close."""
    client.start_run(seed="AGENT")
    deadline = time.time() + seconds
    while time.time() < deadline:
        obs = client.observe()
        if obs.get("run", {}).get("over"):
            print("run over:", obs["run"].get("death"))
            break
        relays = obs["world"]["relays"]
        if not relays:
            client.step(30, act={"move": [0, 1], "look": [0.3, 0]})
            continue
        target = relays[0]
        px, _, pz = obs["player"]["pos"]
        dx, dz = target["x"] + 0.5 - px, target["y"] + 0.5 - pz
        yaw_target = math.atan2(-dx, -dz)
        error = (yaw_target - obs["player"]["yaw"] + math.pi) % (2 * math.pi) - math.pi
        turn = max(-1.0, min(1.0, -error * 3))
        close = math.hypot(dx, dz) < 2.0
        act = {"move": [0, 0 if close else (1 if abs(error) < 0.5 else 0)], "look": [turn, 0]}
        if close and abs(error) < 0.15:
            act["pulse"] = ["interact"]
        client.step(6, act=act)
        print(f"t={obs['time']:7.1f}s relays={obs['run'].get('relays')} next relay {math.hypot(dx, dz):5.1f} m, hunters {[h['id'] for h in obs['hunters']]}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=47600)
    parser.add_argument("--seconds", type=float, default=60.0)
    args = parser.parse_args()
    game = PlaytestClient(args.host, args.port)
    print(game.hello())
    example_loop(game, args.seconds)
