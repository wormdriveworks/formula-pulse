#!/usr/bin/env node
/*
 * 대형 원도 생성기 — `kv_spec.json` → `illustrations/` · `backgrounds/` · `store/` · `platform/`
 *
 * ── 이름은 키 비주얼에서 시작했으나 **다루는 것은 대형 원도 계열 전부**다(키 비주얼 2 · 배경 4 ·
 *    스토어 리프레임 7 · 부트 스플래시 · 후속 전용 CG 6). 셋이 같은 문제를 갖기 때문이다 —
 *    **RD 상한 384 보다 큰 원도를 정수배로만 얻어야 한다.** 파일을 나누면 코덱이 다섯 벌째가 된다.
 *
 * 소유: 에셋 트랙 (`tools/assets/`) · 신설 IMPL-412 · D15 §2.2 · D10 §6.4
 *
 * ── 왜 생성기인가. 정본이 스토어 소재를 **"키 비주얼 리프레임 — 신규 원도 0"** 으로 못박았다
 *    (D15 §2.2-5·§2.6·§3.1). 리프레임이 손 작업이면 **원도가 바뀔 때 9건이 조용히 갈린다.**
 *    선언으로 두면 원도 한 번 고치고 다시 돌리면 끝이고, `--check` 가 그 일치를 계약으로 만든다.
 *
 * ── 합성을 **1× 에서 한다**. 이것이 이 도구의 유일한 설계 결정이다.
 *    파일럿이 답한 것은 *"화소 밀도가 맞는가"* 였고 답은 **"부품이 같은 배수면 정의상 맞는다"**
 *    였다(IMPL-410). 그러므로 합성은 **320×180 원판**에서 하고 가로·세로·캡슐은 전부
 *    **그 한 장의 정수배 확대 + 크롭**으로 낸다 — **배수를 한 곳에서만 정하면 갈릴 수 없다.**
 *    비정수 배율은 쓰지 않는다(도트 격자가 깨진다 — 지침 §5.2).
 *
 * ── 세로판(360×780)은 크롭만으로 안 된다.
 *    원판 비율이 16:9 라 어떤 크롭도 780 높이를 못 준다. 그래서 **가장자리 행 반복으로
 *    하늘과 노면을 잇는다** — 둘 다 가로로 균일한 대역이라 반복이 형태를 만들지 않는다.
 *    **형태가 있는 대역(그랜드스탠드·머신)은 절대 반복 구간에 넣지 않는다** — 선언이 그것을 막는다.
 *
 * ── 무엇을 기계가 보는가.
 *    ⓐ**순색 60** — 합성 결과 전체가 대장 안. 부품이 각각 대장 안이어도 **그림자·확장이 밖으로 나갈 수 있다.**
 *    ⓑ**정수배 전속** — 선언된 배수가 정수가 아니면 즉사.
 *    ⓒ**크롭 유효** — 크롭 사각이 원본 밖으로 나가면 즉사(조용히 자르지 않는다).
 *    ⓓ**반복 구간 균일성** — 세로 확장에 쓰는 가장자리 행의 색 변화가 문턱 이하인지 잰다.
 *      **반복이 형태를 만들면 그것은 확장이 아니라 창작이다.**
 *    ⓔ**재현** — `--check` 가 원본+선언 → 산출물 전건 바이트 대조.
 *    ⓕ**바탕과의 상이성** — `distinct_from` 을 선언한 산출물이 그 바탕과 얼마나 다른지 잰다.
 *      **컷인이 자기 뒤에 이미 깔린 그림이면 화면에서 사라진다** — ㊸ 집행에서 실물로 만난 결함이다.
 *
 * 사용:  node tools/assets/kv_gen.js [--check]
 */
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const SPEC = path.join(__dirname, 'kv_spec.json');
const STRIP = path.join(ROOT, 'tools', 'palette', 'master_60_strip.png');
// 게이트 ⓕ 하한 — 형제 실측에서 도출(구속 형제 cg06 = 95.09% · 결함 = 23.77%/0.00%).
const DISTINCT_MIN = 80;

const KNOWN = new Set(['--check']);
const badFlags = process.argv.slice(2).filter((a) => a.startsWith('-') && !KNOWN.has(a));
if (badFlags.length) { console.error(`FATAL: 미지의 플래그 ${badFlags.join(' ')}`); process.exit(2); }
const CHECK_ONLY = process.argv.includes('--check');
let fails = 0;
const fail = (m) => { fails++; console.log(`  ✗ ${m}`); };
function die(msg) { console.error('FATAL: ' + msg); process.exit(2); }
function hex(h) {
  const m = /^#?([0-9a-fA-F]{6})$/.exec(String(h));
  if (!m) die(`색 표기 '${h}' 가 #RRGGBB 가 아니다`);
  const v = parseInt(m[1], 16);
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
}
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
// ─────────────────────────────────────────────── 본체
const spec = JSON.parse(fs.readFileSync(SPEC, 'utf8'));
const abs = (p) => path.join(ROOT, p);
const PALSET = new Set(PAL.map((c) => c.join(',')));

function inPal(rgba, w, h, label) {
  const bad = new Map();
  for (let i = 0; i < w * h; i++) {
    if (!rgba[i * 4 + 3]) continue;
    const k = `${rgba[i * 4]},${rgba[i * 4 + 1]},${rgba[i * 4 + 2]}`;
    if (!PALSET.has(k)) bad.set(k, (bad.get(k) || 0) + 1);
  }
  if (bad.size) fail(`${label}: 순색 60 밖 ${bad.size}색 (${[...bad].slice(0, 3).map(([k, n]) => `${k}×${n}`).join(' ')})`);
}

// ── 1× 원판 합성 — **출력마다 다른 원판을 가질 수 있다** (2026-08-25 · IMPL-418).
//    키 비주얼은 원판 하나에서 10건이 나왔지만 **전용 CG 는 장면마다 배경이 다르다.**
//    그래서 `compose` 를 출력 단위로 선언할 수 있게 열되, **없으면 전역 원판을 쓴다** —
//    한 장에서 여럿이 나오는 구조(키 비주얼)를 깨지 않는다.
function buildBase(cfg, label) {
  const bg = decode(abs(cfg.background));
  const W = bg.w, H = bg.h;
  const out = Buffer.from(bg.rgba);
  {
    const seen = new Set();
    let moved = 0;
    for (let i = 0; i < W * H; i++) {
      if (!out[i * 4 + 3]) continue;
      const p = nearest(out[i * 4], out[i * 4 + 1], out[i * 4 + 2]);
      if (p[0] !== out[i * 4] || p[1] !== out[i * 4 + 1] || p[2] !== out[i * 4 + 2]) moved++;
      out[i * 4] = p[0]; out[i * 4 + 1] = p[1]; out[i * 4 + 2] = p[2];
      seen.add(p.join(','));
    }
    console.log(`      · ${label} 배경 양자화 ${W}×${H} · 고유색 ${seen.size} · 이동 ${moved}px`);
  }
  const put = (x, y, c) => {
    if (x < 0 || y < 0 || x >= W || y >= H) return;
    const i = (y * W + x) * 4;
    out[i] = c[0]; out[i + 1] = c[1]; out[i + 2] = c[2]; out[i + 3] = 255;
  };
  for (const sh of (cfg.shadows || [])) {
    const c = hex(sh.color);
    if (!PALSET.has(c.join(','))) die(`${label} shadow: ${sh.color} 이 순색 60 밖이다`);
    const [cx, cy] = sh.at, [rx, ry] = sh.radius;
    const [keep, period] = sh.dither || [1, 4];
    let n = 0;
    for (let y = cy - ry; y <= cy + ry; y++) for (let x = cx - rx; x <= cx + rx; x++) {
      const dx = (x - cx) / rx, dy = (y - cy) / ry;
      if (dx * dx + dy * dy > 1) continue;
      if ((x * 3 + y * 5) % period >= keep) continue;
      put(x, y, c); n++;
    }
    if (!n) die(`${label} shadow: 한 픽셀도 그리지 않았다 — 좌표가 틀렸다`);
    console.log(`      · ${label} 접지 그림자 ${n}px`);
  }
  for (const pt of (cfg.parts || [])) {
    const img = decode(abs(pt.src));
    const [ox, oy] = pt.at;
    let drawn = 0, outside = 0;
    for (let y = 0; y < img.h; y++) for (let x = 0; x < img.w; x++) {
      const si = (y * img.w + x) * 4;
      if (!img.rgba[si + 3]) continue;
      const X = ox + x, Y = oy + y;
      if (X < 0 || Y < 0 || X >= W || Y >= H) { outside++; continue; }
      put(X, Y, [img.rgba[si], img.rgba[si + 1], img.rgba[si + 2]]);
      drawn++;
    }
    if (!drawn) die(`${label} part ${pt.src}: 한 픽셀도 그려지지 않았다`);
    if (outside > 0 && !pt.allow_crop) fail(`${label} part ${pt.src}: ${outside}px 가 화면 밖이다 — 잘림을 허용하려면 allow_crop 을 선언해야 한다`);
    console.log(`      · ${label} ${path.basename(pt.src)} ${drawn}px${outside ? ` (밖 ${outside}px · 선언된 잘림)` : ''}`);
  }
  inPal(out, W, H, `${label} 1× 원판`);
  return { buf: out, w: W, h: H };
}
const baseMain = spec.base ? buildBase({ ...spec.base, shadows: spec.shadows, parts: spec.parts }, '주') : null;
let W = baseMain ? baseMain.w : 0, H = baseMain ? baseMain.h : 0;
const out = baseMain ? baseMain.buf : Buffer.alloc(0);
// ── 파생: 정수배 확대 → 크롭 → (선택) 가장자리 행 반복
function scaleUp(src, w, h, k) {
  const W2 = w * k, H2 = h * k;
  const b = Buffer.alloc(W2 * H2 * 4);
  for (let y = 0; y < H2; y++) for (let x = 0; x < W2; x++) {
    const si = (Math.floor(y / k) * w + Math.floor(x / k)) * 4;
    src.copy(b, (y * W2 + x) * 4, si, si + 4);
  }
  return { buf: b, w: W2, h: H2 };
}
function rowVariance(buf, w, y) {
  let mn = [255, 255, 255], mx = [0, 0, 0];
  for (let x = 0; x < w; x++) for (let c = 0; c < 3; c++) {
    const v = buf[(y * w + x) * 4 + c];
    if (v < mn[c]) mn[c] = v;
    if (v > mx[c]) mx[c] = v;
  }
  return Math.max(mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]);
}

let made = 0;
for (const o of spec.outputs) {
  // `source` — 합성 원판이 아닌 다른 산출물에서 파생할 때 쓴다. **왜 필요한가:**
  //    대장 §6.2 는 `store/` 를 *"전량 키 비주얼 리프레임"* 으로 적었으나 **사양서 §11 은
  //    Android 스토어 아이콘 512 를 13 데칼 헬멧 모티프로 규정한다** — 앱 아이콘이 장면
  //    크롭이면 48px 에서 무너지므로 §11 이 맞다. **한 문장이 전량을 덮으려다 예외를 삼킨 것**이고
  //    도구가 그 예외를 표현할 수 있어야 대장을 고칠 수 있다.
  let src = out, sw = W, sh = H;
  if (o.compose) {
    const b = buildBase(o.compose, path.basename(o.file, '.png'));
    src = b.buf; sw = b.w; sh = b.h;
  }
  if (o.source) {
    const si = decode(abs(o.source));
    src = Buffer.from(si.rgba); sw = si.w; sh = si.h;
    // `quantize` — **명시 선언이다.** 원본이 이미 순색 60 인 산출물(아이콘·머신)이면 다시
    //    양자화하는 것이 무의미하고, RD 원판이면 반드시 거쳐야 한다. **조용히 알아서 하지 않는다** —
    //    자동으로 두면 '대장 밖 색이 있었는데 도구가 지웠다'와 '애초에 없었다'가 구분되지 않는다.
    if (o.quantize) {
      const seen = new Set();
      for (let i = 0; i < sw * sh; i++) {
        if (!src[i * 4 + 3]) continue;
        const p = nearest(src[i * 4], src[i * 4 + 1], src[i * 4 + 2]);
        src[i * 4] = p[0]; src[i * 4 + 1] = p[1]; src[i * 4 + 2] = p[2];
        seen.add(p.join(','));
      }
      console.log(`      · ${path.basename(o.source)} 양자화 · 고유색 ${seen.size}`);
    }
  }
  const k = o.scale === undefined ? 1 : o.scale;
  if (!Number.isInteger(k) || k < 1 || k > 12) die(`${o.file}: scale 은 1~12 의 정수다 — 비정수 배율은 도트 격자를 깬다`);
  const up = scaleUp(src, sw, sh, k);
  const [cx, cy, cw, ch] = o.crop;
  if (cx < 0 || cy < 0 || cx + cw > up.w || cy + ch > up.h) {
    die(`${o.file}: 크롭 [${o.crop}] 이 ${up.w}×${up.h} 밖이다 — 조용히 자르지 않는다`);
  }
  const ext = o.extend || null;
  const outH = ch + (ext ? ext.top + ext.bottom : 0);
  const b = Buffer.alloc(cw * outH * 4);
  const copyRow = (srcY, dstY) => {
    for (let x = 0; x < cw; x++) {
      const si = ((cy + srcY) * up.w + (cx + x)) * 4;
      up.buf.copy(b, (dstY * cw + x) * 4, si, si + 4);
    }
  };
  if (ext) {
    // **반복 구간 균일성 검사** — 반복이 형태를 만들면 확장이 아니라 창작이다.
    const lim = ext.max_variance === undefined ? 24 : ext.max_variance;
    // **실제로 반복되는 가장자리만 잰다.** 1차는 위·아래를 무조건 검사해서
    //    확장이 0 인 쪽까지 걸었다 — 쓰이지 않는 것을 재는 게이트는 통과를 막기만 한다.
    const edges = [];
    if (ext.top > 0) edges.push([0, '상단']);
    if (ext.bottom > 0) edges.push([ch - 1, '하단']);
    for (const [srcY, tag] of edges) {
      const v = rowVariance(up.buf, up.w, cy + srcY);
      if (v > lim) fail(`${o.file}: ${tag} 반복 행의 색 변화 ${v} > 허용 ${lim} — 형태가 있는 행을 반복하려 한다`);
    }
    for (let y = 0; y < ext.top; y++) copyRow(0, y);
    for (let y = 0; y < ch; y++) copyRow(y, ext.top + y);
    for (let y = 0; y < ext.bottom; y++) copyRow(ch - 1, ext.top + ch + y);
  } else {
    for (let y = 0; y < ch; y++) copyRow(y, y);
  }
  // `overlays` — **확대 뒤에 얹는 부품.** 스탠딩(180×240)은 1× 캔버스(320×180)에 들어가지
  //    않으므로 원판 합성에 넣을 수 없다. 확대 뒤 640×360 에 1× 그대로 얹으면
  //    **배경은 굵고 인물은 선명한 초점 분리**가 되고, VN 합성 실측에서 그것이 오히려 옳았다.
  for (const ov of (o.overlays || [])) {
    const img = decode(abs(ov.src));
    const [ox, oy] = ov.at;
    let drawn = 0, outside = 0;
    for (let y = 0; y < img.h; y++) for (let x = 0; x < img.w; x++) {
      const si = (y * img.w + x) * 4;
      if (!img.rgba[si + 3]) continue;
      const X = ox + x, Y = oy + y;
      if (X < 0 || Y < 0 || X >= cw || Y >= outH) { outside++; continue; }
      const di = (Y * cw + X) * 4;
      img.rgba.copy(b, di, si, si + 4);
      b[di + 3] = 255;
      drawn++;
    }
    if (!drawn) die(`${o.file}: overlay ${ov.src} 가 한 픽셀도 그려지지 않았다`);
    if (outside > 0 && !ov.allow_crop) fail(`${o.file}: overlay ${ov.src} 가 ${outside}px 화면 밖이다 — allow_crop 선언 필요`);
    console.log(`      · overlay ${path.basename(ov.src)} ${drawn}px${outside ? ` (밖 ${outside}px)` : ''}`);
  }
  inPal(b, cw, outH, o.file);
  // ⓕ **바탕과의 상이성** — 컷인이 *자기 뒤에 이미 깔린 그림*이면 화면에서 사라진다.
  //    ㊸ 집행에서 실물로 만난 결함이다: `cg05` 는 배경이 `garage_320`(= `garage_h` 의 원판·
  //    같은 배수·같은 크롭)이라 **초상 오버레이만 지우면 산출이 `garage_h` 와 바이트 동일**해지고,
  //    그 `garage_h` 가 **바로 이 비트의 VN 바탕**이다(`vn_backdrops.csv` `vnbg_crew_sasha`).
  //    즉 판정을 문면대로 감산으로 집행하면 **상이율 0.00%** 의 투명한 컷인이 조용히 납품된다.
  //    **문턱은 추측이 아니라 형제에서 도출했다** (garage_h 대비 상이 화소율 실측):
  //      cg01 99.31 · cg02 97.94 · cg03 97.38 · cg04 97.31 · cg06 95.09  ← 구속 형제 = cg06
  //      결함 = cg05 23.77 (초상판) / 0.00 (감산판)
  //    95.09 와 23.77 사이는 **71점 간극**이라 문턱 위치가 예민하지 않다 — 80 으로 둔다.
  //    상이율만 재고 *무엇이 다른가*는 재지 않는다(그것은 눈의 몫이다 — §9-⑦).
  if (o.distinct_from) {
    const ref = abs(o.distinct_from);
    if (!fs.existsSync(ref)) die(`${o.file}: distinct_from ${o.distinct_from} 이 없다`);
    const r = decode(ref);
    if (r.w !== cw || r.h !== outH) {
      die(`${o.file}: distinct_from 치수 불일치 ${r.w}×${r.h} ≠ ${cw}×${outH} — 같은 자리에 그려지는 것끼리만 비교한다`);
    }
    let d = 0;
    for (let i = 0; i < cw * outH; i++) {
      for (let c = 0; c < 4; c++) if (b[i * 4 + c] !== r.rgba[i * 4 + c]) { d++; break; }
    }
    const pct = 100 * d / (cw * outH);
    if (pct < DISTINCT_MIN) {
      fail(`${o.file}: ${path.basename(o.distinct_from)} 과 상이율 ${pct.toFixed(2)}% < 하한 ${DISTINCT_MIN}% — 컷인이 자기 바탕과 같아 화면에서 사라진다`);
    }
    console.log(`      · ${path.basename(o.file)} vs ${path.basename(o.distinct_from)} 상이율 ${pct.toFixed(2)}%`);
  }
  const png = encode(cw, outH, b);
  const dst = abs(o.file);
  if (CHECK_ONLY) {
    if (!fs.existsSync(dst)) fail(`${o.file}: 산출물 없음`);
    else if (!fs.readFileSync(dst).equals(png)) fail(`${o.file}: 재산출 불일치`);
  } else {
    if (fails > 0) { console.log(`  ✗ ${o.file}: 앞선 실패로 쓰지 않는다`); continue; }
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.writeFileSync(dst, png);
    console.log(`  → ${o.file}  ${cw}×${outH}  ×${k}${ext ? ` · 확장 ↑${ext.top} ↓${ext.bottom}` : ''}`);
  }
  made++;
}
if (fails) { console.log(`\nKV_GEN ${CHECK_ONLY ? 'CHECK ' : ''}FAIL fails=${fails}`); process.exit(1); }
console.log(`\nKV_GEN ${CHECK_ONLY ? 'PASS' : 'OK'} outputs=${made}`);
