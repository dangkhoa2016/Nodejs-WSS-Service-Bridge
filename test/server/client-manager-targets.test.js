process.env.NODE_ENV = 'test';

import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { describe, it } from 'node:test';
import WebSocket from 'ws';

import { ClientManager } from '../../src/server/ClientManager.js';

function mockWs() {
  const ws = new EventEmitter();
  ws.readyState = WebSocket.OPEN;
  ws.bufferedAmount = 0;
  ws._socket = { remoteAddress: '127.0.0.1' };
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

function manager() {
  return new ClientManager({
    streams: new Map(),
    handleClientFrame() {},
    abortAnyStream() {},
  });
}

function seedClient(cm, ws, tunnelId) {
  ws.tunnelId = tunnelId;
  cm.clients.add(ws);
  cm.clientsByTunnelId.set(tunnelId, ws);
}

describe('ClientManager target routing', () => {
  it('resolves exact tunnel IDs', () => {
    const cm = manager();
    const k1 = mockWs();
    const k2 = mockWs();

    seedClient(cm, k1, 'kaggle-1');
    seedClient(cm, k2, 'kaggle-2');

    assert.equal(cm.resolveTargetClient('kaggle-2').ws, k2);
    assert.equal(cm.getClientByTunnelId('kaggle-1'), k1);
  });

  it('requires a target when multiple tunnel clients are connected', () => {
    const cm = manager();
    seedClient(cm, mockWs(), 'kaggle-1');
    seedClient(cm, mockWs(), 'colab-1');

    const result = cm.resolveTargetClient('');
    assert.equal(result.ws, null);
    assert.match(result.error, /required when multiple tunnel clients/);
  });

  it('keeps legacy no-target routing when exactly one client is connected', () => {
    const cm = manager();
    const only = mockWs();
    assert.equal(cm.addClient(only, 'kaggle-1'), true);

    const result = cm.resolveTargetClient('');
    assert.equal(result.ws, only);
    assert.equal(result.tunnelId, 'kaggle-1');
  });

  it('rejects duplicate live tunnel IDs', () => {
    const cm = manager();
    const first = mockWs();
    const duplicate = mockWs();

    first.tunnelId = 'kaggle-1';
    cm.clientsByTunnelId.set('kaggle-1', first);

    assert.equal(cm.addClient(duplicate, 'kaggle-1'), false);
    assert.equal(duplicate.closed.code, 1008);
  });
});
