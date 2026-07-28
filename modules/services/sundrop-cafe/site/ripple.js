(function () {
  'use strict';

  var canvas = document.getElementById('ripple-canvas');
  if (!canvas) return;
  var ctx = canvas.getContext('2d');

  var reducedMotion = window.matchMedia &&
    window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Fully opaque colors only — dimming the trail is done by blending the
  // fill color from the leading circle's color toward the trailing color,
  // never via alpha/transparency.
  var LEAD_COLOR = { r: 0xf5, g: 0x2e, b: 0x0d };  // matches --gold-pigment
  var TRAIL_COLOR = { r: 0xff, g: 0x7a, b: 0x0b }; // matches --gold-pale

  var DROP_COUNT = 22;
  var TRAIL_LENGTH = 4;       // dimmer circles behind the leading one
  var SPEED_MIN = 0.02;       // px/ms
  var SPEED_MAX = 0.045;
  var RADIUS_MIN = 5;
  var RADIUS_MAX = 12;

  var width = 0;
  var height = 0;
  var dpr = Math.min(window.devicePixelRatio || 1, 2);

  function resize() {
    width = window.innerWidth;
    height = window.innerHeight;
    canvas.width = Math.floor(width * dpr);
    canvas.height = Math.floor(height * dpr);
    canvas.style.width = width + 'px';
    canvas.style.height = height + 'px';
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  window.addEventListener('resize', resize);
  resize();

  function randRange(a, b) {
    return a + Math.random() * (b - a);
  }

  function lerp(a, b, t) {
    return a + (b - a) * t;
  }

  function colorAtDim(t) {
    var r = Math.round(lerp(LEAD_COLOR.r, TRAIL_COLOR.r, t));
    var g = Math.round(lerp(LEAD_COLOR.g, TRAIL_COLOR.g, t));
    var b = Math.round(lerp(LEAD_COLOR.b, TRAIL_COLOR.b, t));
    return 'rgb(' + r + ',' + g + ',' + b + ')';
  }

  function makeDrop(startAbove) {
    var radius = randRange(RADIUS_MIN, RADIUS_MAX);
    return {
      x: randRange(20, width - 20),
      y: startAbove ? randRange(-height, 0) : randRange(0, height),
      radius: radius,
      speed: randRange(SPEED_MIN, SPEED_MAX),
      trailSpacing: radius * 2.75
    };
  }

  var drops = [];
  for (var i = 0; i < DROP_COUNT; i++) {
    drops.push(makeDrop(true));
  }

  function drawDrop(drop) {
    for (var t = 0; t <= TRAIL_LENGTH; t++) {
      var y = drop.y - t * drop.trailSpacing;
      if (y < -drop.radius * 2 || y > height + drop.radius * 2) continue;

      var dimT = t / TRAIL_LENGTH;
      var r = drop.radius * (1 - dimT * 0.4);

      ctx.beginPath();
      ctx.arc(drop.x, y, r, 0, Math.PI * 2);
      ctx.fillStyle = colorAtDim(dimT);
      ctx.fill();
    }
  }

  var lastFrame = 0;

  function tick(now) {
    if (!lastFrame) lastFrame = now;
    var dt = now - lastFrame;
    lastFrame = now;

    ctx.clearRect(0, 0, width, height);

    for (var i = 0; i < drops.length; i++) {
      var drop = drops[i];
      drop.y += drop.speed * dt;

      var trailTop = drop.y - TRAIL_LENGTH * drop.trailSpacing;
      if (trailTop > height + drop.radius * 2) {
        drops[i] = makeDrop(false);
        drops[i].y = -drops[i].trailSpacing;
      }

      drawDrop(drops[i]);
    }

    requestAnimationFrame(tick);
  }

  if (reducedMotion) {
    // Draw a single static frame and stop — respects the user's motion
    // preference while still giving the background some texture.
    ctx.clearRect(0, 0, width, height);
    drops.forEach(function (d) { d.y = randRange(0, height); });
    drops.forEach(drawDrop);
  } else {
    requestAnimationFrame(tick);
  }
})();
