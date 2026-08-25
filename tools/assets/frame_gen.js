#!/usr/bin/env node
/*
 * UI 프레임·글리프 파라메트릭 렌더러 — `frame_spec.json` → `ui/frames/` · `glyphs/`
 *
 * 소유: 에셋 트랙 (`tools/assets/`) · 신설 IMPL-311
 * 전례: `icon_draw.js`(IMPL-215) / `swatch_gen.js`(IMPL-139) — **재현되는 것만 커밋한다.**
 *
 * ── 왜 이 도구가 있는가 (RD 파일럿 실측이 정했다).
 *    9패치는 **기하 계약**이다. ①코너가 규격 px 여야 하고 ②변 가운데는 늘어나는 축으로
 *    균일해야 하며 ③코너 4개가 같은 규격이어야 한다. RD 3회차 6장 실측에서 최선작조차
 *    좌우 불일치 1584px · 변 가운데 불균일 10~11% 였다 — 확산 모델에는 "정확히 16px" 이나
 *    "이 열은 저 열과 같다" 를 표현하는 층위가 없다.
 *
 *    파라메트릭은 그 셋을 **구성으로** 보장한다: 동심 링으로 칠하면 4방 대칭이 공짜이고,
 *    변 가운데는 링 프로파일 그 자체라 균일이 정의상 성립한다. 표식은 좌상 코너 좌표로만
 *    받아 4방 미러로 칠하므로 대칭이 깨질 방법이 없다.
 *
 * ── `--check` 가 하는 일
 *    ⓐ 정의↔실물 바이트 대조 (누가 PNG 만 손대면 정의가 낡는다 — `icon_draw.js` 와 같은 축)
 *    ⓑ **9패치 적합성 검사** — 위 ①②③을 실물 픽셀에서 재측정한다. 생성기가 보장한다고
 *      믿지 않는다: 보장의 근거는 코드이고 검사의 근거는 출력이다. 둘이 갈리면 검사가 이긴다.
 *
 * ── 한계 (검증한 척하지 않는다)
 *    본 도구는 **색이 조달 대장 안인지 보지 않는다.** 그 축은 별 검사 소관이며, 프레임은
 *    아이콘 디렉토리 밖이라 `icon_check.js` PAL 이 닿지 않는다 — `--check` 가 팔레트 키
 *    사용만 강제하고(스펙에 hex 를 직접 못 쓴다) 키→색 대응의 대장 소속은 아래 LEDGER 축이 본다.
 *    도상이 보기 좋은지도 보지 않는다 — 그것은 눈 소관이다.
 *
 * 사용:  node tools/assets/frame_gen.js           (렌더)
 *        node tools/assets/frame_gen.js --check    (대조만 · 불일치 시 exit 1)
 */
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const DEFAULT_DIR = path.join(ROOT, 'godot', 'assets', 'ui', 'frames');
// 산출 디렉토리는 항목별로 갈릴 수 있다 — `key_cap_9p` 는 D10 §5.6 이 **입력 글리프**로 계상했고
// 배치 대장도 `glyphs/` 에 둔다. 9패치라는 형식이 소속을 정하지 않는다.
const DIRS = { frames: DEFAULT_DIR, glyphs: path.join(ROOT, 'godot', 'assets', 'glyphs') };
const dirOf = (s) => DIRS[s.dir || 'frames'] || die(`미지의 dir '${s.dir}'`);
const SPEC = path.join(__dirname, 'frame_spec.json');
const PAL_DIR = path.join(ROOT, 'godot', 'assets', 'palettes');
const DOC_DIR = path.join(ROOT, 'docs', 'assets');

// 파일을 쓰는 도구는 "몰랐으면 안 쓴다" — `bgm_gen.js --only` 가 조용히 무시돼 실물 18개를
// 덮은 사고(IMPL-280)와 같은 기제를 막는다.
const KNOWN = new Set(['--check']);
const bad = process.argv.slice(2).filter((a) => a.startsWith('-') && !KNOWN.has(a));
if (bad.length) {
  console.error(`FATAL: 미지의 플래그 ${bad.join(' ')} — 알려진 것은 ${[...KNOWN].join(' ')}`);
  process.exit(2);
}
const CHECK_ONLY = process.argv.includes('--check');

let fails = 0;
const fail = (axis, msg) => { fails++; console.log(`  ✗ ${axis}  ${msg}`); };
function die(msg) { console.error('FATAL: ' + msg); process.exit(2); }

// ─────────────────────────────────────────────────── 조달 대장 (색값 보유 0)
// 이 파일도 색상값을 하나도 갖지 않는다 — `icon_check.js`·`swatch_gen.js` 와 같은 규율.
const toHex = (r, g, b) => '#' + [r, g, b].map((v) => v.toString(16).toUpperCase().padStart(2, '0')).join('');
function gplHexes(file) {
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  if (lines[0].trim() !== 'GIMP Palette') die(`${path.basename(file)}: 첫 행이 'GIMP Palette' 가 아니다`);
  const out = [];
  for (const line of lines.slice(1)) {
    if (!line.trim() || line.startsWith('#') || /^(Name|Columns):/.test(line)) continue;
    const m = line.match(/^\s*(\d{1,3})\s+(\d{1,3})\s+(\d{1,3})\t(.+)$/);
    if (m) out.push(toHex(Number(m[1]), Number(m[2]), Number(m[3])));
  }
  return out;
}
function canonHexes(sectionNum) {
  const docs = fs.readdirSync(DOC_DIR).filter((f) => /^팔레트_정본_v.*\.md$/.test(f));
  if (docs.length !== 1) die(`팔레트 정본이 ${docs.length}개다 (정확히 1개여야 한다)`);
  const lines = fs.readFileSync(path.join(DOC_DIR, docs[0]), 'utf8').split(/\r?\n/);
  const start = lines.findIndex((l) => new RegExp(`^## ${sectionNum}\\.`).test(l));
  if (start < 0) die(`정본에 §${sectionNum} 절이 없다`);
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i++) if (/^## \d/.test(lines[i])) { end = i; break; }
  const hexes = lines.slice(start, end).join('\n').match(/#[0-9A-Fa-f]{6}/g) || [];
  if (hexes.length === 0) die(`정본 §${sectionNum} 에서 hex 를 못 읽었다 — 표 구조가 바뀌었는가`);
  return hexes.map((h) => h.toUpperCase());
}
const ledger = new Set([
  ...gplHexes(path.join(PAL_DIR, 'master_60.gpl')),
  ...canonHexes(5),
]);
if (ledger.size === 0) die('조달 대장이 비었다 — 팔레트 실물·정본 확인 필요');

// 정본 §6(색각 대체 교체 4색)은 **대장에 넣되 격리한다.** 넣는 이유: `*_alt` 원도가
// 쓸 색이 여기밖에 없다 — 색상 회전은 틴트로 표현되지 않으므로(IMPL-436) 색각 대체는
// 별도 원도이고, 그 원도의 색은 §6 이 정본이다. 격리하는 이유: 열어 두면 §6 색이
// 일반 프레임에 새어 들어가 **색각용 색이 기본 의장에 박힌다.** 그래서 두 방향으로 묶는다.
//   ⓐ §6 전용 색은 이름이 `_alt` 로 끝나는 원도에서만 쓸 수 있다.
//   ⓑ `_alt` 로 끝나는 원도는 §6 색을 **반드시 하나는** 써야 한다 — 안 쓰면 대체가 아니고,
//      빈 유예가 남는다(9패치 symmetry 면제 검사와 같은 규약).
const cbOnly = new Set(canonHexes(6).filter((h) => !ledger.has(h)));
if (cbOnly.size === 0) die('정본 §6 에서 §5·대장 밖 색을 못 읽었다 — 표 구조가 바뀌었는가');
for (const h of cbOnly) ledger.add(h);

// ─────────────────────────────────────────────────── PNG 입출력
function crc32(buf) {
  let c, t = crc32.t;
  if (!t) {
    t = crc32.t = [];
    for (let i = 0; i < 256; i++) { c = i; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[i] = c >>> 0; }
  }
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
function encodePNG(w, h, rgba) {
  const stride = w * 4;
  const raw = Buffer.alloc(h * (stride + 1));
  for (let y = 0; y < h; y++) {
    raw[y * (stride + 1)] = 0;
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}
// 되읽기는 실물 PNG 를 다시 디코드해서 한다 — 인코더가 자기 출력을 비교하면 대조가 아니다.
function decodeRGBA(file, w, h) {
  const buf = fs.readFileSync(file);
  if (buf.readUInt32BE(0) !== 0x89504e47) die(`${file}: PNG 아님`);
  const parts = [];
  let o = 8, gw = 0, gh = 0, ctype = -1;
  while (o + 8 <= buf.length) {
    const len = buf.readUInt32BE(o);
    const type = buf.toString('ascii', o + 4, o + 8);
    const data = buf.slice(o + 8, o + 8 + len);
    if (type === 'IHDR') { gw = data.readUInt32BE(0); gh = data.readUInt32BE(4); ctype = data[9]; }
    if (type === 'IDAT') parts.push(data);
    if (type === 'IEND') break;
    o += 12 + len;
  }
  if (gw !== w || gh !== h) return { mismatch: `치수 ${gw}x${gh} != ${w}x${h}` };
  if (ctype !== 6) return { mismatch: `color type ${ctype} != 6(RGBA)` };
  const idat = zlib.inflateSync(Buffer.concat(parts));
  const stride = w * 4;
  const px = Buffer.alloc(h * stride);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < h; y++) {
    const f = idat[y * (stride + 1)];
    const cur = Buffer.from(idat.slice(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
    for (let i = 0; i < stride; i++) {
      const a = i >= 4 ? cur[i - 4] : 0, b = prev[i], c = i >= 4 ? prev[i - 4] : 0;
      let v = cur[i];
      if (f === 1) v += a; else if (f === 2) v += b; else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c); }
      else if (f !== 0) die(`${file}: 미지의 필터 ${f}`);
      cur[i] = v & 0xff;
    }
    cur.copy(px, y * stride);
    prev = cur;
  }
  return { px };
}

// ─────────────────────────────────────────────────── 렌더
const spec = JSON.parse(fs.readFileSync(SPEC, 'utf8'));
const PAL = spec.palette;
for (const [k, v] of Object.entries(PAL)) {
  if (!/^#[0-9A-F]{6}$/.test(v)) die(`palette ${k}: 색 형식 아님 (${v})`);
  if (!ledger.has(v)) die(`palette ${k} ${v}: 조달 대장 밖 — 대장(master_60 + 정본 §5·§6) 안에서만 고른다`);
}
// 원도별 §6 사용 집계 — 위 ⓐⓑ 두 방향을 프레임 이름과 대조한다.
const CB_KEYS = new Set(Object.entries(PAL).filter(([, v]) => cbOnly.has(v)).map(([k]) => k));
function auditColorblindScope(name, s) {
  const used = new Set();
  const walk = (v) => {
    if (typeof v === 'string') { if (CB_KEYS.has(v)) used.add(v); return; }
    if (Array.isArray(v)) { v.forEach(walk); return; }
    if (v && typeof v === 'object') { Object.values(v).forEach(walk); }
  };
  walk(s);
  const isAlt = /_alt(_9p)?$/.test(name) || /_alt_/.test(name);
  if (used.size && !isAlt) {
    fail('CB-SCOPE', `${name}: 정본 §6 색각 대체색 [${[...used].join(',')}] 을 썼는데 이름이 _alt 가 아니다 — 색각용 색이 기본 의장에 박힌다`);
  }
  if (!used.size && isAltName(name)) {
    fail('CB-SCOPE', `${name}: 이름이 _alt 인데 §6 색을 쓰지 않는다 — 대체가 아니고 빈 유예다`);
  }
}
function isAltName(name) { return /_alt(_9p)?$/.test(name) || /_alt_/.test(name); }
// `bases._palette` 도 `palette` 키만 가리킬 수 있다 — 색값을 두 곳에 두지 않는다.
function rgbOf(key, where) {
  if (key === '.') return null;
  const hex = PAL[key];
  if (!hex) die(`${where}: palette 에 없는 색 키 '${key}'`);
  return [1, 3, 5].map((i) => parseInt(hex.substr(i, 2), 16));
}

function renderNinePatch(name, s) {
  const n = s.size, c = s.corner;
  if (!Number.isInteger(n) || !Number.isInteger(c)) die(`${name}: size·corner 가 정수 아님`);
  // 코너 2개가 캔버스를 넘으면 늘림 구간이 없다 — 9패치가 아니라 그냥 그림이다.
  if (2 * c >= n) die(`${name}: 코너 ${c}×2 >= 변 ${n} — 늘림 구간이 없다`);
  if (s.profile.length > c) die(`${name}: 프로파일 ${s.profile.length}겹 > 코너 ${c} — 링이 코너를 넘는다`);
  const rgba = Buffer.alloc(n * n * 4);
  const put = (x, y, rgb) => {
    if (!rgb) return;
    const i = (y * n + x) * 4;
    rgba[i] = rgb[0]; rgba[i + 1] = rgb[1]; rgba[i + 2] = rgb[2]; rgba[i + 3] = 255;
  };
  // 동심 링 — ring k = 캔버스 경계로부터 체비셰프 거리 k. 4방 대칭이 구성으로 성립한다.
  const depth = s.profile.length;
  const centerRGB = s.center ? rgbOf(s.center, `${name}.center`) : null;
  // `open_sides` = 그 변의 테두리를 두지 않는다. 탭은 아래가 패널에 붙으므로 3면만 둘러야
  // 하는데, 동심 링은 4방 대칭이라 그것을 표현할 수 없다 — 링을 그린 뒤 열린 변을 되돌린다.
  // **대칭 축 선언(`symmetry`)이 함께 필수다** — 안 그러면 검사가 정상 도상을 비대칭으로 잡는다.
  const open = new Set(s.open_sides || []);
  for (const side of open) if (!['top', 'bottom', 'left', 'right'].includes(side)) die(`${name}: 미지의 open_sides '${side}'`);
  const OPEN_AXIS = { top: 'tb', bottom: 'tb', left: 'lr', right: 'lr' };
  if (open.size) {
    const need = new Set([...open].map((k) => OPEN_AXIS[k]));
    const decl = s.symmetry === undefined ? null : s.symmetry;
    // 열린 변이 tb 축을 깨면 `symmetry` 는 'lr' 이어야 하고, 그 역도 같다.
    const allowed = need.has('tb') && need.has('lr') ? 'none' : (need.has('tb') ? 'lr' : 'tb');
    if (decl !== allowed) die(`${name}: open_sides ${[...open].join(',')} 는 symmetry "${allowed}" 선언이 필요하다 (현재 ${JSON.stringify(decl)})`);
  }
  const isOpen = (x, y, ring) => (
    (open.has('top') && y === ring) || (open.has('bottom') && y === n - 1 - ring)
    || (open.has('left') && x === ring) || (open.has('right') && x === n - 1 - ring));
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      const ring = Math.min(x, y, n - 1 - x, n - 1 - y);
      if (ring < depth) {
        // 열린 변에 속하는 링 픽셀은 테두리를 두지 않고 면(또는 투명)으로 남긴다.
        if (isOpen(x, y, ring)) put(x, y, centerRGB);
        else put(x, y, rgbOf(s.profile[ring], `${name}.profile[${ring}]`));
      } else put(x, y, centerRGB);
    }
  }
  // 표식 — 좌상 코너 좌표를 4방 미러. 대칭이 깨질 방법이 없다.
  for (const [mx, my, key] of (s.marks || [])) {
    if (mx < 0 || my < 0 || mx >= c || my >= c) die(`${name}: 표식 (${mx},${my}) 이 코너 구역 0..${c - 1} 밖이다`);
    const rgb = rgbOf(key, `${name}.marks`);
    for (const [px, py] of [[mx, my], [n - 1 - mx, my], [mx, n - 1 - my], [n - 1 - mx, n - 1 - my]]) put(px, py, rgb);
  }
  return { w: n, h: n, rgba };
}

// ── `glyph` 타입 — **공유 base 맵 + 표식**.
//
//    왜 sprite 로 안 되는가: 패드 16종은 *"같은 버튼인데 하나만 다르다"* 로 정의된 세트다
//    (페이스 4 = 같은 링에 점 위치만 / 방향 4 = 같은 십자에 채운 팔만 / 숄더·트리거·스틱 = 좌우 미러).
//    각 파일을 독립 ASCII 맵으로 두면 **같아야 하는 부분이 파일마다 손으로 베껴진다** —
//    한 곳을 고치면 나머지가 낡고, 그것을 막을 대조 상대가 없다.
//    base 를 한 곳에 두고 표식만 갈면 **family 가 구성으로 보장**되고, base 수정이 세트 전체에 전파된다.
//
//    RD 를 쓰지 않는 근거도 정확히 이 지점이다(글리프 파일럿 실측): `rd_fast` 는 `reference_images`
//    를 지원하지 않으므로 *"이것과 같게, 하나만 다르게"* 를 표현할 방법이 **구조적으로 없다**.
function renderGlyph(name, s, bases) {
  const [w, h] = s.size;
  const base = bases[s.base];
  if (!base) die(`${name}: bases 에 없는 base '${s.base}'`);
  if (base.length !== h) die(`${name}: base '${s.base}' 행 ${base.length} != 높이 ${h}`);
  const rgba = Buffer.alloc(w * h * 4);
  const pal = Object.assign({}, s.map_palette || {}, bases._palette || {});
  const put = (x, y, key, where) => {
    if (x < 0 || y < 0 || x >= w || y >= h) die(`${name}: 캔버스 밖 (${x},${y})`);
    const rgb = rgbOf(key, where);
    if (!rgb) return;
    const i = (y * w + x) * 4;
    rgba[i] = rgb[0]; rgba[i + 1] = rgb[1]; rgba[i + 2] = rgb[2]; rgba[i + 3] = 255;
  };
  base.forEach((row, y) => {
    if (row.length !== w) die(`${name}: base '${s.base}' 행 ${y} 폭 ${row.length} != ${w}`);
    for (let x = 0; x < w; x++) {
      const ch = row[x];
      if (ch === '.') continue;
      const key = pal[ch];
      if (!key) die(`${name}: base 글자 '${ch}' 의 색 키가 없다 (map_palette/bases._palette)`);
      // mirror 는 **맵 안에서만** 좌우 반전한다 — 도트 축 반전이라 픽셀 손실 0 (IMPL-162 전례).
      put(s.mirror ? (w - 1 - x) : x, y, key, `${name}.base`);
    }
  });
  for (const [mx, my, key] of (s.marks || [])) {
    put(s.mirror ? (w - 1 - mx) : mx, my, key, `${name}.marks`);
  }
  return { w, h, rgba };
}

function renderSprite(name, s) {
  const [w, h] = s.size;
  const rows = s.map;
  if (rows.length !== h) die(`${name}: 맵 행 ${rows.length} != 높이 ${h}`);
  const rgba = Buffer.alloc(w * h * 4);
  rows.forEach((r, y) => {
    if (r.length !== w) die(`${name}: 맵 행 ${y} 폭 ${r.length} != ${w}`);
    for (let x = 0; x < w; x++) {
      const ch = r[x];
      if (ch === '.') continue;
      const key = s.map_palette[ch];
      if (!key) die(`${name}: map_palette 에 없는 글자 '${ch}' (행 ${y} 열 ${x})`);
      const rgb = rgbOf(key, `${name}.map`);
      const i = (y * w + x) * 4;
      rgba[i] = rgb[0]; rgba[i + 1] = rgb[1]; rgba[i + 2] = rgb[2]; rgba[i + 3] = 255;
    }
  });
  return { w, h, rgba };
}

// ─────────────────────────────────────────────────── 9패치 적합성 검사
// 생성기가 보장한다고 믿지 않는다 — 보장의 근거는 코드이고 검사의 근거는 출력이다.
function ninePatchAudit(name, img, c, symmetry) {
  const { w, h, rgba } = img;
  const at = (x, y) => { const i = (y * w + x) * 4; return `${rgba[i]},${rgba[i + 1]},${rgba[i + 2]},${rgba[i + 3]}`; };
  let lr = 0, tb = 0;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (at(x, y) !== at(w - 1 - x, y)) lr++;
    if (at(x, y) !== at(x, h - 1 - y)) tb++;
  }
  // 요구 축은 스펙이 선언한다. 기본 = 양축. 탭처럼 한 변이 열린 도상은 그 축을 면제하되
  // **면제를 스펙에 적게** 한다 — 검사를 끄는 것이 아니라 무엇을 왜 빼는지 남기는 것이다.
  const wantLR = symmetry !== 'tb' && symmetry !== 'none';
  const wantTB = symmetry !== 'lr' && symmetry !== 'none';
  if (wantLR && lr) fail('NP-SYM', `${name}: 좌우 비대칭 ${lr}px — 코너 4개가 같은 규격이 아니다`);
  if (wantTB && tb) fail('NP-SYM', `${name}: 상하 비대칭 ${tb}px — 〃`);
  // 면제한 축이 **실제로는 대칭이면** 선언이 낡았다는 뜻이다 (빈 유예를 남기지 않는다 — ISO 유예 전례).
  if (!wantLR && lr === 0) fail('NP-SYM', `${name}: symmetry 가 좌우를 면제했는데 실측은 대칭이다 — 선언을 지워라`);
  if (!wantTB && tb === 0) fail('NP-SYM', `${name}: symmetry 가 상하를 면제했는데 실측은 대칭이다 — 선언을 지워라`);
  // 변 가운데는 늘어나는 축으로 균일해야 한다. 상·하 변은 x 축으로, 좌·우 변은 y 축으로.
  let varCount = 0;
  for (let y = 0; y < c; y++) { const ref = at(c, y); for (let x = c; x < w - c; x++) if (at(x, y) !== ref) varCount++; }
  for (let y = h - c; y < h; y++) { const ref = at(c, y); for (let x = c; x < w - c; x++) if (at(x, y) !== ref) varCount++; }
  for (let x = 0; x < c; x++) { const ref = at(x, c); for (let y = c; y < h - c; y++) if (at(x, y) !== ref) varCount++; }
  for (let x = w - c; x < w; x++) { const ref = at(x, c); for (let y = c; y < h - c; y++) if (at(x, y) !== ref) varCount++; }
  if (varCount) fail('NP-TILE', `${name}: 변 가운데 불균일 ${varCount}px — 늘리면 변화가 드러난다`);
  // 늘림 구간의 중앙 면도 균일해야 한다 (센터는 양축으로 늘어난다).
  let cVar = 0;
  const cRef = at(c, c);
  for (let y = c; y < h - c; y++) for (let x = c; x < w - c; x++) if (at(x, y) !== cRef) cVar++;
  if (cVar) fail('NP-TILE', `${name}: 중앙 면 불균일 ${cVar}px — 양축으로 늘어나는 자리다`);
  return { lr, tb, varCount, cVar };
}

// ─────────────────────────────────────────────────── 주행
const names = Object.keys(spec.frames);
if (names.length === 0) die('frame_spec.json 에 프레임이 없다');
if (!CHECK_ONLY) for (const d of new Set(names.map((n) => dirOf(spec.frames[n])))) fs.mkdirSync(d, { recursive: true });
console.log(`UI 프레임 ${CHECK_ONLY ? '대조' : '렌더'} — ${names.length}종 · 조달 대장 ${ledger.size}색\n`);

let audited = 0;
for (const name of names) {
  const s = spec.frames[name];
  auditColorblindScope(name, s);
  const img = s.type === 'ninepatch' ? renderNinePatch(name, s)
    : s.type === 'glyph' ? renderGlyph(name, s, spec.bases || {})
    : renderSprite(name, s);
  const file = path.join(dirOf(s), name + '.png');
  let ink = 0;
  for (let i = 0; i < img.w * img.h; i++) if (img.rgba[i * 4 + 3]) ink++;

  let audit = null;
  if (s.type === 'ninepatch') { audit = ninePatchAudit(name, img, s.corner, s.symmetry); audited++; }
  // 표기는 **요구된 축만** 본다 — 면제된 축의 비대칭을 NG 로 찍으면 로그가 거짓말을 한다
  // (합격인데 NG 로 보이는 줄이 생기면 다음 독자가 그것을 결함으로 읽는다).
  const symTag = s.type !== 'ninepatch' ? '' : (() => {
    const wantLR = s.symmetry !== 'tb' && s.symmetry !== 'none';
    const wantTB = s.symmetry !== 'lr' && s.symmetry !== 'none';
    const bad = (wantLR ? audit.lr : 0) + (wantTB ? audit.tb : 0);
    const note = s.symmetry ? ` (${s.symmetry} 축만 — ${(s.open_sides || []).join(',') || '선언'} 면제)` : '';
    return `${bad === 0 ? 'OK' : 'NG'}${note}`;
  })();
  const tag = s.type === 'ninepatch'
    ? `${img.w}×${img.h} 코너 ${s.corner} · 잉크 ${ink} · 대칭 ${symTag} · 변균일 ${audit.varCount + audit.cVar === 0 ? 'OK' : 'NG'}`
    : `${img.w}×${img.h} ${s.type === 'glyph' ? `글리프 base=${s.base}${s.mirror ? ' (미러)' : ''}` : '스프라이트'} · 잉크 ${ink}`;

  if (CHECK_ONLY) {
    if (!fs.existsSync(file)) { fail('DEF', `${name}.png 부재 — 정의만 있고 실물이 없다`); continue; }
    const got = decodeRGBA(file, img.w, img.h);
    if (got.mismatch) { fail('DEF', `${name}.png ${got.mismatch}`); continue; }
    let diff = 0;
    for (let i = 0; i < img.w * img.h * 4; i++) if (got.px[i] !== img.rgba[i]) diff++;
    if (diff) fail('DEF', `${name}.png 가 정의와 다르다 — 바이트 ${diff}개 어긋남 (한쪽만 고쳐졌다)`);
    else console.log(`  ✓ ${name}.png  ${tag}`);
  } else {
    fs.writeFileSync(file, encodePNG(img.w, img.h, img.rgba));
    console.log(`  → ${name}.png  ${tag}`);
    const got = decodeRGBA(file, img.w, img.h);
    if (got.mismatch) fail('DEF', `${name}.png 되읽기 ${got.mismatch}`);
    else {
      let diff = 0;
      for (let i = 0; i < img.w * img.h * 4; i++) if (got.px[i] !== img.rgba[i]) diff++;
      if (diff) fail('DEF', `${name}.png 되읽기 불일치 ${diff}바이트`);
    }
  }
}

// 정의에 없는 실물 = 유령 파일. 프레임 디렉토리는 이 도구 전속이므로 남는 것이 있으면 알린다.
// **`frames/` 만 이 도구 전속이다.** `glyphs/` 는 패드 16종 등 남의 산출물이 함께 사는
// 디렉토리라 유령 검사를 돌리면 그쪽을 전부 유령으로 잡는다 — 검사 범위는 소유 범위여야 한다.
if (fs.existsSync(DEFAULT_DIR)) {
  const owned = new Set(names.filter((n) => dirOf(spec.frames[n]) === DEFAULT_DIR));
  const stray = fs.readdirSync(DEFAULT_DIR).filter((f) => f.endsWith('.png') && !owned.has(f.replace(/\.png$/, '')));
  for (const f of stray) fail('DEF', `정의에 없는 실물: ${f} — 스펙에 적거나 지운다`);
}

console.log('');
if (fails) { console.log(`FRAME_GEN FAIL fails=${fails}`); process.exit(1); }
console.log(`FRAME_GEN ${CHECK_ONLY ? 'PASS' : 'OK'} frames=${names.length} ninepatch_audited=${audited}`);
