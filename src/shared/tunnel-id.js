const TUNNEL_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;

export function normalizeTunnelId(value, { name = 'tunnel ID', required = false } = {}) {
  const normalized = value == null ? '' : String(value).trim();

  if (!normalized) {
    if (required) throw new Error(`${name} is required`);
    return '';
  }

  if (!TUNNEL_ID_PATTERN.test(normalized)) {
    throw new Error(
      `${name} must be 1-64 characters, start with a letter or digit, and contain only letters, digits, ".", "_", or "-"`,
    );
  }

  return normalized;
}
