// Recreates Android's window.Android for the panel (main frame only). Native replaces __KEY__ (per-launch id) and
// __STATE__ (JSON snapshot) before injecting. Getters read the snapshot native keeps up to date; setters post
// fire-and-forget messages. Methods iOS cannot do (volume keys, pinning, home screen) are left out on purpose so the
// panel feature-detects them away.
(() => {
  'use strict';
  const key = '__KEY__';
  const s = __STATE__;
  const post = (m, ...a) => {
    try { window.webkit.messageHandlers.phonebox.postMessage({ k: key, m, a }); } catch (_) { /* no native side */ }
  };
  let lastId = 0;
  Object.defineProperty(window, '__phoneboxKey', { value: key, writable: false, configurable: false });
  window.Android = {
    battery: () => JSON.stringify(s.battery),
    transport: () => s.transport,
    is24Hour: () => s.is24Hour,
    version: () => s.version,
    sensors: () => JSON.stringify(s.sensors),
    pcs: () => JSON.stringify(s.pcs),
    haptic: () => post('haptic'),
    buzz: (_k, pattern) => post('buzz', String(pattern)),
    setBrightness: (_k, v) => post('setBrightness', Number(v)),
    setOrientation: (_k, mode) => post('setOrientation', String(mode)),
    selectPc: (_k, id) => post('selectPc', String(id)),
    forgetPc: (_k, id) => post('forgetPc', String(id)),
    canListen: () => s.canListen === true,
    listen: (_k, lang, offline) => {
      if (s.canListen !== true) return 0;
      const id = ++lastId;
      post('listen', id, String(lang || ''), offline === true);
      return id;
    },
    stopListening: (_k, id) => post('stopListening', Number(id)),
    cancelListening: (_k, id) => post('cancelListening', Number(id)),
  };
  window.__pbNative = { update: (patch) => { Object.assign(s, patch); } };
  // The stream's open/close pseudo-events say whether the agent is reachable, which is what transport() reports.
  let streamHandler;
  Object.defineProperty(window, 'onAgentStream', {
    configurable: true,
    get: () => streamHandler,
    set: (fn) => {
      streamHandler = typeof fn === 'function' ? (event, data) => {
        if (event === 'open') s.transport = 'wifi'; else if (event === 'close') s.transport = 'none';
        return fn(event, data);
      } : fn;
    },
  });
})();
