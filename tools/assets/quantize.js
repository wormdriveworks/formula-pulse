#!/usr/bin/env node
/*
 * 마스터 팔레트 양자화 — 생성 원본(RD 산출) → 조달 대장 안의 색으로만 이루어진 원도
 *
 * 소유: 에셋 트랙 (`tools/assets/`) · 신설 IMPL-315
 * 사양서 §2.3 ③ 단계 · 운용지침 §4.3 "생성 후 경로"의 국소 구현
 *
 * ── 왜 API(`palette_converter`) 가 아니라 여기서 하는가.
 *    운용지침 §4.3 은 `palette_converter`(무료) 또는 `input_palette` 두 경로를 두고
 *    **생성 후 경로를 권고**한다(원본을 남긴 채 되돌릴 수 있어서). 그 권고는 그대로 따르되
 *    구현을 국소로 옮긴 이유가 둘 있다.
 *
 *    ⓐ **`run_edit_tool` 은 결과를 base64 로 인라인 반환한다.** 캐릭터 47장·머신 37장
 *       규모에서 180×240 PNG 를 왕복마다 base64 로 받으면 대화 문맥이 산출물로 가득 찬다 —
 *       도구가 못 쓰게 되는 것이 아니라 **회차가 못 굴러간다.**
 *    ⓑ **재현이 명령 한 줄이 된다.** API 양자화는 결과 PNG 만 남고 *어떻게* 가 남지 않는다.
 *       여기서 하면 `--check` 가 원본 + 팔레트에서 같은 바이트가 나오는지 대조할 수 있다
 *       (`icon_draw.js`·`frame_gen.js` 와 같은 규율 — **재현되는 것만 커밋한다**).
 *
 *    **바뀌지 않는 것:** 팔레트의 출처는 여전히 `tools/palette/master_60_strip.png`(순색 60)
 *    이고 이 파일은 색값을 하나도 갖지 않는다. 디더는 끈다(운용지침 §4.3 — 자동 디더는
 *    도트 그리드를 깨서 수작업량을 늘린다).
 *
 * ── 무엇을 하지 않는가 (검증한 척하지 않는다)
 *    **믹셀 제거·윤곽 정리(사양서 §2.3 ④)를 하지 않는다.** 그 단계는 명시적으로 수작업이며,
 *    본 도구는 색만 옮긴다. 양자화가 형태를 뭉갰는지도 판정하지 않는다 — 그것은 눈 소관이고,
 *    그래서 원본을 지우지 않고 남긴다(되돌릴 수 있어야 원인을 분리할 수 있다).
 *
 * 사용:  node tools/assets/quantize.js <원본디렉토리> <출력디렉토리>
 *        node tools/assets/quantize.js <원본디렉토리> <출력디렉토리> --check
 */
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const STRIP = path.join(ROOT, 'tools', 'palette', 'master_60_strip.png');

const KNOWN = new Set(['--check']);
const args = process.argv.slice(2);
const bad = args.filter((a) => a.startsWith('-') && !KNOWN.has(a));
if (bad.length) { console.error(`FATAL: 미지의 플래그 ${bad.join(' ')} — 알려진 것은 ${[...KNOWN].join(' ')}`); process.exit(2); }
const CHECK_ONLY = args.includes('--check');
const [SRC, DST] = args.filter((a) => !a.startsWith('-'));
function die(msg) { console.error('FATAL: ' + msg); process.exit(2); }
if (!SRC || !DST) die('사용: quantize.js <원본디렉토리> <출력디렉토리> [--check]');

let fails = 0;
const fail = (msg) => { fails++; console.log(`  ✗ ${msg}`); };

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

// ─────────────────────────────────────────────── 주행
const files = fs.readdirSync(SRC).filter((f) => f.endsWith('.png')).sort();
if (files.length === 0) die(`${SRC} 에 PNG 가 없다`);
if (!CHECK_ONLY) fs.mkdirSync(DST, { recursive: true });
console.log(`팔레트 양자화 ${CHECK_ONLY ? '대조' : '집행'} — ${files.length}파일 · 순색 ${PAL.length}\n`);

const cache = new Map();
for (const f of files) {
  const img = decode(path.join(SRC, f));
  const out = Buffer.alloc(img.w * img.h * 4);
  const before = new Set(), after = new Set();
  for (let i = 0; i < img.w * img.h; i++) {
    const a = img.rgba[i * 4 + 3];
    if (a === 0) continue;                       // 투명은 건드리지 않는다 (컷아웃 보존)
    const r = img.rgba[i * 4], g = img.rgba[i * 4 + 1], b = img.rgba[i * 4 + 2];
    const key = (r << 16) | (g << 8) | b;
    before.add(key);
    let p = cache.get(key);
    if (!p) { p = nearest(r, g, b); cache.set(key, p); }
    out[i * 4] = p[0]; out[i * 4 + 1] = p[1]; out[i * 4 + 2] = p[2]; out[i * 4 + 3] = 255;
    after.add((p[0] << 16) | (p[1] << 8) | p[2]);
  }
  const dstFile = path.join(DST, f);
  const tag = `${img.w}×${img.h} · 고유색 ${before.size} → ${after.size}`;
  if (CHECK_ONLY) {
    if (!fs.existsSync(dstFile)) { fail(`${f} 산출물 부재 — 원본만 있고 결과가 없다`); continue; }
    const got = decode(dstFile);
    if (got.w !== img.w || got.h !== img.h) { fail(`${f} 치수 ${got.w}×${got.h} != ${img.w}×${img.h}`); continue; }
    let diff = 0;
    for (let i = 0; i < img.w * img.h * 4; i++) if (got.rgba[i] !== out[i]) diff++;
    if (diff) fail(`${f} 가 원본+팔레트 재산출과 다르다 — 바이트 ${diff}개 (한쪽만 고쳐졌다)`);
    else console.log(`  ✓ ${f}  ${tag}`);
  } else {
    fs.writeFileSync(dstFile, encode(img.w, img.h, out));
    console.log(`  → ${f}  ${tag}`);
  }
}

console.log('');
if (fails) { console.log(`QUANTIZE FAIL fails=${fails}`); process.exit(1); }
console.log(`QUANTIZE ${CHECK_ONLY ? 'PASS' : 'OK'} files=${files.length} palette=${PAL.length}`);
