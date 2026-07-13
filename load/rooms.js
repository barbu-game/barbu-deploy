import ws from 'k6/ws';
import { check } from 'k6';

// Drives barbu_rooms_active above the KEDA threshold (~10 tables/pod) to trigger scale-out.
// Each VU opens a WebSocket, creates a table filled with bots, and holds it open long enough for
// KEDA to react (default ~4 min).
export const options = {
  scenarios: {
    rooms: { executor: 'per-vu-iterations', vus: 40, iterations: 1, maxDuration: '6m' },
  },
};

const WS_URL = __ENV.WS_URL || 'wss://api.barbu.kour0.com/ws/game';
const HOLD_MS = Number(__ENV.HOLD_MS || 240000);

export default function () {
  const res = ws.connect(WS_URL, {}, (socket) => {
    socket.on('open', () => {
      socket.send(JSON.stringify({ type: 'createRoom', name: `k6-${__VU}`, playerCount: 4 }));
      socket.send(JSON.stringify({ type: 'addBot' }));
      socket.send(JSON.stringify({ type: 'addBot' }));
      socket.send(JSON.stringify({ type: 'addBot' }));
      socket.send(JSON.stringify({ type: 'start' }));
      socket.setTimeout(() => socket.close(), HOLD_MS);
    });
  });
  check(res, { 'ws handshake 101': (r) => r && r.status === 101 });
}
