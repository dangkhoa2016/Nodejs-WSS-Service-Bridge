process.env.NODE_ENV = 'test';

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { parseAgentRoutes } from '../../src/shared/port-parser.js';

describe('parseAgentRoutes', () => {
  it('parses multiple local-to-target routes', () => {
    assert.deepEqual(parseAgentRoutes('22001=kaggle-1:2222,22002=kaggle-2:2222,22003=colab-1:2222'), [
      { localPort: 22001, targetTunnelId: 'kaggle-1', targetPort: 2222 },
      { localPort: 22002, targetTunnelId: 'kaggle-2', targetPort: 2222 },
      { localPort: 22003, targetTunnelId: 'colab-1', targetPort: 2222 },
    ]);
  });

  it('rejects duplicate local ports', () => {
    assert.throws(() => parseAgentRoutes('22001=kaggle-1:2222,22001=kaggle-2:2222'), /duplicate local port/);
  });

  it('rejects malformed routes and invalid target IDs', () => {
    assert.throws(() => parseAgentRoutes('22001=kaggle-1'), /target must use/);
    assert.throws(() => parseAgentRoutes('22001=kaggle:one:2222'), /target tunnel ID/);
    assert.throws(() => parseAgentRoutes('0=kaggle-1:2222'), /local port out of range/);
    assert.throws(() => parseAgentRoutes('22001=kaggle-1:70000'), /target port out of range/);
  });
});
