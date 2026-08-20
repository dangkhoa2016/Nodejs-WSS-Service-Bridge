process.env.NODE_ENV = 'test';

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { resetIdleTimeout } from '../../src/shared/idle-timeout.js';

describe('resetIdleTimeout', () => {
  it('treats timeout 0 as disabled', async () => {
    let fired = false;
    const state = { timer: null };
    const timer = resetIdleTimeout(state, 0, () => {
      fired = true;
    });

    assert.equal(timer, null);
    assert.equal(state.timer, null);
    await new Promise((resolve) => setTimeout(resolve, 20));
    assert.equal(fired, false);
  });

  it('replaces an existing timer', () => {
    const state = { timer: setTimeout(() => {}, 1000) };
    const oldTimer = state.timer;
    const timer = resetIdleTimeout(state, 1000, () => {});
    assert.notEqual(timer, oldTimer);
    clearTimeout(timer);
  });
});
