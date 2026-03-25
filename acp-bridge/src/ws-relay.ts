/**
 * Minimal WebSocket relay server for phone → desktop communication.
 * Launched by WebRelay.swift as a subprocess.
 *
 * Protocol:
 * - Listens on a random port (printed to stdout as "PORT:<number>")
 * - Accepts one WebSocket connection at a time
 * - Receives JSON messages from phone, prints them to stdout as "MSG:<json>"
 * - Reads JSON messages from stdin (one per line), sends to connected client
 */

import { createServer } from "http";
import { WebSocketServer, WebSocket } from "ws";
import { createInterface } from "readline";

const server = createServer((req, res) => {
  // Health check for non-WS requests
  res.writeHead(200);
  res.end("ok");
});

const wss = new WebSocketServer({ server });
let activeClient: WebSocket | null = null;

wss.on("connection", (ws) => {
  // Only one client at a time (latest wins)
  if (activeClient && activeClient.readyState === WebSocket.OPEN) {
    activeClient.close();
  }
  activeClient = ws;
  process.stderr.write("CLIENT_CONNECTED\n");

  ws.on("message", (data) => {
    try {
      const msg = JSON.parse(data.toString());
      // Forward to Swift via stdout
      process.stdout.write("MSG:" + JSON.stringify(msg) + "\n");
    } catch {}
  });

  ws.on("close", () => {
    if (activeClient === ws) {
      activeClient = null;
      process.stderr.write("CLIENT_DISCONNECTED\n");
    }
  });

  ws.on("error", () => {
    if (activeClient === ws) {
      activeClient = null;
    }
  });
});

// Read messages from stdin (Swift → phone)
const rl = createInterface({ input: process.stdin });
rl.on("line", (line) => {
  if (activeClient && activeClient.readyState === WebSocket.OPEN) {
    activeClient.send(line);
  }
});

// Exit cleanly on signals or stdin close (parent died)
function shutdown() {
  wss.close();
  server.close();
  process.exit(0);
}
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
rl.on("close", shutdown);

// Watchdog: exit if parent process dies (kill(pid, 0) throws when process is gone)
const parentPid = process.ppid;
setInterval(() => {
  try {
    process.kill(parentPid, 0); // signal 0 = just check if alive
  } catch {
    shutdown();
  }
}, 5000);

// Listen on random port
server.listen(0, "127.0.0.1", () => {
  const addr = server.address();
  if (addr && typeof addr === "object") {
    process.stdout.write("PORT:" + addr.port + "\n");
  }
});
