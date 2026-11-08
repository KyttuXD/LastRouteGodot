extends RefCounted

## Bump when generation changes the world produced by an existing seed.
## Beta policy: older revisions require a new run, never an in-place migration.
## Shared by save storage and the multiplayer compatibility fingerprint.
const REVISION := 1
