#!/usr/bin/env node
/*
 * 검수 시트 — 에셋 여러 장을 한 장의 대조 시트로 묶는다.
 *
 * 소유: 에셋 트랙 (`tools/assets/`) · 신설 IMPL-394 · 눈 검수 백로그 지원
 *
 * ── 왜 도구인가. 검수 대상이 138장이고 **회차가 반복된다**(고치면 다시 본다).
 *    매번 손으로 합성 스크립트를 쓰면 배율·배경·순서가 회차마다 달라지고,
 *    그러면 **이번에 보인 것이 저번에도 보였는지 알 수 없다.** 시트를 도구로 두면
 *    회차 간 비교가 성립한다.
 *
 * ── 배경색을 고정한 이유. 투명 에셋은 **배경에 따라 다르게 보인다** — 밝은 배경에서
 *    사라지는 획이 어두운 배경에서는 보인다. 검수 배경은 실기 정조에 가까운
 *    어두운 청회색 하나로 고정하고, 필요하면 `--bg` 로 바꾸되 **대장에 적는다.**
 *
 * 사용:  node tools/assets/review_sheet.js --out <png> [--scale N] [--cols N] [--bg RRGGBB] <파일|합성>...
 *        합성 = `base.png+overlay.png` (겹쳐 그린다 — 오버레이는 단독으로 보면 판정이 서지 않는다)
 */
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');
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


// ─────────────────────────────────────────────── 본체
const argv = process.argv.slice(2);
let OUT = null, SCALE = 3, COLS = 0, BG = [0x14, 0x18, 0x22];
const items = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--out') OUT = argv[++i];
  else if (a === '--scale') SCALE = parseInt(argv[++i], 10);
  else if (a === '--cols') COLS = parseInt(argv[++i], 10);
  else if (a === '--bg') { const m = /^#?([0-9a-fA-F]{6})$/.exec(argv[++i]); if (!m) die('--bg 는 RRGGBB'); const v = parseInt(m[1], 16); BG = [(v >> 16) & 255, (v >> 8) & 255, v & 255]; }
  else if (a.startsWith('-')) die(`미지의 플래그 ${a}`);
  else items.push(a);
}
if (!OUT) die('--out 이 필요하다');
if (!items.length) die('대상이 없다');
if (!Number.isInteger(SCALE) || SCALE < 1 || SCALE > 12) die('--scale 은 1~12');

const cells = items.map((spec, n) => {
  const parts = spec.split('+');
  const layers = parts.map((p) => { if (!fs.existsSync(p)) die(`없는 파일 ${p}`); return decode(p); });
  const w = Math.max(...layers.map((l) => l.w)), h = Math.max(...layers.map((l) => l.h));
  for (const l of layers) if (l.w !== w || l.h !== h) die(`${spec}: 합성 대상 치수가 다르다 (${l.w}×${l.h} vs ${w}×${h})`);
  const buf = Buffer.alloc(w * h * 4);
  for (const l of layers) for (let i = 0; i < w * h; i++) if (l.rgba[i * 4 + 3]) l.rgba.copy(buf, i * 4, i * 4, i * 4 + 4);
  const label = parts.map((p) => path.basename(p, '.png')).join(' + ');
  console.log(`${String(n).padStart(3)}  ${w}×${h}  ${label}`);
  return { w, h, buf };
});

const cols = COLS > 0 ? COLS : Math.ceil(Math.sqrt(cells.length));
const rows = Math.ceil(cells.length / cols);
const PAD = 6;
const colW = [], rowH = [];
cells.forEach((c, i) => {
  const cx = i % cols, cy = Math.floor(i / cols);
  colW[cx] = Math.max(colW[cx] || 0, c.w * SCALE);
  rowH[cy] = Math.max(rowH[cy] || 0, c.h * SCALE);
});
const W = colW.reduce((a, b) => a + b, 0) + PAD * (cols + 1);
const H = rowH.reduce((a, b) => a + b, 0) + PAD * (rows + 1);
const out = Buffer.alloc(W * H * 4);
for (let i = 0; i < W * H; i++) { out[i * 4] = BG[0]; out[i * 4 + 1] = BG[1]; out[i * 4 + 2] = BG[2]; out[i * 4 + 3] = 255; }
const xoff = []; let acc = PAD;
for (let c = 0; c < cols; c++) { xoff[c] = acc; acc += colW[c] + PAD; }
const yoff = []; acc = PAD;
for (let r = 0; r < rows; r++) { yoff[r] = acc; acc += rowH[r] + PAD; }
cells.forEach((c, i) => {
  const cx = i % cols, cy = Math.floor(i / cols);
  const ox = xoff[cx] + Math.floor((colW[cx] - c.w * SCALE) / 2);
  const oy = yoff[cy] + Math.floor((rowH[cy] - c.h * SCALE) / 2);
  for (let y = 0; y < c.h * SCALE; y++) {
    for (let x = 0; x < c.w * SCALE; x++) {
      const si = (Math.floor(y / SCALE) * c.w + Math.floor(x / SCALE)) * 4;
      if (!c.buf[si + 3]) continue;
      const di = ((oy + y) * W + (ox + x)) * 4;
      c.buf.copy(out, di, si, si + 4);
      out[di + 3] = 255;
    }
  }
});
fs.writeFileSync(OUT, encode(W, H, out));
console.log(`\nREVIEW_SHEET ${OUT}  ${W}×${H}  ${cells.length}칸 · ${cols}열 · ${SCALE}배`);
