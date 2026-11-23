import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

test('retiring the legacy worker clears only Flutter caches and refreshes its pages', async () => {
  const listeners = new Map();
  const remaining = new Set(['flutter-app-cache','flutter-temp-cache','flutter-app-manifest','other-app-cache']);
  const navigated = [];
  let unregistered = false, skipped = false, activation;
  const self = {
    addEventListener:(name,handler) => listeners.set(name,handler),
    skipWaiting:() => { skipped = true; },
    registration:{scope:'http://localhost:8787/',unregister:async () => { unregistered = true; }},
    clients:{matchAll:async () => [
      {url:'http://localhost:8787/',navigate:async url => navigated.push(url)},
      {url:'http://another.test/',navigate:async url => navigated.push(url)},
    ]},
  };
  vm.runInNewContext(readFileSync(new URL('./retire-web-cache.js',import.meta.url),'utf8'),{
    self,caches:{delete:async name => remaining.delete(name)},
  });
  listeners.get('install')();
  listeners.get('activate')({waitUntil:promise => activation = promise});
  await activation;
  assert.equal(skipped,true);
  assert.equal(unregistered,true);
  assert.deepEqual([...remaining],['other-app-cache']);
  assert.deepEqual(navigated,['http://localhost:8787/']);
});
