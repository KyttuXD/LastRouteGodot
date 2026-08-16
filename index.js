// Pterodactyl-friendly entry point. The backend remains implemented as ES
// modules in server.mjs; package.json's "type": "module" lets a standard
// Node.js egg launch this file directly with `node index.js`.
import { startLastRouteServerFromEnvironment } from "./backend/server.mjs";

startLastRouteServerFromEnvironment();
