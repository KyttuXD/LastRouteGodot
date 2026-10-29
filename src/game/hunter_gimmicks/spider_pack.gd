class_name SpiderPack
extends RefCounted

## The shared state of a wolf-spider PAIR (host only; nothing here is replicated): one rest timer so the two never chain-hunt a runner
## one after the other, and a recall so when one gives up the other goes home with it. The first member is the clock: only it advances
## `elapsed`, so a pair does not tick twice per frame.

var members: Array = []
var elapsed := 0.0
var rest_until := 0.0
var recall_seq := 0


func join(gimmick) -> void:
	if not members.has(gimmick):
		members.append(gimmick)
	gimmick.pack = self


func tick(gimmick, delta: float) -> void:
	if not members.is_empty() and members[0] == gimmick:
		elapsed += delta


func resting() -> bool:
	return elapsed < rest_until


func start_rest(seconds: float) -> void:
	rest_until = maxf(rest_until, elapsed + seconds)


func recall() -> void:
	recall_seq += 1
