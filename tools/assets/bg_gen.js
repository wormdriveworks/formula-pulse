#!/usr/bin/env node
/*
 * 무대 배경 생성기 — `bg_spec.json` → `godot/assets/scenecuts/stage_*_{far,near}.png`
 *
 * 소유: 에셋 트랙 (`tools/assets/`) · 신설 IMPL-378 · 사양서 v1.10 §5.1·§5.3
 *
 * ── 왜 별 생성기인가.
 *    배경은 캐릭터·머신과 **파이프라인이 다르다.** 원도 408px 인데 RD 폭 상한이 256 이므로
 *    204 타일을 **가로 2회 반복**해 만들고(`tile_x` 자기 이음 — IMPL-376), 그 결과를
 *    **수평 밴드로 갈라** 원경/근경 2레이어를 얻는다. `quantize.js` 의 파생은 크롭만 알고
 *    타일·밴드를 모르며, 두 레이어는 **의도적으로 알파가 다르므로** 그쪽 기하 잠금·IoU
 *    게이트와 성격이 맞지 않는다. 억지로 얹는 대신 계열 전용 도구를 둔다.
 *
 * ── 무엇을 기계가 보는가.
 *    ⓐ**이음비** — 우단↔좌단 열 차 ÷ 내부 인접 열 평균 차. **1 미만 요구**(v1.10 §5.3 명문).
 *      절대값이 아니라 내부 대비여야 한다 — 원래 변화가 큰 그림은 이음도 크게 나온다.
 *    ⓑ**무손실 분할** — 원경 불투명 + 근경 불투명 = 전체. 겹치거나 빠지면 실패.
 *    ⓒ**조달 대장** — 순색 60 밖 색 0(양자화가 보장하고 스크럽 색도 대장 안에서 고른다).
 *    ⓓ**재현** — `--check` 가 원본+팔레트+원장 → 산출물을 재산출 대조.
 *    ⓔ**비네트**(보고 전용) — 좌우 끝 대역과 중앙 대역의 평균색 차. 25 초과면 ⚠ 를 붙인다.
 *      차단하지 않는 이유는 본문 주석에 있다 — 문면으로 낮출 수는 있고 없앨 수는 없다.
 *      경고 문턱 30 은 5표본 + 육안 경험값이며 유도값이 아니다.
 *
 * ── 무엇을 하지 않는가.
 *    **베이크된 글자를 기계가 찾지 않는다.** 도트 글립은 간판 무늬와 통계적으로 구분되지
 *    않는다(얼굴 자동 검출 기각 IMPL-372 와 같은 성질). 스크럽은 **구획 선언 + 눈 확인**이며
 *    원장의 `scrub` 항이 그 선언이다.
 *
 * 사용:  node tools/assets/bg_gen.js [--check]
 */
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const SPEC = path.join(__dirname, 'bg_spec.json');
const STRIP = path.join(ROOT, 'tools', 'palette', 'master_60_strip.png');
const SRC = path.join(ROOT, 'tools', 'assets', 'rd_raw', 'scenecuts');
const DST = path.join(ROOT, 'godot', 'assets', 'scenecuts');

const KNOWN = new Set(['--check']);
const badFlags = process.argv.slice(2).filter((a) => a.startsWith('-') && !KNOWN.has(a));
if (badFlags.length) { console.error(`FATAL: 미지의 플래그 ${badFlags.join(' ')}`); process.exit(2); }
const CHECK_ONLY = process.argv.includes('--check');
let fails = 0;
const fail = (m) => { fails++; console.log(`  ✗ ${m}`); };
function die(msg) { console.error('FATAL: ' + msg); process.exit(2); }

// ─────────────────────────────────────────────── PNG
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
  if (CH === undefined) die(`${path.basename(file)}: 지원 밖 color type ${ctype} (팔레트 PNG 는 대상 아님)`);
  if (depth !== 8 || inter !== 0) die(`${path.basename(file)}: depth=${depth} interlace=${inter} — 지원 밖`);
  const idat = zlib.inflateSync(Buffer.concat(parts));
  const stride = w * CH;
  if (idat.length !== h * (stride + 1)) die(`${path.basename(file)}: 압축 해제 길이 불일치`);
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

// ─────────────────────────────────────────────── 팔레트 (색값 보유 0)
const strip = decode(STRIP);
const PAL = [];
{
  const seen = new Set();
  for (let i = 0; i < strip.w * strip.h; i++) {
    if (strip.rgba[i * 4 + 3] === 0) continue;
    const k = `${strip.rgba[i * 4]},${strip.rgba[i * 4 + 1]},${strip.rgba[i * 4 + 2]}`;
    if (seen.has(k)) continue;
    seen.add(k);
    PAL.push([strip.rgba[i * 4], strip.rgba[i * 4 + 1], strip.rgba[i * 4 + 2]]);
  }
}
// 스트립은 `swatch_gen.js` 가 `.gpl` 에서 산출하며 고유색이 정확히 60 이어야 한다
// (되읽기 검산 — 총괄 판정 IMPL-161 §1). 그 계약이 깨졌으면 양자화의 기준이 무너진 것이다.
if (PAL.length !== 60) die(`master_60_strip.png 고유색 ${PAL.length} != 60 — 스트립 계약 위반 (swatch_gen.js 재산출 필요)`);

// 지각 거리로 고른다. 단순 RGB 거리는 **피부와 회색을 자주 바꿔치기한다** —
// 인간 시각은 명도에 민감하고 sRGB 는 선형이 아니므로 가중 없이 재면 초상이 회색으로 끌려간다.
const LIN = new Float64Array(256);
for (let i = 0; i < 256; i++) { const v = i / 255; LIN[i] = v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
const lum = (r, g, b) => 0.2126 * LIN[r] + 0.7152 * LIN[g] + 0.0722 * LIN[b];
const PAL_L = PAL.map(([r, g, b]) => lum(r, g, b));
function nearest(r, g, b) {
  const L = lum(r, g, b);
  let best = 0, bd = Infinity;
  for (let i = 0; i < PAL.length; i++) {
    const p = PAL[i];
    const dr = r - p[0], dg = g - p[1], db = b - p[2];
    // 색차(균등 가중) + 명도차(강한 가중). 명도를 우선하면 형태·음영 구조가 살아남는다.
    const d = (dr * dr + dg * dg + db * db) + 24000 * (L - PAL_L[i]) * (L - PAL_L[i]);
    if (d < bd) { bd = d; best = i; }
  }
  return PAL[best];
}

// ─────────────────────────────────────────────── 원장
const spec = JSON.parse(fs.readFileSync(SPEC, 'utf8'));
const SPAL = {};
for (const [k, v] of Object.entries(spec.palette || {})) {
  if (!/^#[0-9A-F]{6}$/.test(v)) die(`palette ${k}: 색 형식 아님 (${v})`);
  const rgb = [1, 3, 5].map((i) => parseInt(v.substr(i, 2), 16));
  if (!PAL.some((p) => p[0] === rgb[0] && p[1] === rgb[1] && p[2] === rgb[2]))
    die(`palette ${k} ${v}: 순색 60 밖 — 스크럽 색도 조달 대장 안에서 고른다`);
  SPAL[k] = rgb;
}

const names = Object.keys(spec.stages || {});
if (!names.length) { console.log('선언된 무대 없음.\n\nBG_GEN PASS stages=0'); process.exit(0); }
console.log(`무대 배경 ${CHECK_ONLY ? '대조' : '렌더'} — ${names.length}무대 · 순색 ${PAL.length}\n`);
if (!CHECK_ONLY) fs.mkdirSync(DST, { recursive: true });

const cache = new Map();
let outCount = 0;

for (const stage of names) {
  const s = spec.stages[stage];
  const srcFile = path.join(SRC, s.tile);
  if (!fs.existsSync(srcFile)) die(`${stage}: 타일 원본 부재 ${s.tile}`);
  const raw = decode(srcFile);
  const W0 = raw.w, H = raw.h;
  const REPEAT = s.repeat === undefined ? 2 : s.repeat;
  if (!Number.isInteger(REPEAT) || REPEAT < 1) die(`${stage}: repeat 은 1 이상 정수다`);
  const W = W0 * REPEAT;

  // ① 양자화 (타일 상태에서 — 픽셀 단위라 반복 전후 결과가 같다)
  const q = Buffer.alloc(W0 * H * 4);
  for (let i = 0; i < W0 * H; i++) {
    if (!raw.rgba[i * 4 + 3]) continue;
    const r = raw.rgba[i * 4], g = raw.rgba[i * 4 + 1], b = raw.rgba[i * 4 + 2];
    const key = (r << 16) | (g << 8) | b;
    let p = cache.get(key);
    if (!p) { p = nearest(r, g, b); cache.set(key, p); }
    q[i * 4] = p[0]; q[i * 4 + 1] = p[1]; q[i * 4 + 2] = p[2]; q[i * 4 + 3] = 255;
  }

  // ② 스크럽 — 베이크된 글자·표지를 주변색으로 덮는다 (구획 선언 · 눈 확인분)
  let scrubbed = 0;
  for (const op of s.scrub || []) {
    if (!Array.isArray(op.rect) || op.rect.length !== 4) die(`${stage}: scrub.rect 은 [x,y,w,h] 다`);
    if (!op.color || !SPAL[op.color]) die(`${stage}: scrub.color '${op.color}' 가 palette 에 없다`);
    const [rx, ry, rw, rh] = op.rect, c = SPAL[op.color];
    if (rx < 0 || ry < 0 || rx + rw > W0 || ry + rh > H) die(`${stage}: scrub 구획이 타일 밖이다 [${op.rect}] (타일 ${W0}×${H})`);
    for (let y = ry; y < ry + rh; y++) for (let x = rx; x < rx + rw; x++) {
      const i = (y * W0 + x) * 4;
      q[i] = c[0]; q[i + 1] = c[1]; q[i + 2] = c[2]; q[i + 3] = 255; scrubbed++;
    }
  }

  // ③ 이음비 — 스크럽 뒤에 잰다. 스크럽이 이음 열을 건드리면 그것도 잡혀야 한다.
  const at = (x, y, c) => q[((y * W0 + x) * 4) + c];
  const colDiff = (x1, x2) => { let t = 0; for (let y = 0; y < H; y++) for (let c = 0; c < 3; c++) t += Math.abs(at(x1, y, c) - at(x2, y, c)); return t / (H * 3); };
  let inner = 0; for (let x = 1; x < W0; x++) inner += colDiff(x - 1, x); inner /= (W0 - 1);
  const seam = colDiff(W0 - 1, 0);
  const ratio = inner > 0 ? seam / inner : 0;
  const need = s.max_seam_ratio === undefined ? 1.0 : s.max_seam_ratio;
  if (ratio >= need) fail(`${stage}: 이음비 ${ratio.toFixed(2)}배 (내부 ${inner.toFixed(2)} · 이음 ${seam.toFixed(2)}) — 요구 ${need} 미만`);

  // ③-2 비네트 계측 — **보고만 하고 차단하지 않는다** (2026-08-24 · IMPL-379).
  //
  //    `tile_x` 는 좌우 끝을 이어야 하므로 **대칭 구도를 만들고**, 2:1 화면비에서 그 대칭이
  //    **아치형 프레이밍**으로 굳는다. 좌우 끝 대역의 평균색이 중앙 대역과 크게 달라지는 것이
  //    그 신호다.
  //
  //    **차단형으로 두지 않는 이유:** 문면으로 심도를 낮출 수는 있으나(미라지 97 → 49 실측)
  //    **없애지는 못한다.** 반비네트·수평 층화 두 문면을 시험해 각각 부분 개선만 얻었고,
  //    아주르는 50 으로 **이미 도달 가능한 하한**이었다. 하한이 허용 대역(≤약 20 — 육안
  //    허용인 알타 16.7·메트로 12.6·돔 19.4 에서 경험적으로 잡았다) 위에 있으므로
  //    차단형으로 두면 납품이 막힌다. **지표를 남기고 판정을 사람에게 넘긴다.**
  const vband = (x0, x1) => { const t = [0, 0, 0]; let n = 0;
    for (let y = 0; y < H; y++) for (let x = x0; x < x1; x++) { const i = (y * W0 + x) * 4; if (!q[i + 3]) continue;
      t[0] += q[i]; t[1] += q[i + 1]; t[2] += q[i + 2]; n++; }
    return n ? t.map((v) => v / n) : [0, 0, 0]; };
  const VB = 24;
  const vl = vband(0, VB), vr = vband(W0 - VB, W0), vc = vband(Math.floor(W0 / 2) - VB / 2, Math.floor(W0 / 2) + VB / 2);
  const cdist = (a, b) => (Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]) + Math.abs(a[2] - b[2])) / 3;
  const vig = Math.max(cdist(vl, vc), cdist(vr, vc));
  // 경고 문턱 30 — **5표본 + 육안으로 잡은 경험값이고 유도값이 아니다.** 양자화 후 실측에서
  // 알타 27.1 은 허용으로 읽혔고 아주르 40.0 은 아니었다(메트로 7.6·돔 22.8 도 허용).
  // 그 사이에 선을 그었다. 표본이 늘면 다시 잡는다.
  const VIG_WARN = 30;

  // ④ 타일 반복 → 408
  const full = Buffer.alloc(W * H * 4);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const si = (y * W0 + (x % W0)) * 4, di = (y * W + x) * 4;
    full[di] = q[si]; full[di + 1] = q[si + 1]; full[di + 2] = q[si + 2]; full[di + 3] = q[si + 3];
  }

  // ⑤ 밴드 분할 — 원경/근경. **수평 절단은 열 관계인 x-랩을 건드릴 수 없다**(v1.10 §5.1).
  const cut = s.split_y;
  if (!Number.isInteger(cut) || cut <= 0 || cut >= H) die(`${stage}: split_y 는 1~${H - 1} 의 정수다`);
  const layers = { far: [0, cut], near: [cut, H] };
  const sig = {};
  for (const [tag, [y0, y1]] of Object.entries(layers)) {
    const buf = Buffer.alloc(W * H * 4);
    let opq = 0;
    for (let y = y0; y < y1; y++) for (let x = 0; x < W; x++) {
      const i = (y * W + x) * 4;
      if (!full[i + 3]) continue;
      buf[i] = full[i]; buf[i + 1] = full[i + 1]; buf[i + 2] = full[i + 2]; buf[i + 3] = 255; opq++;
    }
    sig[tag] = opq;
    const dstFile = path.join(DST, `${stage}_${tag}.png`);
    const label = `${W}×${H} · 불투명 ${opq}px · 밴드 y${y0}..${y1 - 1}`;
    if (CHECK_ONLY) {
      if (!fs.existsSync(dstFile)) { fail(`${stage}_${tag}.png 부재 — 선언만 있고 실물이 없다`); continue; }
      const got = decode(dstFile);
      if (got.w !== W || got.h !== H) { fail(`${stage}_${tag}.png 치수 ${got.w}×${got.h} != ${W}×${H}`); continue; }
      let diff = 0;
      for (let i = 0; i < W * H * 4; i++) if (got.rgba[i] !== buf[i]) diff++;
      if (diff) fail(`${stage}_${tag}.png 가 원본+팔레트+원장 재산출과 다르다 — 바이트 ${diff}개`);
      else { console.log(`  ✓ ${stage}_${tag}.png  ${label}`); outCount++; }
    } else {
      fs.writeFileSync(dstFile, encode(W, H, buf));
      console.log(`  → ${stage}_${tag}.png  ${label}`);
      outCount++;
    }
  }
  // ⑥ 무손실 분할 — 두 레이어가 원본을 정확히 나눈다(겹침·누락 0)
  let total = 0; for (let i = 0; i < W * H; i++) if (full[i * 4 + 3]) total++;
  if (sig.far + sig.near !== total)
    fail(`${stage}: 분할이 무손실이 아니다 — 원경 ${sig.far} + 근경 ${sig.near} = ${sig.far + sig.near} != 전체 ${total}`);
  console.log(`      · 이음비 ${ratio.toFixed(2)}배 · 비네트 ${vig.toFixed(1)}${vig > VIG_WARN ? ' ⚠' : ''} · 분할 y=${cut} · 무손실 ${sig.far}+${sig.near}=${total}` + (scrubbed ? ` · 스크럽 ${scrubbed}px` : ''));
}

console.log('');
if (fails) { console.log(`BG_GEN FAIL fails=${fails}`); process.exit(1); }
console.log(`BG_GEN ${CHECK_ONLY ? 'PASS' : 'OK'} stages=${names.length} files=${outCount}`);
