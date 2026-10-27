extends RefCounted

## Deliberately broken suite for the runner self-test (scripts/test_runner_failfast.sh): it must not compile.

func run(host: Node) -> int:
	return this is not valid gdscript
