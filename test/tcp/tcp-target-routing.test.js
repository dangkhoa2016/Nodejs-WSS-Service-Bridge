process.env.NODE_ENV = 'test';

import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { describe, it } from 'node:test';
import WebSocket from 'ws';

import { ClientManager } from '../../src/server/ClientManager.js';
import { StreamManager } from '../../src/server/StreamManager.js';
import { FrameCodec, PROTO } from '../../src/shared/protocol.js';
import { TcpAgentServer } from '../../src/tcp/TcpAgentServer.js';
import { TcpRouter } from '../../src/tcp/TcpRouter.js';

function mockWs() {
  const ws = new EventEmitter();
  ws.readyState = WebSocket.OPEN;
  ws.bufferedAmount = 0;
  ws._socket = { remoteAddress: '127.0.0.1' };
  ws.sent = [];
  ws.send = (data, options, callback) => {
    ws.sent.push(Buffer.from(data));
    if (typeof options === 'function') options();
    if (typeof callback === 'function') callback();
  };
  ws.close = (code, reason) => {
    ws.closed = { code, reason };
    ws.readyState = WebSocket.CLOSED;
  };
  ws.ping = () => {};
  ws.terminate = () => {
    ws.readyState = WebSocket.CLOSED;
    ws.emit('close');
  };
  return ws;
}

function decode(buffer) {
  const frame = FrameCodec.parseFrame(buffer);
  let json = null;
  try {
    json = FrameCodec.parseJsonPayload(frame.payload);
  } catch {}
  return { ...frame, json };
}

describe('TCP agent multi-target routing', () => {
  it('routes TCP_OPEN only to the requested tunnel ID', () => {
    const sm = new StreamManager();
    const cm = new ClientManager(sm);
    const router = new TcpRouter(sm, cm);
    const agentServer = new TcpAgentServer(sm, router, {
      allowedPorts: [2222],
      maxConnectionsPerPort: 0,
      maxStreamsPerAgent: 0,
    });

    const kaggle1 = mockWs();
    const kaggle2 = mockWs();
    kaggle1.tunnelId = 'kaggle-1';
    kaggle2.tunnelId = 'kaggle-2';
    cm.clients.add(kaggle1);
    cm.clients.add(kaggle2);
    cm.clientsByTunnelId.set('kaggle-1', kaggle1);
    cm.clientsByTunnelId.set('kaggle-2', kaggle2);

    const agent = mockWs();
    agentServer.handleConnection(agent);

    agentServer._handleTcpConnect(
      agent,
      Buffer.from(JSON.stringify({ port: 2222, targetTunnelId: 'kaggle-2', requestId: 41 })),
    );

    assert.equal(kaggle1.sent.length, 0);
    assert.equal(kaggle2.sent.length, 1);

    const open = decode(kaggle2.sent[0]);
    assert.equal(open.type, PROTO.TYPE.TCP_OPEN);
    assert.deepEqual(open.json, { host: '127.0.0.1', port: 2222 });

    const state = sm.streams.get(open.streamId);
    assert.equal(state.targetTunnelId, 'kaggle-2');
    sm.abortTcpStream(state, 'test cleanup', false);
  });

  it('rejects an unqualified agent connect when multiple targets are online', () => {
    const sm = new StreamManager();
    const cm = new ClientManager(sm);
    const router = new TcpRouter(sm, cm);
    const agentServer = new TcpAgentServer(sm, router, {
      allowedPorts: [2222],
      maxConnectionsPerPort: 0,
      maxStreamsPerAgent: 0,
    });

    const kaggle = mockWs();
    const colab = mockWs();
    kaggle.tunnelId = 'kaggle-1';
    colab.tunnelId = 'colab-1';
    cm.clients.add(kaggle);
    cm.clients.add(colab);
    cm.clientsByTunnelId.set('kaggle-1', kaggle);
    cm.clientsByTunnelId.set('colab-1', colab);

    const agent = mockWs();
    agentServer.handleConnection(agent);

    agentServer._handleTcpConnect(agent, Buffer.from(JSON.stringify({ port: 2222, requestId: 42 })));

    assert.equal(agent.sent.length, 1);
    const abort = decode(agent.sent[0]);
    assert.equal(abort.type, PROTO.TYPE.TCP_ABORT);
    assert.equal(abort.streamId, 0);
    assert.equal(abort.json.requestId, 42);
    assert.match(abort.json.message, /required when multiple tunnel clients/);
  });
});
