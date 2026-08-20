import WebSocket from 'ws';
import { MAX_TUNNEL_CLIENTS } from '../shared/config.js';
import { logVerbose } from '../shared/logger.js';
import { normalizeTunnelId } from '../shared/tunnel-id.js';

export class ClientManager {
  constructor(streamManager) {
    this.clients = new Set();
    this.clientsByTunnelId = new Map();
    this.streamManager = streamManager;
    this._heartbeatInterval = null;
  }

  getActiveClient() {
    let best = null;
    for (const ws of this.clients) {
      if (ws.readyState !== WebSocket.OPEN) continue;
      if (!best || ws.bufferedAmount < best.bufferedAmount) best = ws;
    }
    return best;
  }

  getClientByTunnelId(tunnelId) {
    const normalized = normalizeTunnelId(tunnelId);
    if (!normalized) return null;
    const ws = this.clientsByTunnelId.get(normalized);
    if (!ws || ws.readyState !== WebSocket.OPEN) return null;
    return ws;
  }

  resolveTargetClient(tunnelId) {
    let normalized;
    try {
      normalized = normalizeTunnelId(tunnelId);
    } catch (err) {
      return { ws: null, tunnelId: '', error: err.message };
    }

    if (normalized) {
      const ws = this.getClientByTunnelId(normalized);
      if (!ws) {
        return { ws: null, tunnelId: normalized, error: `Tunnel target not connected: ${normalized}` };
      }
      return { ws, tunnelId: normalized, error: null };
    }

    const openClients = [...this.clients].filter((ws) => ws.readyState === WebSocket.OPEN);
    if (openClients.length === 0) return { ws: null, tunnelId: '', error: 'No tunnel client connected' };
    if (openClients.length > 1) {
      return {
        ws: null,
        tunnelId: '',
        error: 'Target tunnel ID is required when multiple tunnel clients are connected',
      };
    }

    const ws = openClients[0];
    return { ws, tunnelId: ws.tunnelId || '', error: null };
  }

  addClient(ws, tunnelId = '') {
    let normalized;
    try {
      normalized = normalizeTunnelId(tunnelId);
    } catch {
      try {
        ws.close(1008, 'Invalid tunnel ID');
      } catch {}
      return false;
    }

    if (this.clients.size >= MAX_TUNNEL_CLIENTS) {
      try {
        ws.close(1013, 'Too many tunnel clients');
      } catch {}
      return false;
    }

    if (normalized) {
      const existing = this.clientsByTunnelId.get(normalized);
      if (existing && existing.readyState === WebSocket.OPEN) {
        try {
          ws.close(1008, 'Tunnel ID already connected');
        } catch {}
        return false;
      }
      if (existing) this.clientsByTunnelId.delete(normalized);
    }

    ws.binaryType = 'nodebuffer';
    ws.isAlive = true;
    ws.tunnelId = normalized;

    this.clients.add(ws);
    if (normalized) this.clientsByTunnelId.set(normalized, ws);

    logVerbose('ws', 'client_add', {
      clientCount: this.clients.size,
      remoteAddr: ws._socket?.remoteAddress,
      ...(normalized ? { tunnelId: normalized } : {}),
    });

    ws.on('pong', () => {
      ws.isAlive = true;
      logVerbose('heartbeat', 'pong', {
        remoteAddr: ws._socket?.remoteAddress,
        ...(ws.tunnelId ? { tunnelId: ws.tunnelId } : {}),
      });
    });

    ws.on('message', (data, isBinary) => {
      if (!isBinary) return;
      try {
        this.streamManager.handleClientFrame(ws, data);
      } catch {}
    });

    ws.on('close', () => this.cleanupClient(ws));
    ws.on('error', () => this.cleanupClient(ws));
    return true;
  }

  cleanupClient(ws) {
    this.clients.delete(ws);
    if (ws.tunnelId && this.clientsByTunnelId.get(ws.tunnelId) === ws) {
      this.clientsByTunnelId.delete(ws.tunnelId);
    }

    logVerbose('ws', 'client_remove', {
      clientCount: this.clients.size,
      remoteAddr: ws._socket?.remoteAddress,
      ...(ws.tunnelId ? { tunnelId: ws.tunnelId } : {}),
    });

    for (const state of Array.from(this.streamManager.streams.values())) {
      if (state.ws === ws) this.streamManager.abortAnyStream(state, 'Tunnel client disconnected', false);
    }
  }

  startHeartbeat() {
    this._heartbeatInterval = setInterval(() => {
      for (const ws of this.clients) {
        if (ws.isAlive === false) {
          try {
            ws.terminate();
          } catch {}
          continue;
        }

        ws.isAlive = false;
        try {
          ws.ping();
          logVerbose('heartbeat', 'ping', {
            remoteAddr: ws._socket?.remoteAddress,
            ...(ws.tunnelId ? { tunnelId: ws.tunnelId } : {}),
          });
        } catch {}
      }
    }, 30000);

    if (this._heartbeatInterval.unref) this._heartbeatInterval.unref();
  }

  stopHeartbeat() {
    if (this._heartbeatInterval) {
      clearInterval(this._heartbeatInterval);
      this._heartbeatInterval = null;
    }
  }

  async close(timeoutMs = 5000) {
    this.stopHeartbeat();
    const results = await Promise.allSettled([...this.clients].map((ws) => closeClient(ws, timeoutMs)));
    for (const r of results) {
      if (r.status === 'rejected') logVerbose('ws', 'client_close_error', { reason: r.reason?.message });
    }
  }
}

function closeClient(ws, timeoutMs) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = () => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve();
    };
    const timer = setTimeout(() => {
      try {
        ws.terminate();
      } finally {
        finish();
      }
    }, timeoutMs);
    timer.unref?.();
    ws.once('close', finish);
    try {
      ws.close(1001, 'Server shutting down');
    } catch {
      finish();
    }
  });
}
