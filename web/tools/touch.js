(() => {
  const canvas = document.querySelector("#game");
  const hud = document.querySelector("#touch-hud");
  const stick = document.querySelector("#touch-stick");
  const tip = document.querySelector("#touch-tip");
  const buttons = [...hud.querySelectorAll("[data-touch-key]")];
  const buttonPointers = new Map();
  let moving = null;
  let looking = null;
  let paused = false;

  const send = (...args) => window.toyroomTouchInput?.(...args);
  const clearStick = () => {
    moving = null;
    stick.style.setProperty("--stick-x", "0px");
    stick.style.setProperty("--stick-y", "0px");
    send("move", 0, 0);
  };
  const clear = () => {
    clearStick();
    looking = null;
    for (const button of buttonPointers.values()) button.removeAttribute("data-held");
    buttonPointers.clear();
    send("reset");
  };
  const updateStick = event => {
    const bounds = stick.getBoundingClientRect();
    const radius = bounds.width * .37;
    const x = (event.clientX - bounds.left - bounds.width / 2) / radius;
    const y = (event.clientY - bounds.top - bounds.height / 2) / radius;
    const length = Math.max(1, Math.hypot(x, y));
    stick.style.setProperty("--stick-x", `${x / length * radius}px`);
    stick.style.setProperty("--stick-y", `${y / length * radius}px`);
    send("move", x / length, y / length);
  };
  const buttonAction = (button, pressed) => {
    const action = button.dataset.touchKey;
    if (action === "throw") send("throw", pressed);
    else send("key", action, pressed);
  };

  window.toyroomTouchPause = value => {
    paused = value;
    hud.toggleAttribute("data-paused", paused);
    if (paused) queueMicrotask(clear);
  };

  window.activateToyroomTouch = () => {
    hud.hidden = false;
    stick.addEventListener("pointerdown", event => {
      if (paused || moving !== null) return;
      event.preventDefault();
      moving = event.pointerId;
      stick.setPointerCapture(moving);
      updateStick(event);
    });
    stick.addEventListener("pointermove", event => {
      if (event.pointerId === moving) updateStick(event);
    });
    for (const type of ["pointerup", "pointercancel", "lostpointercapture"]) {
      stick.addEventListener(type, event => {
        if (event.pointerId === moving) clearStick();
      });
    }

    canvas.addEventListener("pointerdown", event => {
      if (paused || looking || event.button !== 0) return;
      looking = { id: event.pointerId, x: event.clientX, y: event.clientY };
      canvas.setPointerCapture(event.pointerId);
    });
    canvas.addEventListener("pointermove", event => {
      if (event.pointerId !== looking?.id) return;
      const x = event.clientX - looking.x;
      const y = event.clientY - looking.y;
      looking.x = event.clientX;
      looking.y = event.clientY;
      if (x || y) {
        tip.hidden = true;
        send("look", x * 2, y * 2);
      }
    });
    for (const type of ["pointerup", "pointercancel", "lostpointercapture"]) {
      canvas.addEventListener(type, event => {
        if (event.pointerId === looking?.id) looking = null;
      });
    }

    for (const button of buttons) {
      button.addEventListener("pointerdown", event => {
        if (event.button !== 0 || button.hasAttribute("data-held")) return;
        event.preventDefault();
        button.setPointerCapture(event.pointerId);
        buttonPointers.set(event.pointerId, button);
        button.setAttribute("data-held", "");
        buttonAction(button, true);
      });
      button.addEventListener("pointerup", event => {
        if (buttonPointers.get(event.pointerId) !== button) return;
        buttonPointers.delete(event.pointerId);
        button.removeAttribute("data-held");
        buttonAction(button, false);
      });
      for (const type of ["pointercancel", "lostpointercapture"]) {
        button.addEventListener(type, event => {
          if (buttonPointers.has(event.pointerId)) clear();
        });
      }
    }

    window.addEventListener("blur", clear);
    document.addEventListener("visibilitychange", () => { if (document.hidden) clear(); });
  };
})();
