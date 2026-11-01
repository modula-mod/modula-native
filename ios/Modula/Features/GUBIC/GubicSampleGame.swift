import Foundation

/// "Orbit Tap": a small HTML5 canvas game bundled with the app to exercise the GUBIC runtime and
/// bridge end to end. It is not in the catalogue, so the UI labels it as a bundled sample and its
/// achievements are a local preview that is never sent to the server.
enum GubicSampleGame {
    static let id = "digital.modula.gubic.sample.orbit-tap"
    static let title = "Orbit Tap"
    static let summary = "Tap to hop between two orbits. Collect stars, dodge rocks. A bundled sample that runs in the GUBIC HTML5 runtime."

    static var manifest: [String: Any] {
        [
        "schema": "modula.gubic.game.v1",
        "gameId": id,
        "version": "1.0.0",
        "title": title,
        "genre": "Arcade",
        "categories": ["arcade", "casual"],
        "runtime": ["engine": "html5", "entry": "index.html", "orientation": "any"],
        "bridge": ["version": 1, "capabilities": ["lifecycle", "score", "achievements"]],
        "network": "none",
        "ageRating": "4+",
        "monetisation": "free",
    ]
    }

    static let capabilities: Set<String> = ["lifecycle", "score", "achievements"]

    static let achievements: [GubicAchievement] = [
        .init(key: "first-star", title: "First star", description: "Collect your first star.", points: 10, unlockedAt: nil),
        .init(key: "ten-stars", title: "Stargazer", description: "Collect 10 stars in one run.", points: 20, unlockedAt: nil),
        .init(key: "orbit-master", title: "Orbit master", description: "Collect 25 stars in one run.", points: 40, unlockedAt: nil),
    ]

    static var files: [String: Data] {
        ["index.html": Data(indexHTML.utf8), "game.js": Data(gameJS.utf8)]
    }

    private static let indexHTML = #"""
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
    <title>Orbit Tap</title>
    <style>
      html, body { margin: 0; height: 100%; background: #070A14; overflow: hidden; touch-action: none; -webkit-user-select: none; user-select: none; }
      canvas { display: block; width: 100vw; height: 100vh; }
    </style>
    </head>
    <body>
    <canvas id="stage" aria-label="Orbit Tap game"></canvas>
    <script src="game.js"></script>
    </body>
    </html>
    """#

    private static let gameJS = #"""
    (() => {
      'use strict';
      const bridge = window.gubic;
      const hello = (bridge && bridge.hello) || {};
      const reduceMotion = !!hello.reduceMotion;
      const canvas = document.getElementById('stage');
      const ctx = canvas.getContext('2d');
      let w = 0, h = 0, dpr = 1;
      function resize() {
        dpr = Math.min(window.devicePixelRatio || 1, 3);
        w = window.innerWidth; h = window.innerHeight;
        canvas.width = Math.floor(w * dpr); canvas.height = Math.floor(h * dpr);
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      }
      window.addEventListener('resize', resize); resize();

      const state = { angle: 0, ring: 0, speed: 1.6, items: [], score: 0, over: false, paused: false, spawn: 0, trail: [], unlocked: {} };
      const radii = () => { const m = Math.min(w, h); return [m * 0.22, m * 0.36]; };
      function reset() {
        state.angle = 0; state.ring = 0; state.speed = 1.6; state.items = []; state.score = 0; state.over = false; state.spawn = 0; state.trail = [];
        if (bridge) bridge.reportScore(0);
      }
      function unlock(key) {
        if (state.unlocked[key]) return;
        state.unlocked[key] = true;
        if (bridge) bridge.unlockAchievement(key);
      }
      function tap(e) {
        if (e) e.preventDefault();
        if (state.paused) return;
        if (state.over) { reset(); return; }
        state.ring = 1 - state.ring;
      }
      canvas.addEventListener('pointerdown', tap);
      window.addEventListener('keydown', (e) => { if (e.code === 'Space') tap(e); });
      window.addEventListener('gubic:pause', () => { state.paused = true; });
      window.addEventListener('gubic:resume', () => { state.paused = false; last = performance.now(); });

      function spawn() {
        const rock = Math.random() < Math.min(0.25 + state.score * 0.01, 0.5);
        const ahead = state.angle + 1.6 + Math.random() * 2.4;
        state.items.push({ a: ahead, ring: Math.random() < 0.5 ? 0 : 1, rock, life: 7 });
      }

      let last = performance.now();
      function frame(now) {
        const dt = Math.min((now - last) / 1000, 0.05); last = now;
        if (!state.paused && !state.over) step(dt);
        draw(now);
        requestAnimationFrame(frame);
      }
      function step(dt) {
        state.angle += state.speed * dt;
        state.spawn -= dt;
        if (state.spawn <= 0) { spawn(); state.spawn = Math.max(0.45, 1.1 - state.score * 0.02); }
        const [r0, r1] = radii(); const pr = state.ring ? r1 : r0;
        const px = Math.cos(state.angle) * pr, py = Math.sin(state.angle) * pr;
        if (!reduceMotion) { state.trail.push({ x: px, y: py }); if (state.trail.length > 14) state.trail.shift(); }
        for (const it of state.items) {
          it.life -= dt;
          const ir = it.ring ? r1 : r0;
          const dx = Math.cos(it.a) * ir - px, dy = Math.sin(it.a) * ir - py;
          if (!it.hit && dx * dx + dy * dy < 22 * 22) {
            it.hit = true;
            if (it.rock) { state.over = true; if (bridge) bridge.gameOver({ score: state.score }); }
            else {
              state.score += 1; state.speed += 0.04;
              if (bridge) bridge.reportScore(state.score);
              if (state.score >= 1) unlock('first-star');
              if (state.score >= 10) unlock('ten-stars');
              if (state.score >= 25) unlock('orbit-master');
            }
          }
        }
        state.items = state.items.filter((it) => !it.hit && it.life > 0);
      }
      function star(x, y, r) {
        ctx.beginPath();
        for (let i = 0; i < 10; i++) {
          const a = -Math.PI / 2 + i * Math.PI / 5, rr = i % 2 ? r * 0.45 : r;
          ctx.lineTo(x + Math.cos(a) * rr, y + Math.sin(a) * rr);
        }
        ctx.closePath(); ctx.fill();
      }
      function draw(now) {
        ctx.clearRect(0, 0, w, h);
        const cx = w / 2, cy = h / 2; const [r0, r1] = radii();
        ctx.lineWidth = 2; ctx.strokeStyle = 'rgba(120,160,255,0.28)';
        for (const r of [r0, r1]) { ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke(); }
        const glow = reduceMotion ? 1 : 0.85 + 0.15 * Math.sin(now / 300);
        ctx.fillStyle = `rgba(110,86,240,${0.9 * glow})`; ctx.beginPath(); ctx.arc(cx, cy, 16, 0, Math.PI * 2); ctx.fill();
        for (const it of state.items) {
          const ir = it.ring ? r1 : r0; const x = cx + Math.cos(it.a) * ir, y = cy + Math.sin(it.a) * ir;
          if (it.rock) { ctx.fillStyle = '#E8607A'; ctx.beginPath(); ctx.arc(x, y, 11, 0, Math.PI * 2); ctx.fill(); }
          else { ctx.fillStyle = '#F6D77A'; star(x, y, 12); }
        }
        state.trail.forEach((p, i) => { ctx.fillStyle = `rgba(80,200,255,${i / 40})`; ctx.beginPath(); ctx.arc(cx + p.x, cy + p.y, 8, 0, Math.PI * 2); ctx.fill(); });
        const pr = state.ring ? r1 : r0;
        ctx.fillStyle = '#4FD1FF'; ctx.beginPath(); ctx.arc(cx + Math.cos(state.angle) * pr, cy + Math.sin(state.angle) * pr, 13, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = '#FFFFFF'; ctx.textAlign = 'center';
        ctx.font = '600 15px -apple-system, system-ui, sans-serif';
        ctx.fillText(state.over ? `Score ${state.score} · tap to play again` : (state.score === 0 ? 'Tap to switch orbit' : ''), cx, h - 48);
      }
      if (bridge) bridge.ready();
      requestAnimationFrame(frame);
    })();
    """#
}
