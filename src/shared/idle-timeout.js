export function resetIdleTimeout(state, timeoutMs, onTimeout) {
  if (state.timer) clearTimeout(state.timer);
  state.timer = null;

  if (timeoutMs === 0) return null;

  state.timer = setTimeout(onTimeout, timeoutMs);
  state.timer.unref?.();
  return state.timer;
}
