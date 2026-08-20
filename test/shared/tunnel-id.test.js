process.env.NODE_ENV = 'test';

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { normalizeTunnelId } from '../../src/shared/tunnel-id.js';

describe('normalizeTunnelId', () => {
  it('accepts stable machine-style IDs', () => {
    assert.equal(normalizeTunnelId(' kaggle-1 '), 'kaggle-1');
    assert.equal(normalizeTunnelId('colab_1.example'), 'colab_1.example');
  });

  it('allows empty IDs for legacy single-client mode', () => {
    assert.equal(normalizeTunnelId(''), '');
    assert.equal(normalizeTunnelId(undefined), '');
  });

  it('rejects unsafe or ambiguous IDs', () => {
    assert.throws(() => normalizeTunnelId('/kaggle'), /must be 1-64 characters/);
    assert.throws(() => normalizeTunnelId('a:b'), /must be 1-64 characters/);
    assert.throws(() => normalizeTunnelId('x'.repeat(65)), /must be 1-64 characters/);
  });

  it('can require an ID', () => {
    assert.throws(() => normalizeTunnelId('', { required: true, name: 'target' }), /target is required/);
  });
});
