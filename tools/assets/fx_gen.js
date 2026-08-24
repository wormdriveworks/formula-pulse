#!/usr/bin/env node
/*
 * 연출 요소 생성기 — `fx_spec.json` → `godot/assets/scenecuts/fx_*.png`
 *
 * 소유: 에셋 트랙 (`tools/assets/`) · 신설 IMPL-385 · 사양서 v1.11 §5.2.1
 *
 * ── 이 도구가 존재하는 이유는 파일럿이 기각됐기 때문이다 (IMPL-384).
 *    `rd_animation__vfx` 에 48×32·8프레임을 요청하면 **192×192 4×4 격자(48×48 · 16장)** 가
 *    오고, 그 16장은 **시간 순서가 아니라 서로 독립인 변이**다(불투명 화소 124→299→158,
 *    아크 없음 · 가시비와 크기의 상관 r=0.36 이라 사람이 크기 순으로 세워도 형태가 튄다).
 *    그래서 **루프를 포기하고 변이 집합으로 채택**했다 — 접촉 불꽃은 간헐 발생이므로
 *    루프가 아니어도 성립한다는 연출 판정(사용자 2026-08-24).
 *
 * ── 무엇을 기계가 보는가.
 *    ⓐ**격자 정합** — 셀이 비어 있지 않고, 내용이 셀 경계를 넘지 않는다. 넘으면 합성 시
 *      옆 변이의 파편이 함께 붙는다.
 *    ⓑ**알파 이진** — 0 또는 255 만. **반투명이 한 픽셀이라도 섞이면 순색 60 계약이 깨진다**
 *      (합성 시 배경과 섞인 중간색이 화면에 나오고 그 색은 대장 밖이다). 파일럿 실측은
 *      알파 값이 정확히 2종이었고, 그 성질을 **가정하지 않고 게이트로 받는다.**
 *    ⓒ**조달 대장** — 순색 60 밖 색 0.
 *    ⓓ**중심 안정** — 셀별 무게중심의 산포가 선언 허용 안. **이것이 앵커 선언의 근거다** —
 *      중심이 셀마다 흔들리면 합성 좌표를 한 값으로 적을 수 없다(파일럿 실측 x 2.4 · y 3.4px).
 *    ⓔ**재현** — `--check` 가 원본+팔레트+원장 → 산출물을 재산출 대조.
 *
 * ── 무엇을 하지 않는가.
 *    **프레임 순서를 만들지 않는다.** 16장은 순서가 없고, 없는 순서를 도구가 지어내면
 *    그것은 데이터가 아니라 창작이다. 순서가 필요하면 합성 선언(§5.2.2)이 고른다.
 *
 * ── ⚠ 부채: PNG 코덱·팔레트 블록이 `quantize.js`·`bg_gen.js` 에 이어 **3벌째**다.
 *    통합(`png_io.js` 추출)은 별건으로 남긴다 — 세 도구가 동시에 살아 있는 회차에
 *    공용 모듈을 끼워 넣으면 회귀가 세 곳에서 난다. 부채인 것을 적어 두는 것이
 *    잊는 것보다 낫다.
 *
 * 사용:  node tools/assets/fx_gen.js [--check]
 */
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const SPEC = path.join(__dirname, 'fx_spec.json');
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
console.log(`연출 요소 렌더 — ${Object.keys(spec.elements).length}종 · 순색 60\n`);

for (const [name, e] of Object.entries(spec.elements)) {
  const srcPath = path.join(SRC, e.src);
  if (!fs.existsSync(srcPath)) die(`${name}: 원본 없음 — ${e.src}`);
  const img = decode(srcPath);
  const { w: W, h: H } = img;
  const CW = e.cell[0], CH = e.cell[1];
  if (W % CW || H % CH) die(`${name}: 시트 ${W}×${H} 가 셀 ${CW}×${CH} 로 나뉘지 않는다`);
  const cols = W / CW, rows = H / CH;
  if (cols * rows !== e.frames) die(`${name}: 격자 ${cols}×${rows} = ${cols * rows} 장인데 원장은 ${e.frames} 장이라 적혀 있다`);

  // ⓑ 알파 이진 — 양자화 **전에** 본다. 반투명은 원본의 성질이지 양자화의 산물이 아니다.
  const semi = [];
  for (let i = 0; i < W * H; i++) {
    const a = img.rgba[i * 4 + 3];
    if (a !== 0 && a !== 255) semi.push(a);
  }
  if (semi.length) fail(`${name}: 반투명 ${semi.length}px — 합성 시 배경과 섞인 중간색이 순색 60 밖으로 나온다`);

  // ⓕ 결함색 치환 (`remap`) — **양자화 앞**에서 한다. 양자화 뒤에 하면 이미 대장 안으로
  //    끌려간 색을 다시 만지는 것이 되어 무엇이 결함이고 무엇이 의도인지 구분이 사라진다.
  //    RD 산출물에 **마젠타(`#F904F9`)가 드는 것은 이 프로젝트에서 세 번째**다
  //    (ai_lorentz 번호 · ai_maro 음영 · 본 회차). 색이 정확히 한 값이라 기계로 특정된다.
  //    낡은 선언이 조용히 늙지 않도록 **0회 적중은 즉사**로 받는다(유령 패치 전례).
  const rgba0 = Buffer.from(img.rgba);
  for (const rm of (e.remap || [])) {
    const from = hex(rm.from), to = hex(rm.to);
    let hit = 0;
    for (let i = 0; i < W * H; i++) {
      if (!rgba0[i * 4 + 3]) continue;
      if (rgba0[i * 4] === from[0] && rgba0[i * 4 + 1] === from[1] && rgba0[i * 4 + 2] === from[2]) {
        rgba0[i * 4] = to[0]; rgba0[i * 4 + 1] = to[1]; rgba0[i * 4 + 2] = to[2]; hit++;
      }
    }
    if (!hit) die(`${name}: remap ${rm.from} 이 한 픽셀도 맞지 않았다 — 낡은 선언이다`);
    console.log(`      · remap ${rm.from} → ${rm.to} : ${hit}px${rm.why ? ' (' + rm.why + ')' : ''}`);
  }

  // ⓖ 프레임 선별 (`pick`) — **없는 순서를 만들지는 않지만, 있는 순서에서 고르기는 한다.**
  //    고르는 근거는 원장의 `why` 에 적는다. 취향으로 자르면 다음 편집자가 되돌릴 수 없다.
  let SW = W, SH = H, sheet = rgba0, sc = cols, sr = rows;
  if (e.pick) {
    if (!Array.isArray(e.pick) || !e.pick.length) die(`${name}: pick 은 비지 않은 배열이다`);
    for (const k of e.pick) if (!Number.isInteger(k) || k < 0 || k >= cols * rows) die(`${name}: pick 지표 ${k} 가 격자 밖이다`);
    if (new Set(e.pick).size !== e.pick.length) die(`${name}: pick 에 중복 지표가 있다`);
    sc = e.pick.length; sr = 1; SW = sc * CW; SH = CH;
    sheet = Buffer.alloc(SW * SH * 4);
    e.pick.forEach((k, n) => {
      const kc = k % cols, kr = Math.floor(k / cols);
      for (let y = 0; y < CH; y++) {
        for (let x = 0; x < CW; x++) {
          const si = ((kr * CH + y) * W + (kc * CW + x)) * 4;
          const di = (y * SW + (n * CW + x)) * 4;
          rgba0.copy(sheet, di, si, si + 4);
        }
      }
    });
    console.log(`      · pick [${e.pick.join(',')}] → ${sc}×1 격자`);
  }

  // ⓗ 요소별 팔레트 제외 (`palette_exclude`) — 2026-08-24 신설.
  //
  //    **60색 대장에는 주황과 갈색 사이의 붉은색이 없다.** 온색 16종이 `#E2620F` 다음에
  //    곧장 갈색·자색으로 건너뛰므로, 잉걸의 어두운 붉은 테두리가 **갈 곳이 없어 자색**
  //    (`#C41E7E`·`#6B0F4A`)에 앉는다(실측 73px). 계량의 잘못이 아니라 **팔레트의 빈 자리**다.
  //    지각 가중을 이 에셋만 위해 손대는 것은 **캐릭터·머신 전량이 검증된 계량을 흔드는 일**
  //    이므로 하지 않는다. 대신 **이 요소가 쓸 수 없는 색을 선언**한다 — 불꽃에 자색은 없다.
  //    의미 선언이라 원본 색을 하나씩 열거하는 방식보다 오래 간다(원본이 바뀌어도 유효하다).
  let pal = PAL, palL = PAL_L;
  if (e.palette_exclude) {
    const drop = new Set(e.palette_exclude.map((h) => hex(h).join(',')));
    const known = new Set(PAL.map((c) => c.join(',')));
    for (const d of drop) if (!known.has(d)) die(`${name}: palette_exclude 의 색 #${d} 가 순색 60 안에 없다 — 낡은 선언이다`);
    const keep = [];
    PAL.forEach((c, i) => { if (!drop.has(c.join(','))) keep.push(i); });
    if (keep.length < 8) die(`${name}: 제외 후 남은 색 ${keep.length} — 너무 적다`);
    pal = keep.map((i) => PAL[i]); palL = keep.map((i) => PAL_L[i]);
    console.log(`      · 팔레트 제외 ${drop.size}색 → ${pal.length}색으로 양자화`);
  }
  const pick1 = (r, g, b) => {
    const L = 0.2126 * LIN[r] + 0.7152 * LIN[g] + 0.0722 * LIN[b];
    let best = 0, bd = Infinity;
    for (let i = 0; i < pal.length; i++) {
      const q = pal[i], dr = r - q[0], dg = g - q[1], db = b - q[2];
      const d = (dr * dr + dg * dg + db * db) + 24000 * (L - palL[i]) * (L - palL[i]);
      if (d < bd) { bd = d; best = i; }
    }
    return pal[best];
  };

  // 양자화 (불투명 화소만)
  const out = Buffer.from(sheet);
  let moved = 0, maxd = 0, cset = new Set();
  for (let i = 0; i < SW * SH; i++) {
    if (!out[i * 4 + 3]) { out[i * 4] = 0; out[i * 4 + 1] = 0; out[i * 4 + 2] = 0; continue; }
    const p = pick1(out[i * 4], out[i * 4 + 1], out[i * 4 + 2]);
    const d = Math.hypot(p[0] - out[i * 4], p[1] - out[i * 4 + 1], p[2] - out[i * 4 + 2]);
    if (d > 0) moved++;
    if (d > maxd) maxd = d;
    out[i * 4] = p[0]; out[i * 4 + 1] = p[1]; out[i * 4 + 2] = p[2];
    cset.add(`${p[0]},${p[1]},${p[2]}`);
  }

  // ⓐ 격자 정합 + ⓓ 중심 안정
  const cxs = [], cys = [];
  let empty = 0, bleed = 0;
  const edge = e.edge_margin === undefined ? 1 : e.edge_margin;
  for (let r = 0; r < sr; r++) {
    for (let c = 0; c < sc; c++) {
      let n = 0, sx = 0, sy = 0, touch = 0;
      for (let y = 0; y < CH; y++) {
        for (let x = 0; x < CW; x++) {
          const i = ((r * CH + y) * SW + (c * CW + x)) * 4;
          if (!out[i + 3]) continue;
          n++; sx += x; sy += y;
          if (x < edge || y < edge || x >= CW - edge || y >= CH - edge) touch++;
        }
      }
      if (n === 0) { empty++; continue; }
      if (touch) bleed += touch;
      cxs.push(sx / n); cys.push(sy / n);
    }
  }
  if (empty) fail(`${name}: 빈 셀 ${empty}개 — 격자 선언이 실물과 다르다`);
  if (bleed) fail(`${name}: 셀 가장자리 ${edge}px 안에 화소 ${bleed}개 — 합성 시 옆 변이의 파편이 함께 붙는다`);
  const spanX = Math.max(...cxs) - Math.min(...cxs);
  const spanY = Math.max(...cys) - Math.min(...cys);
  const tol = e.center_tolerance === undefined ? 6 : e.center_tolerance;
  if (spanX > tol || spanY > tol) {
    fail(`${name}: 중심 산포 x ${spanX.toFixed(1)} · y ${spanY.toFixed(1)} > 허용 ${tol} — 앵커를 한 값으로 선언할 수 없다`);
  }

  const dstPath = path.join(DST, name + '.png');
  const png = encode(SW, SH, out);
  if (CHECK_ONLY) {
    if (!fs.existsSync(dstPath)) fail(`${name}: 산출물 없음`);
    else if (!fs.readFileSync(dstPath).equals(png)) fail(`${name}: 재산출 불일치 — 원본·팔레트·원장에서 같은 그림이 나오지 않는다`);
  } else {
    if (fails > 0) { console.log(`  ✗ ${name}: 실패 — 파일을 쓰지 않는다`); continue; }
    fs.writeFileSync(dstPath, png);
    console.log(`  → ${name}.png  ${SW}×${SH} · ${sc}×${sr} 격자 · 셀 ${CW}×${CH}`);
  }
  console.log(`      · 고유색 ${cset.size} · 이동 ${moved}px(최대 ${maxd.toFixed(1)}) · 중심 산포 ${spanX.toFixed(1)}×${spanY.toFixed(1)}px · 반투명 ${semi.length}`);
}

if (fails) { console.log(`\nFX_GEN ${CHECK_ONLY ? 'CHECK ' : ''}FAIL fails=${fails}`); process.exit(1); }
console.log(`\nFX_GEN ${CHECK_ONLY ? 'PASS' : 'OK'} elements=${Object.keys(spec.elements).length}`);
