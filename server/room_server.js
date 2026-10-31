// LAN room relay for the pixel-duel web build.
//
//   node server/room_server.js            # listens on 8899
//   PORT=8901 MAX_PLAYERS=5 node server/room_server.js
//
// It is a dumb relay, on purpose: the host browser runs the only simulation and
// sends snapshots; guests send their button bits. The server just groups
// sockets into rooms of at most MAX_PLAYERS, hands out short codes and forwards
// packets. Keeping the simulation in one place means a five player match needs
// no rollback netcode.
//
// Protocol (JSON over WebSocket)
//   client -> server
//     {"t":"create","name":"Player 1"}          -> {"t":"room","code":"AB12CD","slot":0,"slots":[...]}
//     {"t":"join","code":"AB12CD","name":"..."} -> same, slot 1..4
//     {"t":"list"}                              -> {"t":"rooms","rooms":[{"code","host","players","open"}]}
//     {"t":"data","payload":{...}}              -> forwarded to the other members
//     {"t":"leave"}                             -> {"t":"closed"}
//   server -> client
//     {"t":"room", ...}      room state, broadcast on every change
//     {"t":"data","from":<slot>,"payload":{...}}
//     {"t":"error","reason":"..."}
//
// Run it behind the site's reverse proxy at a websocket path, or expose the
// port directly on the LAN for a same-network match.
'use strict';

const http = require('http');
const crypto = require('crypto');

let WebSocketServer;
try {
  ({ WebSocketServer } = require('ws'));
} catch (error) {
  console.error('missing dependency: npm install ws');
  process.exit(1);
}

const PORT = Number(process.env.PORT || 8899);
const MAX_PLAYERS = Number(process.env.MAX_PLAYERS || 5);
const IDLE_MS = Number(process.env.IDLE_MS || 120000);
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

const rooms = new Map();

// --- accounts -------------------------------------------------------------
// A player picks a name plus a recovery question: logging back in means
// answering it. Answers are stored as salted hashes and never leave the host.
const fs = require('fs');
const path = require('path');
const DATA_DIR = process.env.DATA_DIR || path.join(process.env.HOME || '.', '.pixel-duel-relay');
const ACCOUNTS_FILE = path.join(DATA_DIR, 'accounts.json');

function loadAccounts() {
  try {
    return JSON.parse(fs.readFileSync(ACCOUNTS_FILE, 'utf8'));
  } catch (error) {
    return {};
  }
}

let accounts = loadAccounts();

function saveAccounts() {
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true });
    fs.writeFileSync(ACCOUNTS_FILE, JSON.stringify(accounts, null, 2));
  } catch (error) {
    console.error('cannot save accounts:', error.message);
  }
}

function hashAnswer(answer, salt) {
  return crypto.createHash('sha256').update(`${salt}|${String(answer).trim().toLowerCase()}`).digest('hex');
}

function cleanName(value) {
  const name = String(value || '').trim().replace(/\s+/g, ' ');
  return name.length >= 2 && name.length <= 16 ? name : '';
}

function leaderboard() {
  return Object.entries(accounts)
    .map(([name, record]) => ({ name, wins: record.wins || 0, losses: record.losses || 0 }))
    .sort((a, b) => b.wins - a.wins || a.name.localeCompare(b.name))
    .slice(0, 10);
}

function broadcastLeaderboard() {
  const rows = leaderboard();
  wss.clients.forEach((client) => send(client, { t: 'leaderboard', entries: rows }));
}

function authOk(ws, name) {
  ws.account = name;
  const record = accounts[name];
  send(ws, { t: 'auth_ok', name, wins: record.wins || 0, losses: record.losses || 0 });
  send(ws, { t: 'leaderboard', entries: leaderboard() });
}


function code() {
  let value = '';
  for (let i = 0; i < 6; i += 1) {
    value += CODE_ALPHABET[crypto.randomInt(CODE_ALPHABET.length)];
  }
  return rooms.has(value) ? code() : value;
}

function send(ws, message) {
  if (ws && ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(message));
  }
}

function slotList(room) {
  return room.members.map((member, index) => ({
    slot: index,
    name: member.name,
    ready: !!member.ready,
  }));
}

function roomState(room) {
  return {
    t: 'room',
    code: room.code,
    max: MAX_PLAYERS,
    host: 0,
    slots: slotList(room),
  };
}

function broadcastRoom(room) {
  const state = roomState(room);
  for (const member of room.members) {
    send(member.ws, state);
  }
}

function announceRooms() {
  const list = [];
  for (const room of rooms.values()) {
    list.push({
      code: room.code,
      host: room.members.length ? room.members[0].name : '?',
      players: room.members.length,
      open: room.members.length < MAX_PLAYERS,
    });
  }
  for (const room of rooms.values()) {
    for (const member of room.members) {
      send(member.ws, { t: 'rooms', rooms: list });
    }
  }
}

function leave(ws, reason) {
  const room = ws.room;
  if (!room) return;
  ws.room = null;
  const index = room.members.findIndex((member) => member.ws === ws);
  if (index >= 0) {
    room.members.splice(index, 1);
  }
  if (!room.members.length) {
    rooms.delete(room.code);
  } else {
    // Slots are positions, so tell everyone the new layout and re-number.
    broadcastRoom(room);
    for (const member of room.members) {
      send(member.ws, { t: 'peer_left', reason: reason || 'left' });
    }
  }
  send(ws, { t: 'closed', reason: reason || 'left' });
  announceRooms();
}

function attach(ws, room) {
  ws.room = room;
  room.members.push({ ws, account: ws.account, name: ws.account, ready: false });
  const slot = room.members.length - 1;
  send(ws, { t: 'joined', code: room.code, slot, max: MAX_PLAYERS });
  broadcastRoom(room);
  announceRooms();
}

const server = http.createServer((request, response) => {
  if (request.url === '/health') {
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify({ ok: true, rooms: rooms.size, max: MAX_PLAYERS }));
    return;
  }
  response.writeHead(404, { 'Content-Type': 'text/plain' });
  response.end('pixel-duel room relay\n');
});

const wss = new WebSocketServer({ server });

wss.on('connection', (ws) => {
  ws.room = null;
  ws.alive = Date.now();
  ws.on('pong', () => { ws.alive = Date.now(); });
  ws.on('message', (raw) => {
    let message;
    try {
      message = JSON.parse(raw.toString());
    } catch (error) {
      send(ws, { t: 'error', reason: 'bad json' });
      return;
    }
    ws.alive = Date.now();
    switch (message.t) {
      case 'register': {
        const name = cleanName(message.name);
        const question = String(message.question || '').trim();
        const answer = String(message.answer || '').trim();
        if (!name) {
          send(ws, { t: 'auth_error', reason: 'name must be 2-16 characters' });
          return;
        }
        if (question.length < 3 || answer.length < 1) {
          send(ws, { t: 'auth_error', reason: 'question and answer are required' });
          return;
        }
        if (accounts[name]) {
          send(ws, { t: 'auth_error', reason: 'name already taken' });
          return;
        }
        const salt = crypto.randomBytes(8).toString('hex');
        accounts[name] = { salt, hash: hashAnswer(answer, salt), question, wins: 0, losses: 0 };
        saveAccounts();
        authOk(ws, name);
        broadcastLeaderboard();
        break;
      }
      case 'auth': {
        const name = cleanName(message.name);
        if (!name) {
          send(ws, { t: 'auth_error', reason: 'name must be 2-16 characters' });
          return;
        }
        const record = accounts[name];
        if (!record) {
          send(ws, { t: 'auth_unknown', name });
          return;
        }
        send(ws, { t: 'auth_question', name, question: record.question });
        break;
      }
      case 'answer': {
        const name = cleanName(message.name);
        const record = accounts[name];
        if (!record) {
          send(ws, { t: 'auth_unknown', name });
          return;
        }
        if (hashAnswer(message.answer, record.salt) !== record.hash) {
          send(ws, { t: 'auth_error', reason: 'wrong answer' });
          return;
        }
        authOk(ws, name);
        break;
      }
      case 'leaderboard':
        send(ws, { t: 'leaderboard', entries: leaderboard() });
        break;
      case 'result': {
        // The host reports the winning slot; the relay scores every member.
        const room = ws.room;
        if (!room || !ws.account) return;
        const winner = Number(message.winner_slot);
        room.members.forEach((member, index) => {
          if (!member.account) return;
          const record = accounts[member.account];
          if (!record) return;
          if (index === winner) record.wins = (record.wins || 0) + 1;
          else record.losses = (record.losses || 0) + 1;
        });
        saveAccounts();
        broadcastLeaderboard();
        break;
      }
      case 'create': {
        if (!ws.account) {
          send(ws, { t: 'error', reason: 'login required' });
          return;
        }
        const room = { code: code(), members: [] };
        rooms.set(room.code, room);
        attach(ws, room);
        break;
      }
      case 'join': {
        if (!ws.account) {
          send(ws, { t: 'error', reason: 'login required' });
          return;
        }
        const room = rooms.get(String(message.code || '').toUpperCase());
        if (!room) {
          send(ws, { t: 'error', reason: 'room not found' });
          return;
        }
        if (room.members.length >= MAX_PLAYERS) {
          send(ws, { t: 'error', reason: 'room full' });
          return;
        }
        attach(ws, room);
        break;
      }
      case 'list':
        send(ws, { t: 'rooms', rooms: [...rooms.values()].map((room) => ({
          code: room.code,
          host: room.members.length ? room.members[0].name : '?',
          players: room.members.length,
          open: room.members.length < MAX_PLAYERS,
        })) });
        break;
      case 'ready': {
        const room = ws.room;
        if (!room) return;
        const member = room.members.find((entry) => entry.ws === ws);
        if (member) member.ready = !!message.ready;
        broadcastRoom(room);
        break;
      }
      case 'data': {
        const room = ws.room;
        if (!room) return;
        const from = room.members.findIndex((member) => member.ws === ws);
        for (const member of room.members) {
          if (member.ws !== ws) {
            send(member.ws, { t: 'data', from, payload: message.payload });
          }
        }
        break;
      }
      case 'leave':
        leave(ws, 'left');
        break;
      default:
        send(ws, { t: 'error', reason: 'unknown message' });
    }
  });
  ws.on('close', () => leave(ws, 'disconnected'));
  ws.on('error', () => leave(ws, 'error'));
});

setInterval(() => {
  const now = Date.now();
  wss.clients.forEach((ws) => {
    if (now - ws.alive > IDLE_MS) {
      ws.terminate();
    } else {
      ws.ping();
    }
  });
}, 30000).unref();

server.listen(PORT, () => {
  console.log(`pixel-duel room relay on :${PORT}, max ${MAX_PLAYERS} players per room`);
});
