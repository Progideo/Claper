const visibilityDelay = 150;

export function watchSlideVisibility(frame, sendGoto) {
  const doc = frame.ownerDocument;
  const Observer = doc.defaultView.IntersectionObserver;
  if (typeof Observer !== "function") {
    if (doc.visibilityState === "visible") sendGoto("goto");
    return;
  }

  let connected = true;
  let pending = true;
  let timer;
  let observer;

  function cancelActivation() {
    clearTimeout(timer);
    observer?.disconnect();
    observer = undefined;
  }

  function confirmIntersection(event) {
    if (!connected || !pending || doc.visibilityState !== "visible") return;

    const candidate = new Observer(entries => {
      if (observer !== candidate) return;
      if (!entries.some(entry => entry.isIntersecting && entry.intersectionRatio > 0)) return;

      cancelActivation();
      if (!connected || doc.visibilityState !== "visible") return;
      pending = false;
      sendGoto(event);
    });
    observer = candidate;
    candidate.observe(frame);
  }

  function scheduleActivation() {
    cancelActivation();
    if (!connected || !pending || doc.visibilityState !== "visible") return;
    timer = setTimeout(() => confirmIntersection("goto_visible"), visibilityDelay);
  }

  function visibilityChanged() {
    if (doc.visibilityState !== "visible") {
      pending = true;
      cancelActivation();
      return;
    }
    scheduleActivation();
  }

  doc.addEventListener("visibilitychange", visibilityChanged);
  confirmIntersection("goto");

  return {
    disconnected() {
      connected = false;
      cancelActivation();
    },
    reconnected() {
      connected = true;
      scheduleActivation();
    },
    destroy() {
      cancelActivation();
      doc.removeEventListener("visibilitychange", visibilityChanged);
    },
  };
}
