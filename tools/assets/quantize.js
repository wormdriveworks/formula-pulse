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
 * ── 패치 단계 (IMPL-337 신설) — 사양서 §2.3 ④ 수작업이 사는 자리.
 *    양자화 뒤에 `pixel_patch.json` 의 편집을 적용한다. **왜 파일이 아니라 데이터로 두는가:**
 *    산출물을 손으로 고치면 `--check`(원본+팔레트 → 산출물 재산출 대조)가 즉시 깨진다.
 *    그러면 선택지가 둘인데 둘 다 나쁘다 — 검사를 끄거나, 원본을 고쳐 "원본"을 거짓으로 만드는 것.
 *    편집을 **좌표·색으로 적어 두면** 세 번째 길이 열린다: `--check` 가 *원본 + 팔레트 + 패치*
 *    → 산출물을 재산출해 대조하므로 **수작업이 재현 계약 안에 들어온다.**
 *    부수 이득이 더 크다 — 손으로 무엇을 고쳤는지가 **읽을 수 있는 기록**으로 남는다
 *    (`icon_art.json` 이 도상을 ASCII 로 둔 것과 같은 규율: *"PNG 바이트만 남기면 다음
 *    편집자가 읽을 수 없고 재현도 못 한다"*).
 *
 * ── 무엇을 하지 않는가 (검증한 척하지 않는다)
 *    **무엇을 고쳐야 하는지 판정하지 않는다.** 패치 내용은 눈이 정하고 본 도구는 적용·대조만 한다.
 *    양자화가 형태를 뭉갰는지도 판정하지 않는다 — 그래서 원본을 지우지 않고 남긴다.
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
const PATCH_FILE = path.join(__dirname, 'pixel_patch.json');
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

// ─────────────────────────────────────────────── 패치 (사양서 §2.3 ④)
// 키 = "<산출 디렉토리명>/<파일명>" — 캐릭터·머신이 같은 원장을 쓰되 섞이지 않게 한다.
let PATCH = { palette: {}, patches: {} };
if (fs.existsSync(PATCH_FILE)) PATCH = JSON.parse(fs.readFileSync(PATCH_FILE, 'utf8'));
const PPAL = {};
for (const [k, v] of Object.entries(PATCH.palette || {})) {
  if (!/^#[0-9A-F]{6}$/.test(v)) die(`pixel_patch palette ${k}: 색 형식 아님 (${v})`);
  // 패치 색도 순색 60 안이어야 한다 — 손으로 고친 픽셀이 대장을 빠져나가면 양자화가 무의미해진다.
  if (!PAL.some((p) => p[0] === parseInt(v.substr(1, 2), 16) && p[1] === parseInt(v.substr(3, 2), 16) && p[2] === parseInt(v.substr(5, 2), 16)))
    die(`pixel_patch palette ${k} ${v}: 순색 60 밖 — 패치도 조달 대장 안에서만 고른다`);
  PPAL[k] = [1, 3, 5].map((i) => parseInt(v.substr(i, 2), 16));
}
const DST_TAG = path.basename(path.resolve(DST));
// ── 숫자 3×5 (`digits` op) — 2026-08-23 신설 · IMPL-347.
//
// **왜 패치에 숫자가 들어오는가.** `vh8_behemoth_base_side` 가 정본 No.18 대신 **13** 을 달고
// 나왔다(RD 에 `number 18` 을 넣고 받은 결과). 13 은 보레아스 번호이므로 서로 다른 두 차가
// 같은 번호를 단다 — 정본 저촉이고 방치할 수 없다.
//
// **`pixel_patch.json` 의 "형태를 만드는 일은 패치가 아니다" 와 어긋나지 않는다.** 그 문장은
// ax9 바퀴 시도에서 나왔고, 바퀴는 둥근 실루엣·상단광·허브를 눈으로 맞춰야 하는 **작화**였다.
// 3×5 숫자는 **선언된 폰트에서 나오는 결정적 렌더**이고 덮기까지 기계가 센다(`covers`) —
// 눈이 정하는 것은 자리 하나뿐이다. 판단의 축은 "손으로 그리는가"가 아니라 **"재현되는가"** 다.
//
// 폰트는 `overlay_gen.js` 와 같은 자형이다 — 같은 셀에서 같은 숫자가 두 자형으로 나오면
// 세컨드 리버리를 얹었을 때 번호만 서체가 갈린다.
const FONT35 = {
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

function applyDigits(name, w, h, put, d) {
  const { text, at, color, outline, covers } = d;
  if (!/^[0-9]{1,3}$/.test(String(text))) die(`patch ${name}: digits.text 는 1~3자리 숫자다 (${text})`);
  if (!Array.isArray(at) || at.length !== 2) die(`patch ${name}: digits.at 은 [x,y] 다`);
  if (!outline) die(`patch ${name}: digits 는 outline 선언을 요구한다 — 배경 명도를 모르는 자리다`);
  if (!Array.isArray(covers) || covers.length !== 4) die(`patch ${name}: digits 는 covers [x,y,w,h] 선언을 요구한다 — 옛 번호를 덮는 것이 본체다`);
  const glyph = new Set();
  let gx = at[0];
  for (const ch of String(text)) {
    FONT35[ch].forEach((row, dy) => { [...row].forEach((c, dx) => { if (c === '#') glyph.add(`${gx + dx},${at[1] + dy}`); }); });
    gx += 4;                                          // 3 + 1 공백
  }
  // 외곽선 먼저(8-이웃 한 겹), 그 위에 심색. 글리프 3×5 상자가 전부 불투명해진다.
  const ring = new Set();
  for (const k of glyph) {
    const [x, y] = k.split(',').map(Number);
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      const kk = `${x + dx},${y + dy}`;
      if (!glyph.has(kk)) ring.add(kk);
    }
  }
  for (const k of ring) { const [x, y] = k.split(',').map(Number); put(x, y, outline); }
  for (const k of glyph) { const [x, y] = k.split(',').map(Number); put(x, y, color); }
  // **덮기 검증** — 우연히 덮는 것과 계약으로 덮는 것은 다르다. 자형·자리·자릿수가 바뀌면
  // 우연은 조용히 깨지고 차에 번호가 두 개 남는다.
  const [cx, cy, cw, chh] = covers;
  let uncovered = 0;
  for (let y = cy; y < cy + chh; y++) for (let x = cx; x < cx + cw; x++) {
    if (!glyph.has(`${x},${y}`) && !ring.has(`${x},${y}`)) uncovered++;
  }
  if (uncovered) die(`patch ${name}: 옛 번호 자리 ${uncovered}/${cw * chh}px 가 덮이지 않았다 — 번호가 두 개 남는다`);
}

function applyPatch(name, w, h, buf) {
  const spec = (PATCH.patches || {})[`${DST_TAG}/${name}`];
  if (!spec) return 0;
  let touched = 0;
  const put = (x, y, key) => {
    if (x < 0 || y < 0 || x >= w || y >= h) die(`patch ${name}: 캔버스 밖 (${x},${y})`);
    const i = (y * w + x) * 4;
    if (key === '.') { buf[i] = buf[i + 1] = buf[i + 2] = buf[i + 3] = 0; touched++; return; }
    const c = PPAL[key];
    if (!c) die(`patch ${name}: palette 에 없는 색 키 '${key}'`);
    buf[i] = c[0]; buf[i + 1] = c[1]; buf[i + 2] = c[2]; buf[i + 3] = 255; touched++;
  };
  for (const op of spec.ops || []) {
    if (op.rect) { const [x, y, rw, rh] = op.rect; for (let dy = 0; dy < rh; dy++) for (let dx = 0; dx < rw; dx++) put(x + dx, y + dy, op.color); }
    else if (op.set) { for (const [x, y] of op.set) put(x, y, op.color); }
    else if (op.digits) applyDigits(name, w, h, put, op.digits);
    else die(`patch ${name}: op 에 rect·set·digits 가 없다`);
  }
  return touched;
}
// 원장에만 있고 대상이 없는 패치 = 유령 패치. 조용히 늙지 않게 한다.
const patchKeys = Object.keys(PATCH.patches || {}).filter((k) => k.startsWith(DST_TAG + '/'));

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
  const patched = applyPatch(f, img.w, img.h, out);
  if (patched) { after.clear(); for (let i = 0; i < img.w * img.h; i++) if (out[i * 4 + 3]) after.add((out[i * 4] << 16) | (out[i * 4 + 1] << 8) | out[i * 4 + 2]); }
  const dstFile = path.join(DST, f);
  const tag = `${img.w}×${img.h} · 고유색 ${before.size} → ${after.size}` + (patched ? ` · 패치 ${patched}px` : '');
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

for (const k of patchKeys) { const base = k.slice(DST_TAG.length + 1); if (!files.includes(base)) fail(`유령 패치: ${k} — 대상 파일이 없다`); }

console.log('');
if (fails) { console.log(`QUANTIZE FAIL fails=${fails}`); process.exit(1); }
console.log(`QUANTIZE ${CHECK_ONLY ? 'PASS' : 'OK'} files=${files.length} palette=${PAL.length} patches=${patchKeys.length}`);
