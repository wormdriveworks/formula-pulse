#!/usr/bin/env node
/*
 * 머신 오버레이 생성기 — `overlay_spec.json` → `godot/assets/machines/*.png`
 *
 * 소유: 에셋 트랙 (`tools/assets/`) · 신설 IMPL-341
 * 사양서 §4.1 *"베이스와 동일 셀 크기·좌표 정합 (런타임 레이어 합성 — 사전 조합 금지, G-M3)"*
 *
 * ── 왜 이 도구가 있는가.
 *    오버레이는 **정합이 규격**이다. RD 는 파츠를 분리해 내지 못하고(`supports_reference_images`
 *    false — 5회 확인) 좌표 작화는 차 밖으로 새기 쉽다. 그래서 형태를 좌표로 선언하되
 *    **베이스의 불투명 마스크와 교집합**한다:
 *
 *      오버레이 픽셀 = 선언한 형태 ∩ 베이스 실루엣
 *
 *    이 한 줄이 두 가지를 공짜로 준다. ⓐ**차 밖으로 절대 새지 않는다**(맹목 좌표 작화의 최대
 *    위험이 구조적으로 제거된다) ⓑ**좌표 정합이 자동**이다 — 오버레이가 베이스에서 파생되므로
 *    같은 셀·같은 좌표계라는 계약이 선언이 아니라 구성으로 성립한다.
 *
 * ── 음영을 베이스에서 빌린다 (`ramp`).
 *    평평한 띠를 음영 있는 보디에 얹으면 붙여 놓은 것처럼 보인다. 그래서 오버레이 색을
 *    **베이스 픽셀의 명도로 골라** 램프에서 뽑는다 — 띠가 보디의 음영을 그대로 따라간다.
 *    즉 형태만 선언하고 **명암은 베이스가 준다.**
 *
 * ── 실루엣 교집합은 "차 안"을 보장하고 "차체 위"를 보장하지 않는다 (2026-08-23 실측).
 *    첫 회차의 플랭크 스트라이프는 **점선 노이즈로 부서졌다.** 원인을 재니 밴드 y40..42 의
 *    **74~78% 가 타이어·하부 그림자 픽셀**이었다 — 실루엣 안이지만 도장면이 아니다. 그래서
 *    `paint_floor` 를 둔다: 명도가 그 값 이상인 베이스 픽셀만 도장면으로 본다. 프라이비티어는
 *    고유색 18 이 전건 무채라 명도 분포에 **0.39 → 0.45 의 빈 구간**이 있고(타이어 최대 0.24)
 *    그 골에 문턱을 놓으면 오검출 없이 갈린다.
 *
 * ── 연결성 게이트 — 부서짐을 기계가 잡는다.
 *    점선 결함은 "잉크 0" 검사로 잡히지 않는다(잉크는 있었다). 그래서 형태 op 마다
 *    **최대 연결 성분 / 총 잉크**를 재고 문턱 미만이면 실패시킨다. 띠가 띠로 읽히려면
 *    거의 한 덩이여야 한다는 것이 규격이고, 그것은 셀 수 있다.
 *
 * ── 다중 베이스 교집합 (`base` 배열).
 *    보레아스 리버리는 3종 도색 × 2시점 = 6파일이고 **성장 3단계 전체에 얹힌다**(단계별 파일이
 *    아니다 — 대장 §4.5 계수). 단계마다 실루엣이 다르므로 s3 에만 맞추면 s1 에서 차 밖에
 *    칠해진다. `base` 를 배열로 주면 **전 베이스의 교집합**을 마스크로 쓴다 — 어느 단계에
 *    얹어도 밖으로 나가지 않는다.
 *
 * ── 무엇을 하지 않는가 (검증한 척하지 않는다)
 *    도색이 **보기 좋은지 판정하지 않는다** — 형태 선언의 옳음은 눈 소관이다.
 *    베이스가 바뀌면 오버레이도 바뀐다(마스크가 베이스에서 온다) — 그것이 의도이고,
 *    `--check` 가 그 동기화를 강제한다.
 *
 * 사용:  node tools/assets/overlay_gen.js           (렌더)
 *        node tools/assets/overlay_gen.js --check    (대조만 · 불일치 시 exit 1)
 */
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const SPEC = path.join(__dirname, 'overlay_spec.json');
const STRIP = path.join(ROOT, 'tools', 'palette', 'master_60_strip.png');
const ASSETS = path.join(ROOT, 'godot', 'assets');

const KNOWN = new Set(['--check']);
const bad = process.argv.slice(2).filter((a) => a.startsWith('-') && !KNOWN.has(a));
if (bad.length) { console.error(`FATAL: 미지의 플래그 ${bad.join(' ')} — 알려진 것은 ${[...KNOWN].join(' ')}`); process.exit(2); }
const CHECK_ONLY = process.argv.includes('--check');

let fails = 0;
const fail = (msg) => { fails++; console.log(`  ✗ ${msg}`); };
function die(msg) { console.error('FATAL: ' + msg); process.exit(2); }

// ─────────────────────────────────────────────────── PNG
function decode(file) {
  const buf = fs.readFileSync(file);
  if (buf.readUInt32BE(0) !== 0x89504e47) die(`${file}: PNG 아님`);
  const parts = [];
  let o = 8, w = 0, h = 0, depth = 8, ctype = -1, inter = 0;
  while (o + 8 <= buf.length) {
    const len = buf.readUInt32BE(o);
    const type = buf.toString('ascii', o + 4, o + 8);
    const data = buf.slice(o + 8, o + 8 + len);
    if (type === 'IHDR') { w = data.readUInt32BE(0); h = data.readUInt32BE(4); depth = data[8]; ctype = data[9]; inter = data[12]; }
    if (type === 'IDAT') parts.push(data);
    if (type === 'IEND') break;
    o += 12 + len;
  }
  const CH = { 0: 1, 2: 3, 4: 2, 6: 4 }[ctype];
  if (CH === undefined || depth !== 8 || inter !== 0) die(`${path.basename(file)}: 지원 밖 (ctype=${ctype} depth=${depth})`);
  const idat = zlib.inflateSync(Buffer.concat(parts));
  const stride = w * CH;
  const px = Buffer.alloc(h * stride);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < h; y++) {
    const f = idat[y * (stride + 1)];
    const cur = Buffer.from(idat.slice(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
    for (let i = 0; i < stride; i++) {
      const a = i >= CH ? cur[i - CH] : 0, b = prev[i], c = i >= CH ? prev[i - CH] : 0;
      let v = cur[i];
      if (f === 1) v += a; else if (f === 2) v += b; else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c); }
      else if (f !== 0) die(`${path.basename(file)}: 미지의 필터 ${f}`);
      cur[i] = v & 0xff;
    }
    cur.copy(px, y * stride);
    prev = cur;
  }
  const rgba = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    let r, g, b, a = 255;
    if (ctype === 6) { r = px[i * 4]; g = px[i * 4 + 1]; b = px[i * 4 + 2]; a = px[i * 4 + 3]; }
    else if (ctype === 2) { r = px[i * 3]; g = px[i * 3 + 1]; b = px[i * 3 + 2]; }
    else if (ctype === 4) { r = g = b = px[i * 2]; a = px[i * 2 + 1]; }
    else { r = g = b = px[i]; }
    rgba[i * 4] = r; rgba[i * 4 + 1] = g; rgba[i * 4 + 2] = b; rgba[i * 4 + 3] = a;
  }
  return { w, h, rgba };
}
function crc32(buf) {
  let c, t = crc32.t;
  if (!t) { t = crc32.t = []; for (let i = 0; i < 256; i++) { c = i; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[i] = c >>> 0; } }
  c = 0xffffffff;
  for (const b of buf) c = t[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function encode(w, h, rgba) {
  const stride = w * 4;
  const raw = Buffer.alloc(h * (stride + 1));
  for (let y = 0; y < h; y++) { raw[y * (stride + 1)] = 0; rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride); }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

// ─────────────────────────────────────────────────── 조달 대장 (색값 보유 0)
const strip = decode(STRIP);
const LEDGER = new Set();
for (let i = 0; i < strip.w * strip.h; i++) {
  if (!strip.rgba[i * 4 + 3]) continue;
  LEDGER.add(`${strip.rgba[i * 4]},${strip.rgba[i * 4 + 1]},${strip.rgba[i * 4 + 2]}`);
}
if (LEDGER.size !== 60) die(`master_60_strip.png 고유색 ${LEDGER.size} != 60 — 스트립 계약 위반`);

const spec = JSON.parse(fs.readFileSync(SPEC, 'utf8'));
const PAL = {};
for (const [k, v] of Object.entries(spec.palette || {})) {
  if (!/^#[0-9A-F]{6}$/.test(v)) die(`palette ${k}: 색 형식 아님 (${v})`);
  const rgb = [1, 3, 5].map((i) => parseInt(v.substr(i, 2), 16));
  if (!LEDGER.has(rgb.join(','))) die(`palette ${k} ${v}: 순색 60 밖 — 오버레이도 조달 대장 안에서만 고른다`);
  PAL[k] = rgb;
}

// ─────────────────────────────────────────────────── 형태
const LIN = new Float64Array(256);
for (let i = 0; i < 256; i++) { const v = i / 255; LIN[i] = v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
const lum = (r, g, b) => 0.2126 * LIN[r] + 0.7152 * LIN[g] + 0.0722 * LIN[b];

function inShape(sh, x, y, w, h) {
  if (sh.band) {
    const { axis, from, to } = sh.band;
    return axis === 'y' ? (y >= from && y <= to) : (x >= from && x <= to);
  }
  if (sh.rect) { const [rx, ry, rw, rh] = sh.rect; return x >= rx && y >= ry && x < rx + rw && y < ry + rh; }
  if (sh.diag) {
    // a·x + b·y ∈ [from, to] — 대각 띠. 궤적 라인·아크의 기본형.
    const { a, b, from, to } = sh.diag;
    const v = a * x + b * y;
    return v >= from && v <= to;
  }
  if (sh.ring) {
    const { cx, cy, inner, outer } = sh.ring;
    const d = Math.hypot(x - cx, y - cy);
    return d >= inner && d <= outer;
  }
  die(`형태에 band·rect·diag·ring 중 하나가 없다`);
}

// ─────────────────────────────────────────────────── 숫자 3×5
// 카 넘버는 리버리의 내용이다(사양서 A-MC-10·12·13 — 카 넘버 2·81·51·24·77).
// 3×5 는 이 셀에서 두 자리가 7×5 로 앉는 최소 폭이고, 16px 배지 숫자(IMPL-317)와 같은 규격이다.
const FONT = {
  '0': ['###', '#.#', '#.#', '#.#', '###'],
  '1': ['.#.', '##.', '.#.', '.#.', '###'],
  '2': ['###', '..#', '###', '#..', '###'],
  '3': ['###', '..#', '###', '..#', '###'],
  '4': ['#.#', '#.#', '###', '..#', '..#'],
  '5': ['###', '#..', '###', '..#', '###'],
  '6': ['###', '#..', '###', '#.#', '###'],
  '7': ['###', '..#', '..#', '..#', '..#'],
  '8': ['###', '#.#', '###', '#.#', '###'],
  '9': ['###', '#.#', '###', '..#', '..#'],
};

// 최대 연결 성분 / 총 잉크 — 형태가 한 덩이로 읽히는지의 기계 판정.
function largestComponent(px, w, h) {
  const seen = new Uint8Array(w * h);
  let best = 0;
  const stack = [];
  for (let s0 = 0; s0 < w * h; s0++) {
    if (!px[s0] || seen[s0]) continue;
    let n = 0;
    stack.push(s0); seen[s0] = 1;
    while (stack.length) {
      const i = stack.pop(); n++;
      const x = i % w, y = (i - x) / w;
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        const j = ny * w + nx;
        if (px[j] && !seen[j]) { seen[j] = 1; stack.push(j); }
      }
    }
    if (n > best) best = n;
  }
  return best;
}

// ─────────────────────────────────────────────────── 주행
const names = Object.keys(spec.overlays || {});
if (names.length === 0) { console.log('선언된 오버레이 없음.\n\nOVERLAY_GEN PASS overlays=0'); process.exit(0); }
console.log(`머신 오버레이 ${CHECK_ONLY ? '대조' : '렌더'} — ${names.length}종 · 조달 대장 ${LEDGER.size}색\n`);

for (const name of names) {
  const o = spec.overlays[name];
  const baseList = Array.isArray(o.base) ? o.base : [o.base];
  const bases = baseList.map((b) => {
    const f = path.join(ASSETS, b);
    if (!fs.existsSync(f)) die(`${name}: 베이스 부재 ${b}`);
    return decode(f);
  });
  const failsBefore = fails;
  const { w, h } = bases[0];
  for (const b of bases) if (b.w !== w || b.h !== h) die(`${name}: 베이스 치수 불일치 — 오버레이는 동일 셀 계약이다`);

  // 마스크 = 전 베이스 불투명의 **교집합**. 어느 베이스에 얹어도 밖으로 나가지 않는다.
  const mask = new Uint8Array(w * h);
  for (let i = 0; i < w * h; i++) mask[i] = bases.every((b) => b.rgba[i * 4 + 3] > 0) ? 1 : 0;

  const out = Buffer.alloc(w * h * 4);
  const enc = (i) => (0.2126 * bases[0].rgba[i * 4] + 0.7152 * bases[0].rgba[i * 4 + 1] + 0.0722 * bases[0].rgba[i * 4 + 2]) / 255;

  // 도장면 = 실루엣 ∩ 명도 문턱. **실루엣만으로는 타이어·하부 그림자가 함께 들어온다** —
  // 첫 회차의 스트라이프가 그렇게 점선으로 부서졌다(밴드의 74~78%가 타이어였다).
  const floor = o.paint_floor;
  const paint = new Uint8Array(w * h);
  let paintN = 0;
  if (floor !== undefined) {
    if (typeof floor !== 'number' || floor <= 0 || floor >= 1) die(`${name}: paint_floor 는 0~1 의 수여야 한다`);
    for (let i = 0; i < w * h; i++) if (mask[i] && enc(i) >= floor) { paint[i] = 1; paintN++; }
    if (paintN === 0) die(`${name}: paint_floor ${floor} 에서 도장면 0 — 문턱이 베이스 최명부보다 높다`);
  }
  const region = (scope) => {
    if (scope === 'paint') {
      if (floor === undefined) die(`${name}: on:"paint" 는 paint_floor 선언을 요구한다`);
      return paint;
    }
    if (scope === undefined || scope === 'silhouette') return mask;
    die(`${name}: on 은 "paint" 또는 "silhouette" 다 (받은 값 ${scope})`);
  };
  const rampOf = (keys) => keys.map((k) => { if (!PAL[k]) die(`${name}: palette 에 없는 색 키 '${k}'`); return PAL[k]; });
  const put = (i, c) => { const fresh = out[i * 4 + 3] === 0; out[i * 4] = c[0]; out[i * 4 + 1] = c[1]; out[i * 4 + 2] = c[2]; out[i * 4 + 3] = 255; return fresh; };

  const ops = o.ops || (o.shapes || []).map((sh) => ({ shape: sh, ramp: sh.ramp }));
  if (!ops.length) die(`${name}: ops 가 없다`);
  let ink = 0;

  for (const op of ops) {
    // ── 색 치환 층 — 베이스 자기 픽셀을 명도로 목표 램프에 사상한다.
    //    형태를 만들지 않으므로 필치가 갈리지 않는다(§4.1 벽을 우회하는 유일한 기제 ·
    //    IMPL-163 결정적 색 치환 전례 · 총괄 판정 ① 승인분).
    if (op.recolor) {
      const ramp = rampOf(op.recolor.ramp);
      if (floor === undefined) die(`${name}: recolor 는 paint_floor 선언을 요구한다`);
      // 문턱 위 명도를 [floor,1] 에서 램프로 펴 준다 — 문턱을 그냥 자르면 전 픽셀이 최암단에 몰린다.
      let n = 0;
      for (let i = 0; i < w * h; i++) {
        if (!paint[i]) continue;
        const t = (enc(i) - floor) / (1 - floor);
        const idx = Math.min(ramp.length - 1, Math.floor(t * ramp.length));
        if (put(i, ramp[idx])) ink++;
        n++;
      }
      console.log(`      · 색 치환 ${n}px (문턱 ${floor})`);
      continue;
    }

    // ── 숫자 — 외곽선을 강제한다. 베이스가 어두울지 밝을지 모르는 자리에 놓이므로
    //    심색만으로는 판독이 배경에 좌우된다(AX-9 1번이 가늘어 안 읽힌 관측 · IMPL-335 ⓑ).
    if (op.digits) {
      const { text, at, color, outline, covers } = op.digits;
      if (!/^[0-9]{1,3}$/.test(String(text))) die(`${name}: digits.text 는 1~3자리 숫자다 (${text})`);
      if (!Array.isArray(at) || at.length !== 2) die(`${name}: digits.at 은 [x,y] 다`);
      if (!outline) die(`${name}: digits 는 outline 선언을 요구한다 — 배경 명도를 모르는 자리다`);
      const fg = rampOf([color])[0], bg = rampOf([outline])[0];
      const glyph = new Uint8Array(w * h);
      let gx = at[0];
      for (const ch of String(text)) {
        FONT[ch].forEach((row, dy) => { [...row].forEach((c, dx) => { if (c === '#') glyph[(at[1] + dy) * w + gx + dx] = 1; }); });
        gx += 4;                                     // 3 + 1 공백
      }
      let drawn = 0, out_of = 0;
      // 외곽선 먼저 — 8-이웃으로 한 겹. 그 위에 심색.
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const i = y * w + x;
        if (glyph[i]) continue;
        let touch = false;
        for (let dy = -1; dy <= 1 && !touch; dy++) for (let dx = -1; dx <= 1; dx++) {
          const nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          if (glyph[ny * w + nx]) { touch = true; break; }
        }
        if (touch && mask[i]) { if (put(i, bg)) ink++; }
      }
      for (let i = 0; i < w * h; i++) if (glyph[i]) { if (mask[i]) { if (put(i, fg)) ink++; drawn++; } else out_of++; }
      if (out_of) fail(`${name}: 숫자 ${text} 의 ${out_of}px 가 실루엣 밖이다 — 좌표를 확인하라`);

      // ── 덮기 검증 (`covers`) — 세컨드 리버리는 **기존 번호를 지우는 일**이 본체다.
      //    외곽선이 결과적으로 옛 번호를 덮기는 하지만, **우연히 덮는 것과 계약으로 덮는 것은
      //    다르다.** 폰트·자리·자릿수가 바뀌면 우연은 조용히 깨지고 차에 번호가 두 개 남는다.
      //    그래서 옛 번호의 자리를 원장에 적고(총괄 판정 ② 눈 등재분) 전 픽셀이 불투명해졌는지
      //    기계가 센다. 이것이 눈으로 읽은 좌표를 재현 계약 안에 넣는 방법이다.
      if (covers) {
        if (!Array.isArray(covers) || covers.length !== 4) die(`${name}: digits.covers 는 [x,y,w,h] 다`);
        const [cx, cy, cw, chh] = covers;
        let uncovered = 0, inMask = 0;
        for (let y = cy; y < cy + chh; y++) for (let x = cx; x < cx + cw; x++) {
          if (x < 0 || y < 0 || x >= w || y >= h) die(`${name}: covers 가 셀 밖으로 나간다`);
          const i = y * w + x;
          if (!mask[i]) continue;                    // 실루엣 밖은 덮을 것이 없다
          inMask++;
          if (out[i * 4 + 3] === 0) uncovered++;
        }
        if (inMask === 0) die(`${name}: covers 구획이 실루엣과 만나지 않는다 — 좌표가 틀렸다`);
        if (uncovered) fail(`${name}: 옛 번호 자리 ${uncovered}/${inMask}px 가 덮이지 않았다 — 번호가 두 개 남는다`);
        else console.log(`      · 덮기 검증 ${inMask}/${inMask}px (옛 번호 ${cw}×${chh} @(${cx},${cy}))`);
      }
      console.log(`      · 번호 ${text} @(${at[0]},${at[1]}) ${drawn}px 심 + 외곽선`);
      continue;
    }

    // ── 형태 (띠·대각·링·사각) — 음영은 베이스가 준다.
    const sh = op.shape;
    if (!sh) die(`${name}: op 에 recolor·digits·shape 중 하나가 없다`);
    const scope = region(op.on);
    const ramp = rampOf(op.ramp || sh.ramp);
    const hit = new Uint8Array(w * h);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const i = y * w + x;
      if (!scope[i]) continue;
      if (!inShape(sh, x, y, w, h)) continue;
      hit[i] = 1;
    }
    let n = 0;
    for (let i = 0; i < w * h; i++) if (hit[i]) n++;
    if (n === 0) { fail(`${name}: 형태 잉크 0 — 형태가 도장면과 만나지 않는다 (좌표·on 확인)`); continue; }

    // 램프 선택은 먼저 하고 게이트는 그 결과로 잰다 — 게이트가 재야 하는 것은 **판독**이지 형태가 아니다.
    const pick = new Int32Array(w * h).fill(-1);
    for (let i = 0; i < w * h; i++) {
      if (!hit[i]) continue;
      // 부호화 명도로 램프를 고른다 — 선형 휘도는 어두운 쪽에 몰려 램프가 통짜로 어두워진다.
      pick[i] = Math.min(ramp.length - 1, Math.floor(enc(i) * ramp.length));
    }

    // ── 판독 게이트 (2026-08-23 교정 — 첫 회차의 실패를 기계가 잡게 한 축).
    //    **형태의 연결성은 이 결함을 잡지 못했다** — 첫 스트라이프는 최대 성분 100% 였고
    //    그래도 점선으로 보였다. 이유: 램프가 베이스 명도로 골라지므로 타이어처럼 어두운
    //    픽셀 위에서는 오버레이 색이 베이스와 거의 같아진다. 형태는 이어져 있고 **판독이
    //    끊긴다.** 그래서 게이트는 |ΔL| ≥ delta 인 픽셀만 판독으로 세고, 그 판독 집합의
    //    최대 연결 성분을 본다. 재는 대상을 형태에서 판독으로 옮긴 것이 교정의 요점이다.
    const delta = op.min_delta === undefined ? 0.12 : op.min_delta;
    const read = new Uint8Array(w * h);
    let readN = 0;
    for (let i = 0; i < w * h; i++) {
      if (pick[i] < 0) continue;
      const c = ramp[pick[i]];
      const Lo = (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255;
      // **기준은 이 픽셀이 실제로 덮는 것이다.** 앞선 op(색 치환)이 이미 칠한 자리라면
      // 판독은 베이스가 아니라 그 색과의 대비로 결정된다 — 베이스로 재면 주황 위의 띠를
      // 회색 베이스와 비교해 엉뚱한 통과·탈락이 난다.
      const under = out[i * 4 + 3]
        ? (0.2126 * out[i * 4] + 0.7152 * out[i * 4 + 1] + 0.0722 * out[i * 4 + 2]) / 255
        : enc(i);
      if (Math.abs(Lo - under) >= delta) { read[i] = 1; readN++; }
    }
    const need = op.min_contiguity === undefined ? 0.80 : op.min_contiguity;
    const big = readN ? largestComponent(read, w, h) : 0;
    if (readN / n < need || big / n < need) {
      fail(`${name}: 형태가 판독으로 부서진다 — 판독 ${readN}/${n} = ${(readN / n * 100).toFixed(0)}% · 최대 성분 ${big}/${n} = ${(big / n * 100).toFixed(0)}% (요구 ${(need * 100).toFixed(0)}% · ΔL≥${delta})`);
      continue;
    }
    for (let i = 0; i < w * h; i++) if (pick[i] >= 0 && put(i, ramp[pick[i]])) ink++;
    console.log(`      · 형태 ${n}px · 판독 ${(readN / n * 100).toFixed(0)}% · 최대 성분 ${(big / n * 100).toFixed(0)}%`);
  }
  if (ink === 0) fail(`${name}: 잉크 0`);

  const dstFile = path.join(ASSETS, o.dir || 'machines', name + '.png');
  const tag = `${w}×${h} · 잉크 ${ink} · 마스크 ${baseList.length}베이스 교집합`;
  // **실패한 오버레이는 쓰지 않는다.** 실패를 산출물로 남기면 다음 회차가 그것을 실물로 읽고,
  // 게이트가 잡은 결함이 조용히 리포지토리에 들어앉는다.
  if (fails > failsBefore) { console.log(`  ✗ ${name}: 실패 — 파일을 쓰지 않는다`); continue; }
  if (CHECK_ONLY) {
    if (!fs.existsSync(dstFile)) { fail(`${name}.png 부재 — 선언만 있고 실물이 없다`); continue; }
    const got = decode(dstFile);
    if (got.w !== w || got.h !== h) { fail(`${name}.png 치수 ${got.w}×${got.h} != ${w}×${h}`); continue; }
    let diff = 0;
    for (let i = 0; i < w * h * 4; i++) if (got.rgba[i] !== out[i]) diff++;
    if (diff) fail(`${name}.png 가 선언과 다르다 — 바이트 ${diff}개 (베이스가 바뀌었거나 한쪽만 고쳐졌다)`);
    else console.log(`  ✓ ${name}.png  ${tag}`);
  } else {
    fs.mkdirSync(path.dirname(dstFile), { recursive: true });
    fs.writeFileSync(dstFile, encode(w, h, out));
    console.log(`  → ${name}.png  ${tag}`);
  }
}

console.log('');
if (fails) { console.log(`OVERLAY_GEN FAIL fails=${fails}`); process.exit(1); }
console.log(`OVERLAY_GEN ${CHECK_ONLY ? 'PASS' : 'OK'} overlays=${names.length}`);
