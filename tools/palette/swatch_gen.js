#!/usr/bin/env node
/*
 * 팔레트 스와치 시트 생성기 — godot/assets/palettes/*.png 산출
 *
 * 소유: 에셋 트랙 (`tools/palette/` — 총괄 배정 2026-08-16 · IMPL-139 §1 판정)
 * 전례: IMPL-097 (TL-2 체크리스트) — 생성기 커밋 · 산출물 수기 편집 금지 · 재생성 = 같은 명령
 *
 * ── 이 파일은 색상값을 하나도 갖지 않는다 (부대조건 — 값을 두 번 적으면 그것이 곧 두 벌이다).
 *    마스터 60색 = `godot/assets/palettes/master_60.gpl`      ← 총괄 §1 판정이 지정한 입력
 *    색각 교체 4 = `godot/assets/palettes/colorblind_alt.gpl`
 *    기능 부속 13 = `docs/assets/팔레트_정본_v*.md` §5          ← .gpl 밖이라(대장 §4.9) 정본에서 읽는다
 *    교체 대응관계 = 같은 정본 §6
 *    이 파일이 가진 것은 ASCII 표기 라벨 매핑뿐이다 — 3×5 비트맵 폰트가 한글을 못 그리기 때문.
 *
 * ── 매 실행이 커밋된 산출물끼리의 정합을 함께 검사한다. 하나라도 어긋나면 PNG 를 쓰지 않고 중단한다.
 *
 * 사용:  node tools/palette/swatch_gen.js
 *        node tools/palette/swatch_gen.js --check    (산출 없이 검사만)
 */
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const PAL_DIR = path.join(ROOT, 'godot', 'assets', 'palettes');
const DOC_DIR = path.join(ROOT, 'docs', 'assets');
const CHECK_ONLY = process.argv.includes('--check');

function die(msg) { console.error('FAIL: ' + msg); process.exit(1); }
function need(cond, msg) { if (!cond) die(msg); }

// ─────────────────────────────────────────────────────────── 라벨 매핑 (값 아님)
const BLOCKS = [
  { heading: 'CORE NEUTRAL 16', n: 16, prefix: /^N\d\d$/ },
  { heading: 'TELEMETRY NEON 16', n: 16, prefix: /^[CMAV]\d$/ },
  { heading: 'TEAM COLOR 16', n: 16, prefix: /^(AX|VU|GR|NW)\d$/ },
  { heading: 'ENV / SKIN / MATERIAL 12', n: 12, prefix: /^(EV|SK|MT)\d$/ },
];
const GROUP_LABEL = { '심볼 6종': 'SYM', '게이지 상태': 'GAUGE', '베인 4상태': 'VANE' };
const ITEM_LABEL = {
  '슬립스트림': 'SLIP', '라인': 'LINE', '브레이킹': 'BRAKE', '트러블': 'TROUBLE',
  '찬스': 'CHANCE', '펄스': 'PULSE', '정상': 'OK', '주의': 'WARN', '위험': 'DANGER',
  '평상': 'NORMAL', '경고': 'ALERT', '고양': 'ELATED', '손상': 'DAMAGED',
};
// 정본 §6 '대상' 열 → §5 에서 만들어지는 라벨
const SWAP_TARGET_LABEL = {
  '심볼 · 라인': 'SYM-LINE', '심볼 · 트러블': 'SYM-TROUBLE',
  '게이지 위험': 'GAUGE-DANGER', '게이지 주의': 'GAUGE-WARN',
};

// ─────────────────────────────────────────────────────────── 입력 ① .gpl
const toHex = (r, g, b) => '#' + [r, g, b].map((v) => v.toString(16).toUpperCase().padStart(2, '0')).join('');

function readGpl(file) {
  const raw = fs.readFileSync(file, 'utf8');
  const lines = raw.split(/\r?\n/);
  need(lines[0].trim() === 'GIMP Palette', `${path.basename(file)}: 첫 행이 'GIMP Palette' 가 아니다`);
  const out = [];
  for (const line of lines.slice(1)) {
    if (!line.trim() || line.startsWith('#') || /^(Name|Columns):/.test(line)) continue;
    const m = line.match(/^\s*(\d{1,3})\s+(\d{1,3})\s+(\d{1,3})\t(.+)$/);
    need(m, `${path.basename(file)}: 파싱 불가 행 (구분자가 탭인가?) → ${JSON.stringify(line)}`);
    const [r, g, b] = [m[1], m[2], m[3]].map(Number);
    need([r, g, b].every((v) => v >= 0 && v <= 255), `${path.basename(file)}: RGB 범위 이탈 → ${line}`);
    const sp = m[4].indexOf(' ');
    out.push({ id: sp < 0 ? m[4] : m[4].slice(0, sp), name: sp < 0 ? '' : m[4].slice(sp + 1), hex: toHex(r, g, b) });
  }
  return out;
}

const master = readGpl(path.join(PAL_DIR, 'master_60.gpl'));
const cbGpl = readGpl(path.join(PAL_DIR, 'colorblind_alt.gpl'));

need(master.length === 60, `마스터 엔트리 ${master.length} != 60`);
{ // D10 §2.3 구성 16+16+16+12 (v1.2 — 자색 계열 신설) — 위치 분할이 ID 접두와 맞는지
  let i = 0;
  for (const b of BLOCKS) {
    for (let k = 0; k < b.n; k++, i++) {
      need(b.prefix.test(master[i].id), `블록 '${b.heading}' ${k + 1}번째 ID '${master[i].id}' 가 접두 규칙에 맞지 않는다 — .gpl 순서가 D10 §2.3 구성과 어긋났다`);
    }
  }
  need(i === 60, '블록 합이 60 이 아니다');
}
{ // 마스터 중복 0
  const seen = new Map();
  for (const c of master) {
    need(!seen.has(c.hex), `마스터 중복색 ${c.hex}: ${seen.get(c.hex)} / ${c.id}`);
    seen.set(c.hex, c.id);
  }
}
// 색각 대체본은 마스터 본체를 손대지 않는다 (D10 §2.4 · 대장 §4.9)
need(cbGpl.length === 64, `색각 대체 엔트리 ${cbGpl.length} != 64 (마스터 60 + 교체 4)`);
master.forEach((c, i) => need(cbGpl[i].hex === c.hex && cbGpl[i].id === c.id,
  `colorblind_alt.gpl 의 ${i + 1}번째가 마스터와 다르다 (${cbGpl[i].id} ${cbGpl[i].hex} vs ${c.id} ${c.hex}) — 마스터 본체는 무접촉이어야 한다`));
const cbTail = cbGpl.slice(60);

// ─────────────────────────────────────────────────────────── 입력 ② 팔레트 정본 (기능 13 · 교체 대응)
const docs = fs.readdirSync(DOC_DIR).filter((f) => /^팔레트_정본_v.*\.md$/.test(f));
need(docs.length === 1, `팔레트 정본이 ${docs.length}개다 (정확히 1개여야 한다) — ${DOC_DIR}`);
const DOC = fs.readFileSync(path.join(DOC_DIR, docs[0]), 'utf8');

function section(numTitle) {
  const re = new RegExp(`^## ${numTitle}[^\\n]*$([\\s\\S]*?)(?=^## |\\Z)`, 'm');
  const m = DOC.match(re);
  need(m, `정본에서 '## ${numTitle}' 절을 찾지 못했다 — 문서 구조가 바뀌었다`);
  return m[1];
}
const hexesIn = (s) => (s.match(/#[0-9A-Fa-f]{6}/g) || []).map((h) => h.toUpperCase());

// §5 기능 컬러 부속 13 — 행 = | 군 | 이름 / 이름 ... | `#hex` / `#hex` ... |
const functional = [];
for (const line of section('5\\.').split('\n')) {
  const cells = line.split('|').map((s) => s.trim());
  if (cells.length < 5) continue;
  const label = GROUP_LABEL[cells[1]];
  if (!label) continue;
  const names = cells[2].split('/').map((s) => s.trim());
  const hexes = hexesIn(cells[3]);
  need(names.length === hexes.length, `정본 §5 '${cells[1]}' 행: 이름 ${names.length}개 vs 색 ${hexes.length}개 — 짝이 맞지 않는다`);
  names.forEach((nm, i) => {
    need(ITEM_LABEL[nm], `정본 §5 에 모르는 항목명 '${nm}' — 라벨 매핑을 갱신할 것`);
    functional.push({ id: `${label}-${ITEM_LABEL[nm]}`, hex: hexes[i] });
  });
}
need(functional.length === 13, `기능 컬러 ${functional.length} != 13 (정본 §5 파싱)`);

// §6 색각 대체 — 행 = | 대상 | `#기본` 이름 | `#대체` 이름 | 사유 |
const swaps = [];
for (const line of section('6\\.').split('\n')) {
  const cells = line.split('|').map((s) => s.trim());
  if (cells.length < 6) continue;
  const target = SWAP_TARGET_LABEL[cells[1]];
  if (!target) continue;
  const base = hexesIn(cells[2]), alt = hexesIn(cells[3]);
  need(base.length === 1 && alt.length === 1, `정본 §6 '${cells[1]}' 행: 기본/대체 색이 각 1개가 아니다`);
  swaps.push({ id: target, base: base[0], alt: alt[0] });
}
need(swaps.length === 4, `색각 교체 ${swaps.length} != 4 (정본 §6 파싱 · D10 §2.4 색상만 교체)`);

// ── 교차 검사: 정본 §6 ⇔ colorblind_alt.gpl 꼬리 4 ⇔ 정본 §5 기본색
const fnMap = new Map(functional.map((f) => [f.id, f.hex]));
swaps.forEach((s, i) => {
  need(fnMap.has(s.id), `정본 §6 의 대상 '${s.id}' 가 §5 기능 13 에 없다`);
  need(fnMap.get(s.id) === s.base, `'${s.id}' 기본색 불일치 — §5 ${fnMap.get(s.id)} vs §6 ${s.base}`);
  need(cbTail[i].hex === s.alt, `colorblind_alt.gpl 꼬리 ${i + 1}번(${cbTail[i].id} ${cbTail[i].hex}) 이 정본 §6 대체색 ${s.alt} 와 다르다`);
});

// ─────────────────────────────────────────────────────────── 네온 블록 교차 검사 (IMPL-198 신설)
// **왜 신설했는가.** 자색 4단을 `.gpl` 과 정본 §2 표 **양쪽에** 적는 순간 그것이 곧 두 벌이다
// (대장 §9-⑬ 이 경고한 바로 그 형태). 마스터 색은 종전까지 `.gpl` ↔ `colorblind_alt.gpl` 앞부분
// 대조만 있었고 **정본 표와는 대조가 없었다** — 즉 정본 §2 의 hex 를 오타로 고쳐도 아무것도 안 걸렸다.
// 네온 블록만 거는 이유는 실용이다: §2 는 `| 계열 | 딥 | 베이스 | 브라이트 | 글로우 |` 4열 표라
// 기계 판독이 안정적인데, §1(2단 병렬 표)·§3(산문 혼재)·§4(군/ID/HEX)는 파서가 셋 더 필요하다.
// **부분 커버리지임을 감추지 않는다** — 뉴트럴 16·팀 16·환경 12 는 여전히 정본⇔`.gpl` 미대조다.
const neonDoc = (() => {
  const body = section('2. 텔레메트리 네온');
  const rows = body.split('\n').filter((l) => /^\|/.test(l) && /#[0-9A-Fa-f]{6}/.test(l));
  need(rows.length >= 1, '정본 §2 에서 네온 행을 못 읽었다 — 표 구조가 바뀌었는가');
  const out = [];
  for (const r of rows) out.push(...hexesIn(r));
  return out;
})();
{
  const neonBlock = BLOCKS.findIndex((b) => b.heading.startsWith('TELEMETRY NEON'));
  const start = BLOCKS.slice(0, neonBlock).reduce((n, b) => n + b.n, 0);
  const gplNeon = master.slice(start, start + BLOCKS[neonBlock].n);
  need(neonDoc.length === gplNeon.length,
    `정본 §2 네온 ${neonDoc.length}색 != .gpl 네온 블록 ${gplNeon.length}색`);
  gplNeon.forEach((c, i) => need(c.hex === neonDoc[i],
    `정본 §2 네온 ${i + 1}번째 ${neonDoc[i]} != .gpl ${c.id} ${c.hex} — 두 벌이 갈렸다`));
}

console.log(`검사 통과 — 마스터 ${master.length}(중복 0·구성 ${BLOCKS.map((b) => b.n).join('+')}) · 기능 ${functional.length} · 교체 ${swaps.length} · 마스터 본체 무접촉 · 정본⇔.gpl 교차 일치(§2 네온 ${neonDoc.length} 포함)`);

// ── 커버리지 보고 — 검증 못 하는 것을 검증한 척하지 않는다 (돌연변이 실측으로 드러난 구멍)
//    기능 13 중 §6 교체쌍 4건만 대조 상대(.gpl 꼬리)가 있다. 나머지는 정본이 유일 출처라
//    값을 바꿔도 잡을 방법이 없다 — 대조는 두 곳에 있는 값에만 성립한다.
//    해소 경로: 구현 트랙이 `ui_palette.gd` 를 정본 §9.2 매핑표대로 결선하면(현재 [가안] 21건 미종결)
//    13색 전건에 두 번째 출처가 생긴다. 그때 이 파일에 교차 검사를 추가할 것.
{
  const verified = new Set(swaps.map((s) => s.id));
  const unverified = functional.filter((f) => !verified.has(f.id)).map((f) => f.id);
  console.log(`기능 13 교차 검증 커버리지 ${verified.size}/13 — 미검증 ${unverified.length}건 (정본 단일 출처): ${unverified.join(' ')}`);
  console.log(`  └ 해소 = 구현 트랙의 ui_palette.gd 결선(정본 §9.2) 후 대조 추가`);
}

if (CHECK_ONLY) process.exit(0);

// ─────────────────────────────────────────────────────────── PNG 인코더 (zlib 내장 — 외부 의존 0)
let CRC_T = null;
function crc32(buf) {
  if (!CRC_T) {
    CRC_T = new Int32Array(256);
    for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; CRC_T[n] = c; }
  }
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_T[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function encodePNG(w, h, rgb) {
  const stride = 1 + w * 3;
  const raw = Buffer.alloc(h * stride);
  for (let y = 0; y < h; y++) {
    raw[y * stride] = 0; // filter none — 도트 원도라 필터 예측 이득이 없다
    rgb.copy(raw, y * stride + 1, y * w * 3, (y + 1) * w * 3);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 2; // 8bit truecolor
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ─────────────────────────────────────────────────────────── 3×5 비트맵 폰트 (시트도 도트 규격)
const FONT = {
  A: '111101111101101', B: '110101110101110', C: '011100100100011', D: '110101101101110',
  E: '111100111100111', F: '111100111100100', G: '011100101101011', H: '101101111101101',
  I: '111010010010111', J: '001001001101010', K: '101101110101101', L: '100100100100111',
  M: '101111111101101', N: '110101101101101', O: '010101101101010', P: '110101110100100',
  Q: '010101101110011', R: '110101110101101', S: '011100010001110', T: '111010010010010',
  U: '101101101101111', V: '101101101101010', W: '101101111111101', X: '101101010101101',
  Y: '101101010010010', Z: '111001010100111',
  0: '111101101101111', 1: '010110010010111', 2: '111001111100111', 3: '111001111001111',
  4: '101101111001001', 5: '111100111001111', 6: '111100111101111', 7: '111001001001001',
  8: '111101111101111', 9: '111101111001111',
  '#': '101111101111101', '-': '000000111000000', '.': '000000000000010', '/': '001001010100100',
  ':': '000010000010000', '>': '100010001010100', '+': '000010111010000', '(': '001010010010001',
  ')': '100010010010100', ' ': '000000000000000',
};
const GW = 3, GH = 5, GAP = 1;
const hex2rgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));

// 시트 자신의 색도 마스터에서 조달한다 — 팔레트 밖 색을 쓰지 않는다
const byId = new Map(master.map((c) => [c.id, c.hex]));
const BG = byId.get('N03'), TXT = byId.get('N16'), DIM = byId.get('N14'),
      HEAD = byId.get('C3'), BORDER = byId.get('N08');
need([BG, TXT, DIM, HEAD, BORDER].every(Boolean), '시트 UI 색(N03·N16·N14·C3·N08)을 마스터에서 찾지 못했다');

const COLS = 4, CELL_W = 68, CELL_H = 42, MARGIN = 8;
const CHIP_X = 2, CHIP_Y = 2, CHIP_W = 64, CHIP_H = 24;
const HEAD_H = 14, TITLE_H = 22, SHEET_W = MARGIN * 2 + COLS * CELL_W;

function mkCanvas(w, h, bgHex) {
  const buf = Buffer.alloc(w * h * 3), [r, g, b] = hex2rgb(bgHex);
  for (let i = 0; i < w * h; i++) { buf[i * 3] = r; buf[i * 3 + 1] = g; buf[i * 3 + 2] = b; }
  return { w, h, buf };
}
function px(cv, x, y, rgb) {
  if (x < 0 || y < 0 || x >= cv.w || y >= cv.h) return;
  const o = (y * cv.w + x) * 3;
  cv.buf[o] = rgb[0]; cv.buf[o + 1] = rgb[1]; cv.buf[o + 2] = rgb[2];
}
function rect(cv, x, y, w, h, hex) {
  const rgb = hex2rgb(hex);
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) px(cv, x + i, y + j, rgb);
}
function frame(cv, x, y, w, h, hex) {
  const rgb = hex2rgb(hex);
  for (let i = 0; i < w; i++) { px(cv, x + i, y, rgb); px(cv, x + i, y + h - 1, rgb); }
  for (let j = 0; j < h; j++) { px(cv, x, y + j, rgb); px(cv, x + w - 1, y + j, rgb); }
}
function text(cv, x, y, s, hex, sc = 1) {
  const rgb = hex2rgb(hex);
  let cx = x;
  for (const ch of s.toUpperCase()) {
    const g = FONT[ch] !== undefined ? FONT[ch] : FONT[' '];
    for (let j = 0; j < GH; j++) for (let i = 0; i < GW; i++) {
      if (g[j * GW + i] === '1') for (let sy = 0; sy < sc; sy++) for (let sx = 0; sx < sc; sx++) px(cv, cx + i * sc + sx, y + j * sc + sy, rgb);
    }
    cx += (GW + GAP) * sc;
  }
}

const rowsOf = (n) => Math.ceil(n / COLS);
function drawBlock(cv, y, heading, cells) {
  text(cv, MARGIN, y + 4, heading, HEAD);
  const top = y + HEAD_H;
  cells.forEach((c, i) => {
    const cx = MARGIN + (i % COLS) * CELL_W, cy = top + Math.floor(i / COLS) * CELL_H;
    if (c.alt) { // 교체쌍 — 좌 기본 / 우 대체
      rect(cv, cx + CHIP_X, cy + CHIP_Y, CHIP_W / 2, CHIP_H, c.hex);
      rect(cv, cx + CHIP_X + CHIP_W / 2, cy + CHIP_Y, CHIP_W / 2, CHIP_H, c.alt);
      frame(cv, cx + CHIP_X + CHIP_W / 2 - 1, cy + CHIP_Y, 2, CHIP_H, BG);
    } else {
      rect(cv, cx + CHIP_X, cy + CHIP_Y, CHIP_W, CHIP_H, c.hex);
    }
    frame(cv, cx + CHIP_X, cy + CHIP_Y, CHIP_W, CHIP_H, BORDER); // N01 이 바탕에 묻히지 않게
    text(cv, cx + CHIP_X, cy + 28, c.id, TXT);
    text(cv, cx + CHIP_X, cy + 35, c.alt ? `${c.hex}>${c.alt}` : c.hex, DIM);
  });
  return top + rowsOf(cells.length) * CELL_H;
}
function sheet(title, blocks, footer) {
  const h = MARGIN + TITLE_H + blocks.reduce((s, b) => s + HEAD_H + rowsOf(b.cells.length) * CELL_H, 0) + 10 + MARGIN;
  const cv = mkCanvas(SHEET_W, h, BG);
  text(cv, MARGIN, MARGIN, title, TXT, 2);
  rect(cv, MARGIN, MARGIN + 16, SHEET_W - MARGIN * 2, 1, BORDER);
  let y = MARGIN + TITLE_H;
  for (const b of blocks) y = drawBlock(cv, y, b.heading, b.cells);
  text(cv, MARGIN, y + 3, footer, DIM);
  return cv;
}

const masterBlocks = (() => {
  let i = 0;
  return BLOCKS.map((b) => ({ heading: b.heading, cells: master.slice(i, i += b.n).map((c) => ({ id: c.id, hex: c.hex })) }));
})();

function emit(name, cv) {
  fs.writeFileSync(path.join(PAL_DIR, name), encodePNG(cv.w, cv.h, cv.buf));
  console.log(`${name} ${cv.w}x${cv.h}`);
}

// ─────────────────────────────────────────────────────────── 양자화용 순색 스트립
// 총괄 판정 ⓑ (IMPL-161 §1): `tools/palette/master_60_strip.png` — 제작 공정의 입력이지
// 런타임 리소스가 아니므로 `res://` 밖에 둔다 (대장 §1.1 의 `store/` 논거 그대로 적용).
// 스와치 시트는 기능 4색이 섞여 64색이라 비아이콘 원도의 양자화 기준이 될 수 없다.
function readIDAT(file) {
  const b = fs.readFileSync(file), parts = [];
  let o = 8;
  while (o < b.length) {
    const len = b.readUInt32BE(o), t = b.toString('ascii', o + 4, o + 8);
    if (t === 'IDAT') parts.push(b.slice(o + 8, o + 8 + len));
    if (t === 'IEND') break;
    o += 12 + len;
  }
  return Buffer.concat(parts);
}
{
  const w = master.length, buf = Buffer.alloc(w * 3);
  master.forEach((c, i) => { const [r, g, b] = hex2rgb(c.hex); buf[i * 3] = r; buf[i * 3 + 1] = g; buf[i * 3 + 2] = b; });
  const file = path.join(__dirname, 'master_60_strip.png');
  fs.writeFileSync(file, encodePNG(w, 1, buf));

  // 부대조건 ② — 쓴 파일을 되읽어 검산한다. 60색 실측이 "스와치를 그대로 먹이면 안 된다"의
  // 증거였으므로 스트립 자신도 같은 방식으로 감시한다. 장식이 한 픽셀이라도 섞이면 여기서 죽는다.
  const raw = zlib.inflateSync(readIDAT(file));
  need(raw.length === 1 + w * 3 && raw[0] === 0, '스트립 재독 실패 — 1행·필터 0 이 아니다');
  const got = new Set();
  for (let i = 0; i < w; i++) got.add(toHex(raw[1 + i * 3], raw[2 + i * 3], raw[3 + i * 3]));
  need(got.size === 60, `스트립 고유색 ${got.size} != 60 (장식·중복이 섞였다)`);
  for (const c of master) need(got.has(c.hex), `스트립에 ${c.id} ${c.hex} 없음 — .gpl 과 1:1 이 아니다`);
  console.log(`master_60_strip.png ${w}x1 — 되읽기 검산 통과 (고유색 60 · .gpl 1:1)`);
}
emit('master_60.png', sheet('FORMULA PULSE MASTER 60', [
  ...masterBlocks,
  { heading: 'FUNCTIONAL 13 (OUTSIDE MASTER 60)', cells: functional },
], 'A-PALETTE-01 V1.0 / GENERATED - DO NOT EDIT BY HAND'));

const swapMap = new Map(swaps.map((s) => [s.id, s.alt]));
emit('colorblind_alt.png', sheet('FORMULA PULSE COLORBLIND ALT', [
  ...masterBlocks,
  { heading: 'FUNCTIONAL 13 (CB APPLIED)', cells: functional.map((f) => ({ id: f.id, hex: swapMap.get(f.id) || f.hex })) },
  { heading: 'REPLACED 4 (BASE > ALT)', cells: swaps.map((s) => ({ id: s.id, hex: s.base, alt: s.alt })) },
], 'A-PALETTE-02 V1.0 / MASTER 60 UNCHANGED / DO NOT EDIT'));
