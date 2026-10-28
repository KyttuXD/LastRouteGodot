# Voice chat and spoken chat

## Proximity voice chat (`VoiceChat`, `VoiceCodec`)

- Online rooms only. The microphone opens when you are in an online room with **Settings -> VOICE -> VOICE CHAT: ON** and closes when you
  leave, switch it off or the host mutes you. A pill at the bottom right shows it (`MIC ON`, `MIC LIVE`, `HOLD [V] TO TALK`,
  `MIC MUTED BY HOST`). Nothing is recorded, saved or sent anywhere but the room; the packets live in memory only.
- **Voice activated** (default): speech above the SENSITIVITY level transmits, with a 0.35 s hangover. **Push to talk**: hold `V`
  (gamepad: right stick click); in a headset hold both thumbstick clicks. Mic gain, input device, a live level meter and THEIR VOLUME are in the tab.
- Wire format: mono 12 kHz IMA ADPCM, 40 ms per packet (245 bytes, about 6 KB/s while talking, nothing while quiet), unreliable RPC to the
  host. Godot has no Opus encoder; ADPCM costs about 0.2 ms per packet.
- The host relays only to peers on the same level within 29 m of the speaker. Listeners play it from an `AudioStreamPlayer3D` at the speaker's
  head (25 m range, quieter and muffled through walls, silent from other levels), up to 4 speakers at once, with a 0.3 s latency cap.
- Per-player: MUTE and a volume slider for each other player (Settings -> VOICE, and the pause menu's MUTE buttons); local only.

## Moderation

The host drops a player's voice when they are room-muted (the owner/admin menu's chat mute now also silences voice and tells the
player), troll-flagged, send malformed or oversized packets, or exceed 8 KB/s. A force-muted client also closes its own gate.

## Spoken chat (TTS)

Chat lines are read with the OS voice (`DisplayServer.tts_speak`) at the sender's distance: **TTS: EVERYONE** (others' lines), **OWN LINES**
or **OFF**, with a rate slider and an OS voice choice (AUTO = a stable voice per player). The chat moderation and spam limits are
unchanged; there is no swear filter.

Validator: `voice_chat` (`godot --headless --path . res://scenes/validate.tscn -- voice_chat`).
