#!/usr/bin/env node
/*
 * 얼굴 특징 좌표 제안기 — 표정 차분 34장의 원장 작성 보조.
 *
 * 소유: 에셋 트랙 (`tools/assets/`) · 신설 IMPL-362
 *
 * ── 왜 이 도구가 있는가.
 *    표정은 `shift`(구획 이동)로 만들고, 그러려면 인물마다 **눈썹·눈꺼풀·입선의 구획**을
 *    좌표로 알아야 한다. 13인을 눈으로만 재면 인물당 확대 렌더 3장 × 판독이 필요하다.
 *    이 도구는 **후보를 제안**하고, 사람은 확대 렌더 1장으로 **확인만** 한다.
 *
 * ── 무엇을 근거로 찾는가.
 *    얼굴은 어두운 띠가 위에서 아래로 **눈썹 → 눈 → 입** 순으로 놓인다. 그래서 머리 구획
 *    안에서 **행별 암부 밀도 프로파일**을 만들고 봉우리를 찾는다. 색이나 홍채에 의존하지
 *    않으므로 인물마다 다른 눈·머리 색에 흔들리지 않는다.
 *
 * ── 무엇을 하지 않는가 (검증한 척하지 않는다).
 *    **이것은 제안이고 판정이 아니다.** 머리카락이 얼굴을 덮는 인물, 안경, 수염은
 *    프로파일을 흐린다(사샤 = 안경 · 디아스 = 수염 · 홀로웨이 = 콧수염). 반드시 눈으로 확인한다.
 *
 * 사용:  node tools/assets/face_probe.js <시트.png> [크롭Y]
 */
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

function die(m) { console.error('FATAL: ' + m); process.exit(2); }
function decode(file) {
  const buf = fs.readFileSync(file);
  if (buf.readUInt32BE(0) !== 0x89504e47) die(`${file}: PNG 아님`);
  let o = 8, w = 0, h = 0, ct = -1; const parts = [];
  while (o + 8 <= buf.length) {
    const len = buf.readUInt32BE(o), type = buf.toString('ascii', o + 4, o + 8), data = buf.slice(o + 8, o + 8 + len);
    if (type === 'IHDR') { w = data.readUInt32BE(0); h = data.readUInt32BE(4); ct = data[9]; }
    if (type === 'IDAT') parts.push(data);
    if (type === 'IEND') break;
    o += 12 + len;
  }
  const CH = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[ct];
  if (!CH) die(`${file}: 지원 밖 color type ${ct}`);
  const inf = zlib.inflateSync(Buffer.concat(parts)), stride = w * CH, px = Buffer.alloc(h * stride);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < h; y++) {
    const f = inf[y * (stride + 1)];
    const cur = Buffer.from(inf.slice(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
    for (let i = 0; i < stride; i++) {
      const a = i >= CH ? cur[i - CH] : 0, b = prev[i], c = i >= CH ? prev[i - CH] : 0;
      let v = cur[i];
      if (f === 1) v += a; else if (f === 2) v += b; else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c); }
      cur[i] = v & 0xff;
    }
    cur.copy(px, y * stride); prev = cur;
  }
  const rgba = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    let r, g, b, a = 255;
    if (ct === 6) { r = px[i * 4]; g = px[i * 4 + 1]; b = px[i * 4 + 2]; a = px[i * 4 + 3]; }
    else if (ct === 2) { r = px[i * 3]; g = px[i * 3 + 1]; b = px[i * 3 + 2]; }
    else { r = g = b = px[i]; }
    rgba[i * 4] = r; rgba[i * 4 + 1] = g; rgba[i * 4 + 2] = b; rgba[i * 4 + 3] = a;
  }
  return { w, h, rgba };
}

const file = process.argv[2];
if (!file) die('사용: face_probe.js <시트.png> [크롭Y]');
const CROP_Y = process.argv[3] === undefined ? 20 : Number(process.argv[3]);
const im = decode(file);
if (im.w !== 180 || im.h !== 240) die(`${path.basename(file)}: ${im.w}×${im.h} — 스탠딩 시트는 180×240 이다`);
const L = (i) => (0.2126 * im.rgba[i * 4] + 0.7152 * im.rgba[i * 4 + 1] + 0.0722 * im.rgba[i * 4 + 2]) / 255;

// ── 얼굴 대역 = 시트 상단 절반의 불투명 구획. 그 안에서 **피부 중간톤**을 기준으로 암부를 센다.
//    절대 명도 문턱을 쓰면 짙은 피부(주드)에서 얼굴 전체가 암부로 잡힌다.
const band = [];
for (let y = 0; y < 140; y++) for (let x = 0; x < im.w; x++) { const i = y * im.w + x; if (im.rgba[i * 4 + 3]) band.push(L(i)); }
if (!band.length) die('불투명 픽셀 없음');
band.sort((a, b) => a - b);
const median = band[Math.floor(band.length / 2)];
const DARK = median * 0.55;                        // 피부 중간톤의 55% 미만 = 특징 암부
console.log(`${path.basename(file)} — 피부 중간톤 L=${median.toFixed(3)} · 암부 문턱 ${DARK.toFixed(3)}`);

// 행별 암부 개수 + 그 행의 암부 x 범위
const rows = [];
for (let y = 0; y < 150; y++) {
  let n = 0, x0 = 1e9, x1 = -1;
  for (let x = 0; x < im.w; x++) {
    const i = y * im.w + x;
    if (!im.rgba[i * 4 + 3] || L(i) >= DARK) continue;
    n++; if (x < x0) x0 = x; if (x > x1) x1 = x;
  }
  rows.push({ y, n, x0, x1 });
}
// 봉우리 = 국소 최대. 머리카락은 상단에 넓게 깔리므로 **얼굴 시작 행**부터 본다:
// 얼굴 시작 = 암부 개수가 한 번 크게 줄어드는 지점(이마)
let foreheadY = 0, minN = 1e9;
for (let y = 30; y < 80; y++) if (rows[y].n < minN) { minN = rows[y].n; foreheadY = y; }
console.log(`이마(암부 최소) y=${foreheadY} · n=${minN}`);

console.log('\n행별 암부 프로파일 (이마 아래):');
const peaks = [];
for (let y = foreheadY; y < 145; y++) {
  const r = rows[y];
  if (!r.n) continue;
  const bar = '#'.repeat(Math.min(60, Math.round(r.n / 2)));
  console.log(`  y${String(y).padStart(3)}  n=${String(r.n).padStart(3)}  x ${String(r.x0).padStart(3)}..${String(r.x1).padStart(3)}  ${bar}`);
  if (r.n > rows[y - 1].n && r.n >= rows[y + 1].n) peaks.push(y);
}
console.log(`\n국소 봉우리 y: ${peaks.join(' ')}`);

// 봉우리 행의 **암부 구간(run)** — 좌/우 눈썹·눈을 가르는 근거다. x0..x1 만 보면
// 머리카락이 양끝을 잡아 한 덩이로 보인다.
console.log('\n봉우리 행의 암부 구간 (2px 이상):');
for (const y of peaks) {
  const runs = [];
  let s0 = -1;
  for (let x = 0; x <= im.w; x++) {
    const i = y * im.w + x;
    const dark = x < im.w && im.rgba[i * 4 + 3] && L(i) < DARK;
    if (dark && s0 < 0) s0 = x;
    else if (!dark && s0 >= 0) { if (x - s0 >= 2) runs.push(`${s0}..${x - 1}(${x - s0})`); s0 = -1; }
  }
  console.log(`  y${String(y).padStart(3)}  ${runs.join('  ')}`);
}
// ── 눈 기준 자동 검출은 **시도했고 기각했다** (2026-08-23 · IMPL-362).
//
//    가설: 눈은 피부색과 무관한 구조적 서명(*암부에 둘러싸인 명부* — 속눈썹선 사이의 흰자·
//    홍채 하이라이트)을 가지므로, 그것을 잡으면 짙은 피부에서도 성립하고 나머지 특징은
//    얼굴 비례로 따라온다. 구현해서 4인에 돌렸다.
//
//    **결과: 4인 중 1인도 맞지 않았다.** 로렌츠는 **머리 하이라이트**를 눈으로 잡았고
//    (실제 눈 y81~89 를 y14~17 로 제안) 셔우드·주드는 쌍 자체를 못 찾았고, 사샤는 한쪽만
//    맞고 다른 쪽이 어깨 반사였다. 원인은 도트 렌더에 **눈만큼 밝고 눈처럼 둘러싸인 곳이
//    많다**는 것이다 — 머리 하이라이트, 금속 반사, 네온 림.
//
//    **확신 있게 틀린 값을 내는 도구는 없는 것보다 나쁘므로 제안부를 걷어냈다.** 남긴 것은
//    행별 암부 프로파일이며, 이것은 **판독 보조**다 — 봉우리가 눈썹·눈·코·입에 대응하는
//    것을 로렌츠에서 확인했다(79/87/101/120 = 실측과 일치). 깨끗한 얼굴에서 확대 렌더의
//    판독을 교차 검증하는 데 쓴다.
//
//    좌표 확정은 **확대 렌더 판독**으로 한다. 사양서 §3 이 이 계열을 아트 작업으로 두는
//    이유가 여기 있다 — 표정의 구획은 인물마다 다르고 기계가 대신 읽지 못한다.

console.log(`\n⚠ 이것은 **제안**이다 — 안경(사샤)·수염(디아스·홀로웨이)·앞머리는 프로파일을 흐린다. 확대 렌더로 확인할 것.`);
console.log(`크롭 좌표계로 옮길 때: crop = sheet − (34,${CROP_Y})`);
