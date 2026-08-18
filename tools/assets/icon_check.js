#!/usr/bin/env node
/*
 * 아이콘 원도 기계 검사 — `godot/assets/ui/icons/*.png` 27종(+대체 2) 전수
 *
 * 소유: 에셋 트랙 (`tools/assets/` — 미배정 경로 신설. 근거는 IMPL-139 §1 전례
 *       *"미배정 경로이지 남의 경로가 아니다"*. `tools/palette/` 는 색 파이프라인 소관이고
 *       본 검사는 도상 기하 축이라 같은 디렉토리에 두면 독자를 오도한다)
 * 전례: IMPL-097 / IMPL-139 — **검사는 커밋한다. 재현 = 같은 명령.**
 *
 * ── 왜 신설인가 (IMPL-165 의 결함).
 *    IMPL-165 는 "아이콘 29파일 전건 32×32 · 팔레트 이탈 0 · 고립 픽셀 0" 을 실측으로 보고했으나
 *    **그 검사는 애드혹 스크립트였고 커밋되지 않았다.** 그래서 IMPL-172(주력 눈 판독)가 찾은
 *    `achv_rival` 분리 파편 3px 을 기계가 놓친 것은 축이 약했던 문제만이 아니다 —
 *    **재실행할 수 있는 검사가 없었다.** 산문으로 남은 검사는 재현을 보증하지 못한다(IMPL-139 §1 논거).
 *    본 파일이 그 애드혹 검사를 축 강화와 함께 커밋 형태로 대체한다.
 *
 * ── 검사 축
 *    DIM  치수 32×32                                  (대장 §4.1) — 차단
 *    PAL  불투명 픽셀 색이 조달 대장 안                  (정본 §3·§5·§6) — 차단
 *    ISO  단독 1px 성분 0                              (IMPL-165 축 — **정의 교정**) — 차단 (좌표 유예 가능)
 *    SEP  **분리 성분 수 = 선언값**                      (신설 — 총괄 판정 §2-③) — 차단
 *    FRG  파편 후보(작고 본체에서 멀다) 열거              (신설 부속) — 경고
 *
 * ── ISO 정의를 4-이웃에서 8-이웃으로 교정한 근거 (실측).
 *    IMPL-165 의 축은 *"상하좌우 4이웃이 모두 투명한 불투명 픽셀"* 이었다. 그 정의를 그대로
 *    구현하니 `symbol_chance` 의 **대각 광선 끝 4픽셀**(11,11)(20,11)(11,20)(20,20) 이 걸린다 —
 *    완전 대칭이고 4갈래 반짝임 도상의 뾰족한 끝이다. 대각으로만 붙는 1픽셀은 도트 관용이며
 *    결함이 아니다. 즉 **4-이웃 정의는 정상 도상을 잡는다.** 우리가 잡으려는 결함은
 *    *"아무것에도 붙지 않은 잉크"* 이므로 정의는 8-이웃 단독 성분이 맞다.
 *    (부수로 드러난 사실: IMPL-165 의 "고립 픽셀 0" 은 4-이웃 정의로도 성립하지 않았다 —
 *     당시 실물에 6픽셀이 있었다. 애드혹 검사가 전수를 돌지 않았거나 결함이 있었고,
 *     커밋되지 않았으므로 어느 쪽인지 확인할 방법이 없다.)
 *
 * ── SEP 를 "성분 1개" 로 못 박지 않은 이유 (실측 근거).
 *    실측하니 29파일 중 10파일이 다성분이고 **전부 의도된 도상**이다(슬립스트림 속도선 2줄,
 *    세이브 화살표와 본체, 해저드 스파크 등). "성분 1" 을 차단 규격으로 두면 정상 도상이
 *    대량 오검출된다. 그래서 **선언 대조**로 세웠다 — 성분 수를 `icon_manifest.json` 에
 *    사유와 함께 적어 두고 실측과 대조한다. 값이 두 곳에 있을 때만 대조가 성립한다는
 *    대장 §9-⑬ 의 규율을 그대로 적용한 것이며, **새 파편은 선언에 없으므로 즉시 차단**된다.
 *
 * ── 한계 (검증한 척하지 않는다).
 *    SEP 는 성분 **수**만 본다. 한 회차에 파편이 1개 생기고 정상 성분 2개가 붙어버리면
 *    수가 같아 통과한다. FRG 경고 축이 그 사각을 부분적으로 덮지만(파편은 대개 작고 멀다)
 *    완전하지 않다. 도상 자체의 옳음은 여전히 눈 판독 소관이다.
 *
 * 사용:  node tools/assets/icon_check.js            (검사 — 위반 시 exit 1)
 *        node tools/assets/icon_check.js --report   (검사 없이 실측 덤프 — 선언값 산출용)
 */
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ICON_DIR = path.join(ROOT, 'godot', 'assets', 'ui', 'icons');
const PAL_DIR = path.join(ROOT, 'godot', 'assets', 'palettes');
const DOC_DIR = path.join(ROOT, 'docs', 'assets');
const MANIFEST = path.join(__dirname, 'icon_manifest.json');
const REPORT_ONLY = process.argv.includes('--report');

const DIM = 32;                  // 대장 §4.1 기본 — 16px 세트는 매니페스트 `size` 로 선언한다 (IMPL-215)
const FRG_MAX_PX = 3;            // 파편 후보 절대 상한 (경고 축) — 주력 검출분이 3px 이었다
const FRG_MIN_GAP = 4;           // 본체와의 체비셰프 간격 하한 (경고 축)
const FRG_MAX_SHARE = 0.05;      // 전 잉크 대비 비중 상한 (경고 축)

let fails = 0;
let warns = 0;
const fail = (axis, msg) => { fails++; console.log(`  ✗ ${axis}  ${msg}`); };
const warn = (axis, msg) => { warns++; console.log(`  ⚠ ${axis}  ${msg}`); };
function die(msg) { console.error('FATAL: ' + msg); process.exit(2); }

const toHex = (r, g, b) => '#' + [r, g, b].map((v) => v.toString(16).toUpperCase().padStart(2, '0')).join('');

// ─────────────────────────────────────────────────────────── 조달 대장 (색값 보유 0)
// 이 파일도 색상값을 하나도 갖지 않는다 — swatch_gen.js 의 부대조건과 같은 규율.
function gplHexes(file) {
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  if (lines[0].trim() !== 'GIMP Palette') die(`${path.basename(file)}: 첫 행이 'GIMP Palette' 가 아니다`);
  const out = [];
  for (const line of lines.slice(1)) {
    if (!line.trim() || line.startsWith('#') || /^(Name|Columns):/.test(line)) continue;
    const m = line.match(/^\s*(\d{1,3})\s+(\d{1,3})\s+(\d{1,3})\t(.+)$/);
    if (!m) die(`${path.basename(file)}: 파싱 불가 행 (구분자가 탭인가?) → ${JSON.stringify(line)}`);
    out.push(toHex(Number(m[1]), Number(m[2]), Number(m[3])));
  }
  return out;
}

function canonHexes(sectionNum) {
  const docs = fs.readdirSync(DOC_DIR).filter((f) => /^팔레트_정본_v.*\.md$/.test(f));
  if (docs.length !== 1) die(`팔레트 정본이 ${docs.length}개다 (정확히 1개여야 한다)`);
  const doc = fs.readFileSync(path.join(DOC_DIR, docs[0]), 'utf8');
  const lines = doc.split(/\r?\n/);
  const start = lines.findIndex((l) => new RegExp(`^## ${sectionNum}\\.`).test(l));
  if (start < 0) die(`정본에 §${sectionNum} 절이 없다`);
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i++) if (/^## \d/.test(lines[i])) { end = i; break; }
  const hexes = lines.slice(start, end).join('\n').match(/#[0-9A-Fa-f]{6}/g) || [];
  if (hexes.length === 0) die(`정본 §${sectionNum} 에서 hex 를 못 읽었다 — 표 구조가 바뀌었는가`);
  return hexes.map((h) => h.toUpperCase());
}

const ledger = new Set([
  ...gplHexes(path.join(PAL_DIR, 'master_60.gpl')),       // 마스터 60 (D10 v1.2 — 자색 4단 포함)
  ...gplHexes(path.join(PAL_DIR, 'colorblind_alt.gpl')),  // 60 + 교체 4
  ...canonHexes(5),                                        // 기능 부속 13 (56 밖 — 정본 §5)
  ...canonHexes(6),                                        // 색각 교체 대응 (정본 §6)
]);

// ─────────────────────────────────────────────────────────── PNG 디코드
// swatch_gen.js 의 `readIDAT` 은 1행 RGB 스트립 전용(필터 처리 없음)이라 재사용할 수 없다.
// 팔레트 파이프라인을 건드려 리팩터하는 편이 위험이 크므로 여기에 완전 디코더를 둔다.
function pngChunks(buf) {
  if (buf.length < 8 || buf.readUInt32BE(0) !== 0x89504e47) die('PNG 시그니처 불일치');
  const out = [];
  let o = 8;
  while (o + 8 <= buf.length) {
    const len = buf.readUInt32BE(o);
    const type = buf.toString('ascii', o + 4, o + 8);
    out.push({ type, data: buf.slice(o + 8, o + 8 + len) });
    if (type === 'IEND') break;
    o += 12 + len;
  }
  return out;
}

function decodePNG(file) {
  const cs = pngChunks(fs.readFileSync(file));
  const ihdr = cs.find((c) => c.type === 'IHDR');
  if (!ihdr) die(`${path.basename(file)}: IHDR 부재`);
  const w = ihdr.data.readUInt32BE(0), h = ihdr.data.readUInt32BE(4);
  const depth = ihdr.data[8], ctype = ihdr.data[9], interlace = ihdr.data[12];
  const CH = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[ctype];
  if (CH === undefined) die(`${path.basename(file)}: 미지의 color type ${ctype}`);
  // 인터레이스·16bit 는 본 파이프라인 산출물이 아니다. 조용히 넘기지 않고 죽는다 —
  // 검사가 못 읽는 파일을 통과로 세면 검사가 아니다.
  if (depth !== 8 || interlace !== 0) die(`${path.basename(file)}: depth=${depth} interlace=${interlace} — 지원 밖(8bit·비인터레이스만)`);
  const plte = cs.find((c) => c.type === 'PLTE');
  const trns = cs.find((c) => c.type === 'tRNS');
  const idat = zlib.inflateSync(Buffer.concat(cs.filter((c) => c.type === 'IDAT').map((c) => c.data)));
  const stride = w * CH;
  if (idat.length !== h * (stride + 1)) die(`${path.basename(file)}: 압축 해제 길이 ${idat.length} != ${h * (stride + 1)}`);
  const px = Buffer.alloc(h * stride);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < h; y++) {
    const f = idat[y * (stride + 1)];
    const cur = Buffer.from(idat.slice(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
    for (let i = 0; i < stride; i++) {
      const a = i >= CH ? cur[i - CH] : 0, b = prev[i], c = i >= CH ? prev[i - CH] : 0;
      let v = cur[i];
      if (f === 1) v += a;
      else if (f === 2) v += b;
      else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) {
        const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
      } else if (f !== 0) die(`${path.basename(file)}: 미지의 필터 ${f} (행 ${y})`);
      cur[i] = v & 0xff;
    }
    cur.copy(px, y * stride);
    prev = cur;
  }
  const rgba = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    let r, g, b, a = 255;
    if (ctype === 6) { [r, g, b, a] = [px[i * 4], px[i * 4 + 1], px[i * 4 + 2], px[i * 4 + 3]]; }
    else if (ctype === 2) { [r, g, b] = [px[i * 3], px[i * 3 + 1], px[i * 3 + 2]]; }
    else if (ctype === 4) { r = g = b = px[i * 2]; a = px[i * 2 + 1]; }
    else if (ctype === 0) { r = g = b = px[i]; }
    else { const k = px[i]; [r, g, b] = [plte.data[k * 3], plte.data[k * 3 + 1], plte.data[k * 3 + 2]]; if (trns && k < trns.data.length) a = trns.data[k]; }
    rgba[i * 4] = r; rgba[i * 4 + 1] = g; rgba[i * 4 + 2] = b; rgba[i * 4 + 3] = a;
  }
  return { w, h, ctype, rgba };
}

// ─────────────────────────────────────────────────────────── 기하 축
const D4 = [[1, 0], [-1, 0], [0, 1], [0, -1]];
const D8 = [...D4, [1, 1], [1, -1], [-1, 1], [-1, -1]];

// 성분은 8-이웃으로 센다. 4-이웃으로 세면 대각으로만 이어진 정상 도상(속도선·파선)이
// 통째로 쪼개져 선언값이 도상 의도가 아니라 연결 방식의 부산물이 된다.
function components(img) {
  const { w, h, rgba } = img;
  const opaque = (x, y) => rgba[(y * w + x) * 4 + 3] > 0;
  const lab = new Int32Array(w * h).fill(-1);
  const comps = [];
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (!opaque(x, y) || lab[y * w + x] !== -1) continue;
    const id = comps.length, stack = [[x, y]], pts = [];
    lab[y * w + x] = id;
    while (stack.length) {
      const [cx, cy] = stack.pop();
      pts.push([cx, cy]);
      for (const [dx, dy] of D8) {
        const nx = cx + dx, ny = cy + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        if (!opaque(nx, ny) || lab[ny * w + nx] !== -1) continue;
        lab[ny * w + nx] = id; stack.push([nx, ny]);
      }
    }
    comps.push(pts);
  }
  return comps.sort((a, b) => b.length - a.length);
}

const chebyshevGap = (a, b) => {
  let best = Infinity;
  for (const [x, y] of a) for (const [mx, my] of b) {
    const d = Math.max(Math.abs(x - mx), Math.abs(y - my));
    if (d < best) best = d;
  }
  return best;
};

const bboxOf = (c) => {
  const xs = c.map((p) => p[0]), ys = c.map((p) => p[1]);
  return `(${Math.min(...xs)},${Math.min(...ys)})-(${Math.max(...xs)},${Math.max(...ys)})`;
};

// ─────────────────────────────────────────────────────────── 선언 대조
const manifest = REPORT_ONLY ? { icons: {} } : JSON.parse(fs.readFileSync(MANIFEST, 'utf8'));
const decl = manifest.icons || {};

const files = fs.readdirSync(ICON_DIR).filter((f) => f.endsWith('.png')).sort();
if (files.length === 0) die(`${ICON_DIR} 에 PNG 가 없다`);

console.log(`아이콘 기계 검사 — ${files.length}파일 · 조달 대장 ${ledger.size}색`);
console.log('');

let checks = 0;
const reportRows = [];

for (const f of files) {
  const img = decodePNG(path.join(ICON_DIR, f));
  const lines = [];
  const say = (fn, axis, msg) => { lines.push(() => fn(axis, `${f}: ${msg}`)); };

  // DIM — 치수는 파일마다 다를 수 있다(32px 본 세트 + 16px 목록·피드 세트). **선언이 없으면 32 다**,
  // 즉 새 치수는 매니페스트에 적어야만 통과한다 — 임의 치수가 조용히 들어오는 길을 막는다.
  const declEntry = decl[f];
  const dim = (declEntry && declEntry.size) || DIM;
  checks++;
  if (img.w !== dim || img.h !== dim) say(fail, 'DIM', `${img.w}×${img.h} != 선언 ${dim}×${dim}`);

  // PAL
  const outside = new Map();
  for (let i = 0; i < img.w * img.h; i++) {
    if (img.rgba[i * 4 + 3] === 0) continue;
    checks++;
    const hx = toHex(img.rgba[i * 4], img.rgba[i * 4 + 1], img.rgba[i * 4 + 2]);
    if (!ledger.has(hx)) outside.set(hx, (outside.get(hx) || 0) + 1);
  }
  for (const [hx, n] of outside) say(fail, 'PAL', `조달 대장 밖 ${hx} ${n}px`);

  const entry = declEntry;
  const comps = components(img);
  const main = comps[0] || [];
  const ink = comps.reduce((n, c) => n + c.length, 0);

  // ISO — 8-이웃으로도 아무것에 붙지 않은 1px 성분. 좌표 단위 유예(`iso_open`)를 둔다.
  // 파일 단위로 유예하면 같은 파일의 **새** 고립 픽셀이 함께 가려지므로 기보고분만 좌표로 못 박는다.
  const isoOpen = new Set((entry && entry.iso_open) || []);
  const isoSeen = new Set();
  for (const c of comps) {
    if (c.length !== 1) continue;
    checks++;
    const key = `${c[0][0]},${c[0][1]}`;
    if (isoOpen.has(key)) { isoSeen.add(key); say(warn, 'ISO', `단독 픽셀 (${key}) ← 기보고 미해소`); }
    else say(fail, 'ISO', `단독 픽셀 (${key})`);
  }
  // 유예가 해소됐으면 선언을 지우게 한다 — 남은 유예는 조용히 늙는다.
  for (const key of isoOpen) if (!isoSeen.has(key)) { checks++; say(fail, 'ISO', `유예 선언 (${key}) 에 단독 픽셀 없음 — 해소됐으면 iso_open 에서 지워라`); }

  // SEP
  const expected = entry ? entry.components : 1;
  checks++;
  if (comps.length !== expected) {
    const detail = comps.slice(1).map((c) => `${c.length}px ${bboxOf(c)} gap=${chebyshevGap(c, main)}`).join(' | ');
    say(fail, 'SEP', `분리 성분 ${comps.length} != 선언 ${expected}${detail ? `  [비본체: ${detail}]` : ''}`);
  }

  // FRG — 파편은 "작고 멀다". 크기 하나로 자르면 정상 대칭 도상(배틀 존의 마주보는 꺾쇠 48px,
  // 간격 11)이 걸리고, 간격 하나로 자르면 같은 것이 또 걸린다. 그래서 **절대 크기**(≤3px)이거나
  // **잉크 비중이 미미하면서 멀 때**(≤5% AND gap≥4)만 후보로 올린다.
  for (const c of comps.slice(1)) {
    const gap = chebyshevGap(c, main);
    // 간격 하한은 캔버스에 비례시킨다 — 16px 원도에서 gap 4 는 32px 의 gap 8 에 해당한다.
    const minGap = Math.max(2, Math.round(FRG_MIN_GAP * dim / DIM));
    if (c.length <= FRG_MAX_PX || (c.length / ink <= FRG_MAX_SHARE && gap >= minGap)) {
      checks++;
      say(warn, 'FRG', `파편 후보 ${c.length}px(${(c.length / ink * 100).toFixed(1)}%) ${bboxOf(c)} gap=${gap} — 눈 판독 대상`);
    }
  }

  if (REPORT_ONLY) {
    reportRows.push(`${f.padEnd(26)} ${img.w}x${img.h} ct=${img.ctype} 성분=${comps.length} 본체=${main.length}px` +
      (comps.length > 1 ? `  › ${comps.slice(1).map((c) => `${c.length}px ${bboxOf(c)} gap=${chebyshevGap(c, main)}`).join(' | ')}` : ''));
  } else if (lines.length) {
    console.log(f);
    lines.forEach((fn) => fn());
  }
}

if (REPORT_ONLY) {
  reportRows.forEach((r) => console.log(r));
  console.log('');
  console.log('--report 는 선언값 산출용 덤프다. 선언은 icon_manifest.json 에 사유와 함께 적는다.');
  process.exit(0);
}

// 선언에만 있고 실물이 없는 파일 = 유령 선언
for (const name of Object.keys(decl)) {
  checks++;
  if (!files.includes(name)) fail('SEP', `선언에 있으나 실물 부재: ${name}`);
}

console.log('');
console.log(`ICON_CHECK ${fails === 0 ? 'PASS' : 'FAIL'} checks=${checks} fails=${fails} warnings=${warns}`);
process.exit(fails === 0 ? 0 : 1);
