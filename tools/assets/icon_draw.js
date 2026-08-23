#!/usr/bin/env node
/*
 * 손 작화 아이콘 렌더러 — `icon_art.json` 의 도상 정의 → `godot/assets/ui/icons/*.png`
 *
 * 소유: 에셋 트랙 (`tools/assets/` — IMPL-183 §2-⑧ 승인 경로)
 * 전례: IMPL-097 / IMPL-139 / IMPL-182 — **재현되는 것만 커밋한다.**
 *
 * ── 왜 이 도구가 있는가.
 *    아이콘 27종은 RD(Retro Diffusion) 생성물이다. 그런데 RD 가 못 내는 도상이 있다 —
 *    `achv_rival` 이 그 실증이며 **두 회차 연속 실패**했다(IMPL-162 "교차하는 두 헬멧이 32px 에서
 *    안 읽힌다" · IMPL-214 재시도 2시안 = 세로 점유 15행·12행으로 요구 미달·헬멧 미판독).
 *    그런 도상은 손으로 그린다. 그때 **PNG 바이트만 남기면 다음 편집자가 도상을 읽을 수 없고
 *    재현도 못 한다** — 3px 파편 하나를 고치려 해도 전체를 다시 디코드해야 한다.
 *    그래서 도상을 텍스트(ASCII 맵)로 두고 PNG 를 파생시킨다.
 *
 * ── `--check` 가 하는 일 (본체보다 이쪽이 요점이다).
 *    정의와 실물이 갈리는 것을 막는다. 누가 PNG 만 손대면 정의가 낡고, 정의만 손대면 실물이 낡는다.
 *    대장 §9-⑬ 의 규율 *"대조는 값이 두 곳에 있을 때만 성립한다"* 를 아이콘 원도에 적용한 것이다.
 *
 * ── 한계 (검증한 척하지 않는다).
 *    **`icon_art.json` 에 없는 아이콘은 대조 대상이 아니다.** RD 산출물은 도상 정의가 없으므로
 *    이 검사가 지키지 못하며, 그쪽은 `icon_check.js` 의 기하·팔레트 축과 눈 판독이 소관이다.
 *    본 도구는 색이 팔레트 안인지도 보지 않는다 — 그 축은 `icon_check.js` PAL 이 이미 가진다.
 *
 * ── `--proposal` (IMPL-305 신설).
 *    **판정 대기 도상을 유입시키지 않고 눈에 보이게 하는 경로다.** 원격은 화면을 못 보므로
 *    도상 판정에는 PNG 실물이 필요한데, 유입 원장(`icon_art.json`)에 적으면 그 순간
 *    `godot/assets/ui/icons/` 에 실물이 들어가고 매니페스트 계상이 따라온다.
 *    그래서 원장(`icon_art_proposal.json`)과 산출 경로(`docs/assets/시안/`)를 **둘 다** 갈랐다.
 *    `--proposal` 은 `ICON_DIR` 를 열지도 않는다 — 플래그 오타가 유입으로 번지는 길을 끊는다.
 *
 * 사용:  node tools/assets/icon_draw.js              (렌더 — PNG 를 쓴다)
 *        node tools/assets/icon_draw.js --check      (대조만 — 쓰지 않는다. 불일치 시 exit 1)
 *        node tools/assets/icon_draw.js --proposal   (시안 렌더 → docs/assets/시안/)
 *        node tools/assets/icon_draw.js --proposal --check
 */
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const CHECK_ONLY = process.argv.includes('--check');
const PROPOSAL = process.argv.includes('--proposal');

// **모르는 플래그는 거부한다.** 이 도구는 파일을 쓴다 — `bgm_gen.js --only` 사고(IMPL-280)가
// 실물 18개를 덮은 기제가 그대로 여기에도 있다: 오타 플래그가 조용히 무시되면 사용자가
// 의도한 것과 다른 대상이 재생성된다. 특히 `--proposal` 오타는 시안이 유입으로 번진다.
const KNOWN = new Set(['--check', '--proposal']);
const badFlags = process.argv.slice(2).filter((a) => a.startsWith('-') && !KNOWN.has(a));
if (badFlags.length) {
  console.error(`FATAL: 미지의 플래그 ${badFlags.join(' ')} — 알려진 것은 ${[...KNOWN].join(' ')}`);
  process.exit(2);
}

// 시안 모드는 유입 경로를 아예 잡지 않는다 (`ICON_DIR` 미참조).
const OUT_DIR = PROPOSAL
  ? path.join(ROOT, 'docs', 'assets', '시안')
  : path.join(ROOT, 'godot', 'assets', 'ui', 'icons');
const ART = path.join(__dirname, PROPOSAL ? 'icon_art_proposal.json' : 'icon_art.json');

let fails = 0;
function fail(msg) { console.error('  ✗ ' + msg); fails++; }
function die(msg) { console.error('FATAL: ' + msg); process.exit(2); }

// ─────────────────────────────────────────────────────────── 도상 → 픽셀
function hex2rgb(h) {
  const m = /^#([0-9A-Fa-f]{6})$/.exec(h);
  if (!m) die(`색값 형식 아님: ${h}`);
  return [0, 2, 4].map((i) => parseInt(m[1].substr(i, 2), 16));
}

function render(spec, name) {
  const n = spec.size;
  if (!Number.isInteger(n) || n < 1) die(`${name}: size 가 정수 아님`);
  const rgba = Buffer.alloc(n * n * 4); // 전면 투명에서 시작
  const pal = {};
  for (const [k, v] of Object.entries(spec.palette)) pal[k] = hex2rgb(v);

  for (const layer of spec.layers) {
    const [ox, oy] = layer.origin;
    const rows = layer.map;
    const w = rows[0].length;
    // 폭이 들쭉날쭉하면 도상이 아니라 오타다 — 조용히 넘기지 않는다
    rows.forEach((r, i) => { if (r.length !== w) die(`${name}: 층 행 ${i} 폭 ${r.length} != ${w}`); });
    for (let y = 0; y < rows.length; y++) {
      for (let x = 0; x < w; x++) {
        const ch = rows[y][x];
        if (ch === '.') continue;
        if (!pal[ch]) die(`${name}: 팔레트에 없는 글자 '${ch}' (행 ${y} 열 ${x})`);
        // mirror 는 **층 안에서만** 좌우 반전한다 — 캔버스 반전이 아니다.
        // 도트 축 반전이라 픽셀 손실이 0 인 것이 이 방식의 요점이다(IMPL-162 전례).
        const px = ox + (layer.mirror ? (w - 1 - x) : x);
        const py = oy + y;
        if (px < 0 || px >= n || py < 0 || py >= n) die(`${name}: 캔버스 밖 (${px},${py})`);
        const i = (py * n + px) * 4;
        const [r, g, b] = pal[ch];
        rgba[i] = r; rgba[i + 1] = g; rgba[i + 2] = b; rgba[i + 3] = 255;
      }
    }
  }
  return { n, rgba };
}

// ─────────────────────────────────────────────────────────── PNG 입출력
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

function encodePNG(n, rgba) {
  const stride = n * 4;
  const raw = Buffer.alloc(n * (stride + 1));
  for (let y = 0; y < n; y++) {
    raw[y * (stride + 1)] = 0; // 필터 0 — 32px 원도에서 필터는 이득이 없고 재현성만 해친다
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(n, 0); ihdr.writeUInt32BE(n, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// 되읽기는 실물 PNG 를 다시 디코드해서 한다 — 인코더가 자기 출력을 비교하면 대조가 아니다.
function decodeRGBA(file, n) {
  const buf = fs.readFileSync(file);
  if (buf.readUInt32BE(0) !== 0x89504e47) die(`${file}: PNG 아님`);
  const parts = [];
  let o = 8, w = 0, h = 0, ctype = -1;
  while (o + 8 <= buf.length) {
    const len = buf.readUInt32BE(o);
    const type = buf.toString('ascii', o + 4, o + 8);
    const data = buf.slice(o + 8, o + 8 + len);
    if (type === 'IHDR') { w = data.readUInt32BE(0); h = data.readUInt32BE(4); ctype = data[9]; }
    if (type === 'IDAT') parts.push(data);
    if (type === 'IEND') break;
    o += 12 + len;
  }
  if (w !== n || h !== n) return { mismatch: `치수 ${w}x${h} != ${n}x${n}` };
  if (ctype !== 6) return { mismatch: `color type ${ctype} != 6(RGBA)` };
  const idat = zlib.inflateSync(Buffer.concat(parts));
  const stride = n * 4;
  const px = Buffer.alloc(n * stride);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < n; y++) {
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

// ─────────────────────────────────────────────────────────── 주행
const art = JSON.parse(fs.readFileSync(ART, 'utf8'));
const names = Object.keys(art).filter((k) => !k.startsWith('_'));
if (names.length === 0) die(`${path.basename(ART)} 에 도상이 없다`);
if (!CHECK_ONLY) fs.mkdirSync(OUT_DIR, { recursive: true });

console.log(`${PROPOSAL ? '시안' : '손 작화 아이콘'} ${CHECK_ONLY ? '대조' : '렌더'} — ${names.length}종  → ${path.relative(ROOT, OUT_DIR)}\n`);

for (const name of names) {
  const spec = art[name];
  const { n, rgba } = render(spec, name);
  const file = path.join(OUT_DIR, name + '.png');
  let ink = 0;
  for (let i = 0; i < n * n; i++) if (rgba[i * 4 + 3]) ink++;

  if (CHECK_ONLY) {
    if (!fs.existsSync(file)) { fail(`${name}.png 부재 — 정의만 있고 실물이 없다`); continue; }
    const got = decodeRGBA(file, n);
    if (got.mismatch) { fail(`${name}.png ${got.mismatch}`); continue; }
    let diff = 0;
    for (let i = 0; i < n * n * 4; i++) if (got.px[i] !== rgba[i]) diff++;
    if (diff) fail(`${name}.png 가 정의와 다르다 — 바이트 ${diff}개 어긋남 (한쪽만 고쳐졌다)`);
    else console.log(`  ✓ ${name}.png  ${n}x${n} · 잉크 ${ink}`);
  } else {
    fs.writeFileSync(file, encodePNG(n, rgba));
    console.log(`  → ${name}.png  ${n}x${n} · 잉크 ${ink}`);
    // 쓴 직후 실물을 다시 디코드해 대조한다. 인코더가 옳다고 믿지 않는다.
    const got = decodeRGBA(file, n);
    if (got.mismatch) fail(`${name}.png 되읽기 ${got.mismatch}`);
    else {
      let diff = 0;
      for (let i = 0; i < n * n * 4; i++) if (got.px[i] !== rgba[i]) diff++;
      if (diff) fail(`${name}.png 되읽기 불일치 ${diff}바이트`);
    }
  }
}

if (fails) { console.error(`\nICON_DRAW${PROPOSAL ? '_PROPOSAL' : ''} FAIL fails=${fails}`); process.exit(1); }
console.log(`\nICON_DRAW${PROPOSAL ? '_PROPOSAL' : ''} ${CHECK_ONLY ? 'PASS' : 'OK'} icons=${names.length}`);
