class_name NetChannels
extends RefCounted

## ENet channels for the route's RPCs. Every RPC used to share channel 0, and ENet holds an unreliable packet behind
## any reliable packet sent before it on the same channel, so one lost door/pickup event (resent after an RTT or
## more) froze every runner's 20 Hz movement and the hunters until it arrived. Discrete events stay reliable and in
## order on channel 0 (the default); each high-rate stream gets its own channel.
##
## ENetMultiplayerPeer's default (max_channels = 0) opens the protocol maximum, so no peer setup changes.

const EVENTS := 0          # reliable, ordered: world events, interactions, snapshots, profiles, chat (default)
const STATE := 1           # unreliable_ordered: the 20 Hz runner sample (PlayerStateWire)
const HUNTERS := 2         # unreliable_ordered: host hunter frames
const HUNTERS_LARGE := 3   # reliable: hunter frames too big for one datagram
const VOICE := 4           # unreliable: proximity voice
