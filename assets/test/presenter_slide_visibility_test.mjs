import assert from "node:assert/strict";
import test from "node:test";

import { watchSlideVisibility } from "../js/presenter_slide_visibility.mjs";

function mountFrame(visibilityState) {
  let observer;
  class Observer {
    constructor(callback) {
      this.callback = callback;
    }
    observe() {
      observer = this;
    }
    disconnect() {
      observer = undefined;
    }
  }
  const doc = Object.assign(new EventTarget(), {
    visibilityState,
    defaultView: { IntersectionObserver: Observer },
  });
  const events = [];
  const watcher = watchSlideVisibility({ ownerDocument: doc }, event => events.push(event));

  return {
    events,
    watcher,
    changeVisibility(state) {
      doc.visibilityState = state;
      doc.dispatchEvent(new Event("visibilitychange"));
    },
    reportIntersection(ratio) {
      observer?.callback([{ isIntersecting: ratio > 0, intersectionRatio: ratio }]);
    },
  };
}

test("activates the initially visible frame and reactivates it once when shown again", t => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const frame = mountFrame("visible");
  frame.reportIntersection(1);
  assert.deepEqual(frame.events, ["goto"]);

  frame.changeVisibility("hidden");
  t.mock.timers.tick(150);
  frame.changeVisibility("visible");
  t.mock.timers.tick(149);
  assert.deepEqual(frame.events, ["goto"]);
  t.mock.timers.tick(1);
  frame.reportIntersection(1);

  frame.changeVisibility("visible");
  t.mock.timers.tick(150);
  assert.deepEqual(frame.events, ["goto", "goto_visible"]);
  frame.watcher.destroy();
});

test("a hidden frame waits and a quick pass through it does not activate it", t => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const frame = mountFrame("hidden");
  frame.changeVisibility("visible");
  t.mock.timers.tick(100);
  frame.changeVisibility("hidden");
  t.mock.timers.tick(200);
  assert.deepEqual(frame.events, []);

  frame.changeVisibility("visible");
  t.mock.timers.tick(150);
  frame.reportIntersection(1);
  assert.deepEqual(frame.events, ["goto_visible"]);
  frame.watcher.destroy();
});

test("a disconnected or removed frame cannot send a deferred activation", t => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const frame = mountFrame("hidden");
  frame.changeVisibility("visible");
  frame.watcher.disconnected();
  t.mock.timers.tick(150);
  assert.deepEqual(frame.events, []);

  frame.changeVisibility("hidden");
  frame.watcher.reconnected();
  t.mock.timers.tick(150);
  assert.deepEqual(frame.events, []);

  frame.watcher.disconnected();
  frame.changeVisibility("visible");
  frame.watcher.reconnected();
  t.mock.timers.tick(150);
  frame.reportIntersection(1);
  assert.deepEqual(frame.events, ["goto_visible"]);

  frame.changeVisibility("hidden");
  frame.changeVisibility("visible");
  frame.watcher.destroy();
  t.mock.timers.tick(150);
  assert.deepEqual(frame.events, ["goto_visible"]);
});

test("a CSS-hidden iframe stays inactive even if its document reports visible", t => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const frame = mountFrame("visible");
  frame.reportIntersection(0);
  assert.deepEqual(frame.events, []);
  frame.reportIntersection(1);
  assert.deepEqual(frame.events, ["goto"]);

  frame.changeVisibility("hidden");
  frame.changeVisibility("visible");
  t.mock.timers.tick(150);
  frame.reportIntersection(0);
  assert.deepEqual(frame.events, ["goto"]);
  frame.reportIntersection(1);
  assert.deepEqual(frame.events, ["goto", "goto_visible"]);
  frame.watcher.destroy();
});
