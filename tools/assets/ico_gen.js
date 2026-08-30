#!/usr/bin/env node
/*
 * Windows ICO 세트 생성기 — `icon_master_128.png` → `godot/assets/platform/icon_win.ico`
 *
 * 소유: 에셋 트랙 (`tools/assets/`) · 신설 IMPL-502 · 대장 §6.1 · 사양서 §11 · D15 §2.2
 * 발주 = `docs/handoff/윈도우빌드_총괄회신.md` §4 ①(총괄 IMPL-499 · 제출물 마감 3건 중 에셋 몫)
 *
 * ── 왜 도구인가. 원판이 한 장이고 산출이 네 크기다. 손으로 뽑으면 **원판이 바뀔 때 네 벌이
 *    조용히 갈린다** — `kv_gen.js` 가 스토어 소재에서 답한 것과 같은 문제다. `--check` 가
 *    원판 → 산출을 재산출해 대조하므로 **재현되는 것만 커밋한다**는 규율이 여기서도 선다.
 *
 * ── 크기는 우리 취향이 아니라 Windows 셸 규약이다(16 작은 아이콘 · 32 · 48 보통 아이콘 ·
 *    256 큰/특대). 그래서 선언 파일로 빼지 않고 상수로 둔다 — **선언 파일에 두면 "조정해도
 *    되는 값"으로 읽힌다.**
 *
 * ── 축소는 니어리스트 전속(발주 규약 · 지침 §5.2). 평균·쌍선형은 도트 격자를 깨고
 *    **대장 밖 색을 만든다** — 순색 60 계약이 여기서 무너진다. 니어리스트는 원본 화소를
 *    고를 뿐 섞지 않으므로 **팔레트 정합이 자료 구조의 성질**이 된다(게이트 ⓒ는 이중 안전장치).
 *
 * ── ⚠ 착수 전 가설이 실측에서 뒤집혔다 — 기록해 둔다.
 *    비정수 배율(128÷48 = 2.667)이 48 을 깰 것이라 보고 대안을 준비했다. **아니었다.**
 *    네 후보를 12배로 확대해 나란히 놓고 보니 **'13' 데칼이 가장 잘 읽히는 것이 48** 이고,
 *    깨지는 것은 **정수 배율인 32**(÷4)였다 — 표본 간격이 고른 것과 자형이 살아남는 것은
 *    다른 사실이고, 실제로 자형을 정하는 것은 **화소 예산**이다.
 *    그리고 그 판독마저 확대의 산물이었다: **1:1 로 다시 놓으니 32 는 "틀린 숫자"가 아니라
 *    "표지가 있는 헬멧"으로 읽힌다.** 아이콘은 확대해서 쓰는 물건이 아니므로 소비 크기가
 *    판정 크기다. 두 번의 되재기가 없었으면 48 을 피하고 32 를 믿었을 것이다 — 정확히 거꾸로.
 *
 * ── PNG 엔트리 전속. ICO 는 엔트리마다 BMP(DIB) 또는 PNG 를 담을 수 있다. 전량 PNG 로 둔다:
 *    ⓐ **되읽기 검산이 성립한다** — 우리 디코더로 그대로 열어 원판 재산출과 바이트 대조가 된다.
 *      BMP 를 섞으면 검산기에 두 번째 코덱이 필요하고, 그 코덱은 아무도 검산하지 않는다.
 *    ⓑ 지원 하한 = Windows Vista+(셸 PNG 엔트리). MS-3 제출 대상은 Steam Windows(Win10+)라
 *      사정권 안이다. **하한이 있다는 사실 자체는 주력 `application/icon` 결선에서 눈으로 받는다.**
 *
 * ── 무엇을 기계가 보는가.
 *    ⓐ**원판 치수 고정** — 128×128 이 아니면 즉사(배수 전제가 통째로 깨진다).
 *    ⓑ**빈 엔트리 없음** — 불투명 화소 0 이면 즉사.
 *    ⓒ**순색 60** — 산출 전 엔트리가 대장 안(니어리스트라 구성상 참이나 이중으로 잰다).
 *    ⓓ**되읽기 정합** — 쓴 .ico 를 다시 파싱해 엔트리 수·치수·오프셋·길이가 헤더와 맞는지.
 *    ⓔ**재현** — `--check` 가 원판 → .ico 를 재산출해 **파일 전체 바이트 대조**.
 *
 * 사용:  node tools/assets/ico_gen.js [--check]
 */
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC = path.join(ROOT, 'godot', 'assets', 'platform', 'icon_master_128.png');
const DST = path.join(ROOT, 'godot', 'assets', 'platform', 'icon_win.ico');
const STRIP = path.join(ROOT, 'tools', 'palette', 'master_60_strip.png');

// Windows 셸 규약. 256 은 원판의 ×2 이고 나머지는 축소다.
const SIZES = [16, 32, 48, 256];
const MASTER = 128;

const KNOWN = new Set(['--check']);
const badFlags = process.argv.slice(2).filter((a) => a.startsWith('-') && !KNOWN.has(a));
if (badFlags.length) { console.error(`FATAL: 미지의 플래그 ${badFlags.join(' ')}`); process.exit(2); }
const CHECK_ONLY = process.argv.includes('--check');
let fails = 0;
const fail = (m) => { fails++; console.log(`  ✗ ${m}`); };
function die(msg) { console.error('FATAL: ' + msg); process.exit(2); }

// ─────────────────────────────────────────────── PNG (kv_gen.js 와 같은 코덱 규율)
function decode(file) {
  const buf = Buffer.isBuffer(file) ? file : fs.readFileSync(file);
  const label = Buffer.isBuffer(file) ? '<메모리>' : path.basename(file);
  if (buf.readUInt32BE(0) !== 0x89504e47) die(`${label}: PNG 아님`);
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
  if (CH === undefined) die(`${label}: 지원 밖 color type ${ctype}`);
  if (depth !== 8 || inter !== 0) die(`${label}: depth=${depth} interlace=${inter} — 지원 밖`);
  const idat = zlib.inflateSync(Buffer.concat(parts));
  const stride = w * CH;
  if (idat.length !== h * (stride + 1)) die(`${label}: 압축 해제 길이 불일치`);
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
      else if (f !== 0) die(`${label}: 미지의 필터 ${f}`);
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
const PALSET = new Set();
{
  const strip = decode(STRIP);
  for (let i = 0; i < strip.w * strip.h; i++) {
    if (strip.rgba[i * 4 + 3] === 0) continue;
    PALSET.add(`${strip.rgba[i * 4]},${strip.rgba[i * 4 + 1]},${strip.rgba[i * 4 + 2]}`);
  }
  if (PALSET.size !== 60) die(`master_60_strip.png 고유색 ${PALSET.size} != 60 — 스트립 계약 위반`);
}

// ─────────────────────────────────────────────── 파생
// **니어리스트 전속.** 원본 화소를 고를 뿐 섞지 않으므로 대장 밖 색이 생기지 않는다.
function nearestResize(src, sw, sh, t) {
  const b = Buffer.alloc(t * t * 4);
  for (let y = 0; y < t; y++) for (let x = 0; x < t; x++) {
    const sx = Math.floor(x * sw / t), sy = Math.floor(y * sh / t);
    const si = (sy * sw + sx) * 4;
    src.copy(b, (y * t + x) * 4, si, si + 4);
  }
  return b;
}

const master = decode(SRC);
if (master.w !== MASTER || master.h !== MASTER) {
  die(`${path.basename(SRC)} 가 ${master.w}×${master.h} 다 — ${MASTER}×${MASTER} 전제가 깨졌다`);
}
console.log(`원판 ${path.basename(SRC)} ${master.w}×${master.h}`);

const entries = [];
for (const t of SIZES) {
  const rgba = nearestResize(master.rgba, master.w, master.h, t);
  let opaque = 0;
  const outside = new Set();
  for (let i = 0; i < t * t; i++) {
    if (rgba[i * 4 + 3] <= 8) continue;
    opaque++;
    const k = `${rgba[i * 4]},${rgba[i * 4 + 1]},${rgba[i * 4 + 2]}`;
    if (!PALSET.has(k)) outside.add(k);
  }
  if (opaque === 0) fail(`${t}×${t}: 불투명 화소 0 — 빈 엔트리다`);
  if (outside.size) fail(`${t}×${t}: 대장 밖 색 ${outside.size}종 — ${[...outside].slice(0, 3).join(' / ')}`);
  const png = encode(t, t, rgba);
  const ratio = MASTER / t;
  const tag = Number.isInteger(ratio) ? `÷${ratio}` : (Number.isInteger(t / MASTER) ? `×${t / MASTER}` : `÷${ratio.toFixed(3)} (비정수)`);
  console.log(`  · ${String(t).padStart(3)}×${String(t).padEnd(3)} ${tag.padEnd(16)} 불투명 ${String(opaque).padStart(6)}px · PNG ${String(png.length).padStart(6)}B`);
  entries.push({ size: t, png });
}

// ─────────────────────────────────────────────── ICO 조립
// ICONDIR(6) + ICONDIRENTRY(16)×N + 이미지 데이터. 치수 바이트는 256 일 때 0 이다.
function buildIco(list) {
  const dir = Buffer.alloc(6);
  dir.writeUInt16LE(0, 0);            // reserved
  dir.writeUInt16LE(1, 2);            // type 1 = 아이콘
  dir.writeUInt16LE(list.length, 4);
  let offset = 6 + 16 * list.length;
  const table = [];
  for (const e of list) {
    const ent = Buffer.alloc(16);
    ent[0] = e.size >= 256 ? 0 : e.size;   // 0 = 256 (한 바이트에 안 들어간다)
    ent[1] = e.size >= 256 ? 0 : e.size;
    ent[2] = 0;                             // 팔레트 색 수 (32bpp = 0)
    ent[3] = 0;                             // reserved
    ent.writeUInt16LE(1, 4);                // planes
    ent.writeUInt16LE(32, 6);               // bpp
    ent.writeUInt32LE(e.png.length, 8);
    ent.writeUInt32LE(offset, 12);
    offset += e.png.length;
    table.push(ent);
  }
  return Buffer.concat([dir, ...table, ...list.map((e) => e.png)]);
}
const ico = buildIco(entries);

// ⓓ 되읽기 — 쓰기 전에 자기 산출을 다시 판다. **쓴 것과 읽은 것이 같은지는 별 사실이다.**
{
  if (ico.readUInt16LE(0) !== 0 || ico.readUInt16LE(2) !== 1) fail('ICO 헤더 서명 불일치');
  const n = ico.readUInt16LE(4);
  if (n !== SIZES.length) fail(`ICO 엔트리 수 ${n} != ${SIZES.length}`);
  for (let i = 0; i < n; i++) {
    const o = 6 + 16 * i;
    const declared = ico[o] === 0 ? 256 : ico[o];
    const len = ico.readUInt32LE(o + 8), off = ico.readUInt32LE(o + 12);
    if (off + len > ico.length) { fail(`엔트리 ${i}: 오프셋 ${off}+${len} 이 파일(${ico.length}) 밖이다`); continue; }
    const img = decode(ico.slice(off, off + len));
    if (img.w !== declared || img.h !== declared) {
      fail(`엔트리 ${i}: 디렉토리는 ${declared} 인데 이미지는 ${img.w}×${img.h} 다`);
    }
    if (!img.rgba.equals(entries[i].png && decode(entries[i].png).rgba)) {
      fail(`엔트리 ${i}: 되읽은 화소가 파생 결과와 다르다`);
    }
  }
  console.log(`  · 되읽기 ${n} 엔트리 · ${ico.length}B`);
}

if (fails) { console.log(`\nICO_GEN ${CHECK_ONLY ? 'CHECK ' : ''}FAIL fails=${fails}`); process.exit(1); }

if (CHECK_ONLY) {
  if (!fs.existsSync(DST)) { console.log(`  ✗ ${path.relative(ROOT, DST)}: 산출물 없음`); console.log('\nICO_GEN CHECK FAIL fails=1'); process.exit(1); }
  if (!fs.readFileSync(DST).equals(ico)) { console.log(`  ✗ ${path.relative(ROOT, DST)}: 재산출 불일치`); console.log('\nICO_GEN CHECK FAIL fails=1'); process.exit(1); }
  console.log(`\nICO_GEN PASS entries=${entries.length}`);
} else {
  fs.writeFileSync(DST, ico);
  console.log(`  → ${path.relative(ROOT, DST)}  ${ico.length}B`);
  console.log(`\nICO_GEN OK entries=${entries.length}`);
}
