#!/usr/bin/env node
/*
 * cut_layout.js — E15 컷 머신 배치 선언 렌더러 · 검수 시트 생성기
 *
 * 왜 도구인가:
 *   총괄 발주(IMPL-440 ④)는 컷 6종의 머신 2~4대 좌표를 **눈으로 확정**하라고 했다.
 *   눈으로 정하는 값이라도 **선언은 기계가 읽는 자리에 있어야** 회차 밖에서 재현된다 —
 *   `cut_layout.json` 이 정본이고 이 도구는 ⓐ실기 합성 검수 시트 ⓑ게이트 ⓒ표 전사용
 *   블록을 낸다. 좌표를 문서에만 적으면 다음 회차가 그 숫자를 다시 눈으로 정하게 된다.
 *
 * 앵커 규약 = **중심 좌표**다. `scene_cut_layers.csv` 의 fx 앵커가 중심임을 실측으로
 *   확인했다 — `fxe_slipstream`(64×32 @108,62) 과 `fxe_accel_afterimage`(96×32 @92,62)
 *   가 중심 해석에서 **둘 다 정확히 x=140** 에서 끝난다. 140 은 머신 표준 자리
 *   `[140,30,128,64]` 의 좌단이다. 두 원소가 독립적으로 같은 선에 맞는 것은 우연이 아니다.
 *   그러므로 머신 좌표도 중심으로 적는다 — 한 표에서 앵커 규약이 갈리면 안 된다.
 *
 * 게이트 (전부 차단형):
 *   ⓐ **프레임 밖 금지** — 머신은 캔버스 안에 온전히 든다. 선언적 잘림이 필요하면
 *      `allow_crop` 을 적어야 한다(적으면 그만큼만 허용).
 *   ⓑ **노면 대역** — 선언하는 y 는 **노면선(바퀴가 닿는 줄)이고 셀 중심이 아니다.**
 *      섀시 5종의 불투명 바닥이 셀 중심 기준 +11 ~ +19 로 **8px 흩어져 있다**
 *      (priv_common 11 · ax9/gm12 13 · vh8 18 · nw01 19). 그래서 같은 cy 를 주면
 *      차들이 서로 다른 높이에 서고, **SC-04 처럼 "같은 레인"이 뜻인 컷이 그 자리에서
 *      깨진다** — 실기 합성에서 눈으로 먼저 보였고 그 뒤에 계측이 확인했다.
 *      셀 중심은 그림이 어디 있는지 말하지 않는다. 그러므로 좌표를 노면선으로 적고
 *      `cy = road_y − 바닥오프셋` 을 도구가 푼다. 이 형식은 **해소 방향과 무관하게
 *      성립한다**: 섀시 셀을 정렬해 오프셋을 통일하든(구성 보장), 오프셋을 데이터로
 *      넘기든(소비부 계산) 같은 숫자가 쓰인다.
 *      대역 밖으로 나가면 위로는 차가 뜨고 아래로는 근경에 묻힌다. 세로 offset 은
 *      원근의 유일한 단서지만(비정수 축소는 도트 격자를 깬다 — 전 프로젝트 규칙)
 *      그 단서가 쓸 수 있는 폭은 노면 대역만큼이다.
 *   ⓒ **근경 가림 = 식별 대역(상반)이 살아 있는가** — 총량 문턱을 쓰지 않는다.
 *      총량으로 재면 두 번 헛돈다. ⓐ`bg_gen.js` 의 40% 는 *구획 안 행 비율* 이라는
 *      다른 척도의 값이라 그대로 옮기면 **남의 문턱**이 된다(mirage 표준 자리 =
 *      행 척도 18% 대 화소 척도 47%). ⓑ표준 자리 대비 초과분으로 바꿔도 여전히
 *      **선언된 의도를 위반으로 읽는다** — mirage 는 *"차가 모래에 앉는다"* 가 정본
 *      의도이므로(제원표 §4) 낮은 레인이 더 묻히는 것은 결함이 아니라 그 무대다.
 *      눈이 실제로 묻는 것은 총량이 아니다: **차로 읽히는가**, 즉 조종석·에어박스·
 *      윙 상단이 남았는가다. 근경은 언제나 아래에서 먹어 들어오므로 **스프라이트
 *      불투명 상반의 가림 = 0** 이 그 질문의 기계 형태다. 이 축은 metro 의 옛 참사
 *      (split 53 · 97% 가림)를 그대로 잡는다 — 그때 사라진 것이 바로 상반이었다.
 *      총량은 **정보로만** 찍는다(차단하지 않는다).
 *   ⓓ **상호 가림 상한** — 뒤 차가 앞 차에 가려 실루엣이 남지 않으면 대수가 거짓이
 *      된다(원격 4.2 가 관측으로 남긴 `multi_machine_omissions` 의 실체). 각 차의
 *      **보이는 화소 비율**을 재고 하한 미달이면 실패.
 *   ⓔ **fx 요충 회피** — fx 와 머신의 z 순서는 원격 소관이고 아직 선언이 없다.
 *      그러므로 좌표는 **어느 순서든 읽히도록** 정해야 한다: 큰 fx 원소가 차의
 *      조종석 대역(중심 ±16 가로 · 상반)을 덮는 비율에 상한을 둔다.
 *   ⓕ **대수 일치** — `scene_cuts.csv` 의 `machines` 와 선언 대수가 같아야 한다.
 *
 * 사용:  node tools/assets/cut_layout.js [--sheet <디렉토리>] [--table]
 */
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const SPEC = path.join(__dirname, 'cut_layout.json');
const CUTS_CSV = path.join(ROOT, 'godot/data/tables/scene_cuts.csv');
const LAYERS_CSV = path.join(ROOT, 'godot/data/tables/scene_cut_layers.csv');
const FXE_CSV = path.join(ROOT, 'godot/data/tables/fx_elements.csv');
const BDROP_CSV = path.join(ROOT, 'godot/data/tables/stage_backdrops.csv');

let FAILED = 0;
function die(m) { console.error('FATAL: ' + m); process.exit(2); }
function fail(m) { console.error('  ✗ ' + m); FAILED++; }
function ok(m) { console.log('  ✓ ' + m); }

// ─────────────────────────────────────────────── PNG (review_sheet.js 와 동일 구현)
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
  if (CH === undefined) die(`${path.basename(file)}: 지원 밖 color type ${ctype}`);
  if (depth !== 8 || inter !== 0) die(`${path.basename(file)}: depth=${depth} interlace=${inter}`);
  const idat = zlib.inflateSync(Buffer.concat(parts));
  const stride = w * CH;
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
    cur.copy(px, y * stride); prev = cur;
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

// ─────────────────────────────────────────────── CSV (읽기 전용 — 타 레인 소유)
function csv(file) {
  const lines = fs.readFileSync(file, 'utf8').trim().split(/\r?\n/);
  const head = lines[0].split(',');
  return lines.slice(1).map((l) => {
    const c = l.split(',');
    const o = {};
    head.forEach((h, i) => { o[h] = c[i] === undefined ? '' : c[i]; });
    return o;
  });
}

// ─────────────────────────────────────────────── 합성
function blit(dst, dw, dh, src, cx, cy) {
  // cx, cy = **중심** 좌표. 반환 = 캔버스 안에 놓인 화소 수 / 원본 불투명 화소 수
  const x0 = cx - (src.w >> 1), y0 = cy - (src.h >> 1);
  let inside = 0, total = 0;
  for (let y = 0; y < src.h; y++) for (let x = 0; x < src.w; x++) {
    const a = src.rgba[(y * src.w + x) * 4 + 3];
    if (!a) continue;
    total++;
    const dx = x0 + x, dy = y0 + y;
    if (dx < 0 || dy < 0 || dx >= dw || dy >= dh) continue;
    inside++;
    const di = (dy * dw + dx) * 4;
    src.rgba.copy(dst, di, (y * src.w + x) * 4, (y * src.w + x) * 4 + 4);
  }
  return { inside, total };
}
// 스프라이트의 불투명 세로 범위 (셀 안에 여백이 있으므로 셀 절반 ≠ 그림 절반)
const bboxCache = new Map();
function opaqueRows(src) {
  if (bboxCache.has(src)) return bboxCache.get(src);
  let top = src.h, bot = -1;
  for (let y = 0; y < src.h; y++) for (let x = 0; x < src.w; x++) {
    if (src.rgba[(y * src.w + x) * 4 + 3]) { if (y < top) top = y; if (y > bot) bot = y; break; }
  }
  const r = { top, bot, mid: Math.floor((top + bot) / 2) };
  bboxCache.set(src, r);
  return r;
}
function visibleMask(dst, dw, dh, src, cx, cy, region) {
  // 이 스프라이트의 화소가 지금 캔버스에 몇 개 남아 있는가 (색 일치로 센다).
  // region='upper' 면 **그림의 불투명 상반만** 센다 — 식별 대역이다.
  const x0 = cx - (src.w >> 1), y0 = cy - (src.h >> 1);
  const lim = region === 'upper' ? opaqueRows(src).mid : src.h;
  let seen = 0, total = 0;
  for (let y = 0; y <= lim && y < src.h; y++) for (let x = 0; x < src.w; x++) {
    const si = (y * src.w + x) * 4;
    if (!src.rgba[si + 3]) continue;
    total++;
    const dx = x0 + x, dy = y0 + y;
    if (dx < 0 || dy < 0 || dx >= dw || dy >= dh) continue;
    const di = (dy * dw + dx) * 4;
    if (dst[di] === src.rgba[si] && dst[di + 1] === src.rgba[si + 1] && dst[di + 2] === src.rgba[si + 2]) seen++;
  }
  return { seen, total };
}

// ─────────────────────────────────────────────── 본체
const argv = process.argv.slice(2);
let SHEET = null, TABLE = false;
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--sheet') SHEET = argv[++i];
  else if (argv[i] === '--table') TABLE = true;
  else die(`미지의 플래그 ${argv[i]}`);
}

const spec = JSON.parse(fs.readFileSync(SPEC, 'utf8'));
const CANVAS = spec.canvas;              // [408, 100]
const [CW, CH] = CANVAS;
const BAND = spec.road_band;             // [min_cy, max_cy]
const LIM = spec.limits;

const cuts = csv(CUTS_CSV);
const layers = csv(LAYERS_CSV);
const fxe = csv(FXE_CSV);
const bdrops = csv(BDROP_CSV);
const fxeById = {}; for (const e of fxe) fxeById[e.id] = e;

const machineCache = {};
function machine(file) {
  if (!machineCache[file]) machineCache[file] = decode(path.join(ROOT, file));
  return machineCache[file];
}

// 무대별 **표준 자리 가림 기준선** — 승인된 자리에서 근경이 머신을 얼마나 먹는가.
const baseCache = {};
function baseline(bd, spec) {
  if (baseCache[bd.stage_id] !== undefined) return baseCache[bd.stage_id];
  const far = decode(path.join(ROOT, `godot/assets/scenecuts/${bd.far_asset}.png`));
  const near = decode(path.join(ROOT, `godot/assets/scenecuts/${bd.near_asset}.png`));
  const spr = machine(spec.probe_sprite);
  const buf = Buffer.alloc(CW * CH * 4);
  far.rgba.copy(buf);
  const sx = spec.standard_slot[0];
  const sy = spec.standard_road_y - (opaqueRows(spr).bot - (spr.h >> 1));
  blit(buf, CW, CH, spr, sx, sy);
  for (let i = 0; i < CW * CH; i++) if (near.rgba[i * 4 + 3]) near.rgba.copy(buf, i * 4, i * 4, i * 4 + 4);
  const v = visibleMask(buf, CW, CH, spr, sx, sy);
  const hidden = v.total ? 1 - v.seen / v.total : 1;
  baseCache[bd.stage_id] = hidden;
  return hidden;
}

// ── 노면 대역 하한은 **유도된다.** 근경이 식별 대역(상반)을 먹기 시작하는 줄이 그 값이고,
//    무대 × 섀시 전 조합의 최소값이다. 상한은 유도되지 않는다("떠 보인다"는 눈 판단).
//    유도해 두는 이유: 근경 행수나 섀시 높이가 바뀌면 하한도 따라 움직여야 하는데,
//    손으로 적은 숫자는 따라오지 않는다.
function derivedLowerBound() {
  const chassis = new Set([spec.probe_sprite]);
  for (const d of Object.values(spec.cuts)) for (const sl of d.slots) if (sl.sprite) chassis.add(sl.sprite);
  let best = Infinity, who = '';
  for (const bd of bdrops) {
    const far = decode(path.join(ROOT, `godot/assets/scenecuts/${bd.far_asset}.png`));
    const near = decode(path.join(ROOT, `godot/assets/scenecuts/${bd.near_asset}.png`));
    for (const f of chassis) {
      const spr = machine(f), off = opaqueRows(spr).bot - (spr.h >> 1);
      let last = -1;
      for (let ry = BAND[0]; ry <= CH; ry++) {
        const cy = ry - off;
        const solo = Buffer.alloc(CW * CH * 4);
        far.rgba.copy(solo);
        blit(solo, CW, CH, spr, spec.standard_slot[0], cy);
        for (let i = 0; i < CW * CH; i++) if (near.rgba[i * 4 + 3]) near.rgba.copy(solo, i * 4, i * 4, i * 4 + 4);
        const u = visibleMask(solo, CW, CH, spr, spec.standard_slot[0], cy, 'upper');
        if (u.total && u.seen === u.total) last = ry; else break;
      }
      if (last < best) { best = last; who = `${bd.stage_id} × ${path.basename(f)}`; }
    }
  }
  return { bound: best, who };
}
const LB = derivedLowerBound();
console.log(`캔버스 ${CW}×${CH} · 노면선 대역 ${BAND[0]}~${BAND[1]} · 무대 ${bdrops.length}`);
console.log(`  유도 하한 = ${LB.bound} (구속 = ${LB.who}) · 선언 하한 ${BAND[1]}`);
if (BAND[1] > LB.bound) die(`선언 하한 ${BAND[1]} 이 유도 하한 ${LB.bound} 보다 낮다 — ${LB.who} 에서 식별 대역이 먹힌다`);

const sheets = [];
for (const [cutId, decl] of Object.entries(spec.cuts)) {
  const cut = cuts.find((c) => c.id === cutId);
  if (!cut) { fail(`${cutId}: scene_cuts.csv 에 없다`); continue; }
  const want = parseInt(cut.machines, 10);
  const slots = decl.slots;

  // ⓕ 대수 일치
  if (slots.length !== want) { fail(`${cut.cut_code}: 선언 ${slots.length}대 ≠ 표 machines=${want}`); continue; }

  const myLayers = layers.filter((l) => l.cut_id === cutId)
    .sort((a, b) => parseInt(a.layer_order, 10) - parseInt(b.layer_order, 10));

  let worstOccl = 0, worstOcclStage = '', worstUpper = 0, worstUpperWho = '', worstVis = 1, worstVisSlot = '', worstFx = 0, worstFxWho = '';

  for (const bd of bdrops) {
    const far = decode(path.join(ROOT, `godot/assets/scenecuts/${bd.far_asset}.png`));
    const near = decode(path.join(ROOT, `godot/assets/scenecuts/${bd.near_asset}.png`));
    if (far.w !== CW || far.h !== CH) die(`${bd.far_asset}: ${far.w}×${far.h} ≠ 캔버스`);

    const buf = Buffer.alloc(CW * CH * 4);
    far.rgba.copy(buf);

    // 머신 — 선언 순서대로(먼저 = 뒤). 원경 위·근경 아래 (제원표 §4).
    const placed = [];
    for (const s0 of slots) {
      const spr = machine(s0.sprite || spec.probe_sprite);
      // 노면선 → 셀 중심. 섀시별 바닥 오프셋이 8px 흩어져 있으므로 여기서 푼다.
      const cy = s0.road_y - (opaqueRows(spr).bot - (spr.h >> 1));
      const s = Object.assign({}, s0, { cy });
      // ⓑ 노면 대역 (노면선 기준)
      if (s0.road_y < BAND[0] || s0.road_y > BAND[1]) {
        fail(`${cut.cut_code}/${s.name}: road_y=${s0.road_y} 가 노면 대역 ${BAND[0]}~${BAND[1]} 밖이다 — 위로는 뜨고 아래로는 근경에 묻힌다`);
      }
      const r = blit(buf, CW, CH, spr, s.cx, s.cy);
      // ⓐ 프레임 밖
      const out = r.total - r.inside;
      const allow = s.allow_crop === undefined ? 0 : s.allow_crop;
      if (out > allow) {
        fail(`${cut.cut_code}/${s.name}: ${out}px 가 프레임 밖이다 (허용 ${allow}) — 잘림은 선언해야 한다`);
      }
      placed.push({ s, spr });
    }

    // ⓓ 상호 가림 — 전 대수 배치가 끝난 상태에서 각 차가 몇 % 남았는가
    for (const p of placed) {
      const v = visibleMask(buf, CW, CH, p.spr, p.s.cx, p.s.cy);
      const frac = v.total ? v.seen / v.total : 0;
      if (frac < worstVis) { worstVis = frac; worstVisSlot = `${bd.stage_id}/${p.s.name}`; }
      if (frac < LIM.min_visible) {
        fail(`${cut.cut_code}/${p.s.name} @${bd.stage_id}: 실루엣이 ${(frac * 100).toFixed(0)}% 만 남는다 (하한 ${(LIM.min_visible * 100)}%) — 표의 machines 가 거짓이 된다`);
      }
    }

    // ⓒ 근경 가림 — **차 한 대만 놓고** 잰다. 기준선도 한 대이므로 같은 척도가 된다.
    //   두 번 틀렸고 두 번 다 같은 잘못이었다: 합성물을 재면서 한 가지 이름을 붙였다.
    //   ①fx 를 얹은 뒤에 재서 SC-01 이 *표준 자리 그 자체인데* 기준선보다 21%p 나쁘게 나왔다
    //   ②fx 를 뺐더니 이번엔 전 대수가 올라간 상태라 **cy 56(더 높은 자리)이 cy 62 보다
    //     19%p 더 가려졌다** — 근경은 아래에 있으므로 높이 둔 차가 더 가려질 수 없다.
    //     그 모순이 상호 가림이 섞여 있다는 신호였다(SC-02 lead↔mid 겹침 58px).
    //   섞인 수치는 무엇을 고쳐야 하는지도 말해주지 않는다 — 근경을 올릴지, 차를 옮길지,
    //   fx 를 옮길지가 한 숫자 안에서 구분되지 않는다. **축마다 캔버스를 따로 세운다.**
    const base = baseline(bd, spec);
    for (const p of placed) {
      const solo = Buffer.alloc(CW * CH * 4);
      far.rgba.copy(solo);
      blit(solo, CW, CH, p.spr, p.s.cx, p.s.cy);
      for (let i = 0; i < CW * CH; i++) if (near.rgba[i * 4 + 3]) near.rgba.copy(solo, i * 4, i * 4, i * 4 + 4);
      const v = visibleMask(solo, CW, CH, p.spr, p.s.cx, p.s.cy);
      const hidden = v.total ? 1 - v.seen / v.total : 1;
      if (hidden > worstOccl) { worstOccl = hidden; worstOcclStage = `${bd.stage_id}/${p.s.name}`; }
      const u = visibleMask(solo, CW, CH, p.spr, p.s.cx, p.s.cy, 'upper');
      const upper = u.total ? 1 - u.seen / u.total : 1;
      if (upper > worstUpper) { worstUpper = upper; worstUpperWho = `${bd.stage_id}/${p.s.name}`; }
      if (upper > LIM.max_upper_occlusion) {
        fail(`${cut.cut_code}/${p.s.name} @${bd.stage_id}: 근경이 **식별 대역(상반)** 을 ${(upper * 100).toFixed(0)}% 먹는다 (상한 ${LIM.max_upper_occlusion * 100}%) — 총량은 ${(hidden * 100).toFixed(0)}%, 표준 자리 ${(base * 100).toFixed(0)}%`);
      }
    }

    // fx — 표 순서대로 얹는다 (z 순서는 원격 소관 · 여기서는 최악을 보려고 위에 둔다)
    const fxBoxes = [];
    for (const l of myLayers) {
      const e = fxeById[l.element_id];
      if (!e) { fail(`${cut.cut_code}: fx_elements 에 ${l.element_id} 없다`); continue; }
      const file = path.join(ROOT, `godot/assets/scenecuts/${e.asset}.png`);
      if (!fs.existsSync(file)) { fail(`없는 fx 실물 ${e.asset}.png`); continue; }
      const sheet = decode(file);
      const cw = parseInt(e.cell_w, 10), ch = parseInt(e.cell_h, 10);
      const fr = parseInt(e.still_frame, 10) || 0;
      // 스프라이트 시트에서 정지 프레임 1컷만 뽑는다
      const cell = { w: cw, h: ch, rgba: Buffer.alloc(cw * ch * 4) };
      for (let y = 0; y < ch; y++) for (let x = 0; x < cw; x++) {
        const sx = fr * cw + x;
        if (sx >= sheet.w || y >= sheet.h) continue;
        sheet.rgba.copy(cell.rgba, (y * cw + x) * 4, (y * sheet.w + sx) * 4, (y * sheet.w + sx) * 4 + 4);
      }
      const ax = parseInt(l.anchor_x, 10), ay = parseInt(l.anchor_y, 10);
      blit(buf, CW, CH, cell, ax, ay);
      fxBoxes.push({ id: l.element_id, x0: ax - (cw >> 1), y0: ay - (ch >> 1), x1: ax + (cw >> 1), y1: ay + (ch >> 1) });
    }

    // ⓔ fx 요충 회피 — 조종석 대역 = 중심 ±16 가로 · 상반(cy-32 ~ cy)
    for (const p of placed) {
      const kx0 = p.s.cx - 16, kx1 = p.s.cx + 16, ky0 = p.s.cy - 32, ky1 = p.s.cy;
      const area = (kx1 - kx0) * (ky1 - ky0);
      let covered = 0;
      for (let y = ky0; y < ky1; y++) for (let x = kx0; x < kx1; x++) {
        for (const b of fxBoxes) if (x >= b.x0 && x < b.x1 && y >= b.y0 && y < b.y1) { covered++; break; }
      }
      const frac = area ? covered / area : 0;
      if (frac > worstFx) { worstFx = frac; worstFxWho = `${p.s.name}`; }
      if (frac > LIM.max_fx_over_cockpit) {
        fail(`${cut.cut_code}/${p.s.name}: fx 가 조종석 대역을 ${(frac * 100).toFixed(0)}% 덮는다 (상한 ${LIM.max_fx_over_cockpit * 100}%) — z 순서가 어느 쪽이든 읽혀야 한다`);
      }
    }

    // 근경 (검수 시트용 — 게이트 ⓒ 는 위에서 이미 쟀다)
    for (let i = 0; i < CW * CH; i++) if (near.rgba[i * 4 + 3]) near.rgba.copy(buf, i * 4, i * 4, i * 4 + 4);

    if (SHEET && bd.stage_id === spec.sheet_stage) {
      sheets.push({ name: `${cut.cut_code}_${cutId}`, w: CW, h: CH, rgba: buf });
    }
    if (SHEET && spec.sheet_stage_worst && bd.stage_id === spec.sheet_stage_worst) {
      sheets.push({ name: `${cut.cut_code}_${bd.stage_id}`, w: CW, h: CH, rgba: buf });
    }
  }

  ok(`${cut.cut_code} ${slots.length}대 [${decl.pattern}] · 상반 가림 ${(worstUpper * 100).toFixed(0)}%(${worstUpperWho}) · 총량 ${(worstOccl * 100).toFixed(0)}%(${worstOcclStage})`
    + ` · 최소 실루엣 ${(worstVis * 100).toFixed(0)}%(${worstVisSlot})`
    + ` · fx/조종석 ${(worstFx * 100).toFixed(0)}%(${worstFxWho})`);
}

if (SHEET) {
  fs.mkdirSync(SHEET, { recursive: true });
  const K = spec.sheet_scale || 3;
  for (const s of sheets) {
    const w = s.w * K, h = s.h * K;
    const out = Buffer.alloc(w * h * 4);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const si = (((y / K) | 0) * s.w + ((x / K) | 0)) * 4;
      s.rgba.copy(out, (y * w + x) * 4, si, si + 4);
    }
    const f = path.join(SHEET, `${s.name}.png`);
    fs.writeFileSync(f, encode(w, h, out));
    console.log(`  → ${f}  ${w}×${h}  ×${K}`);
  }
}

if (TABLE) {
  console.log('\n--- 전사용 블록 ① 머신 자리 (anchor_y = **노면선** · slot_order = 그리는 순서) ---');
  console.log('cut_id,slot_name,slot_order,anchor_x,anchor_road_y');
  for (const [cutId, decl] of Object.entries(spec.cuts)) {
    decl.slots.forEach((s, i) => console.log(`${cutId},${s.name},${i + 1},${s.cx},${s.road_y}`));
  }
  console.log('\n--- 전사용 블록 ② 섀시 바닥 오프셋 ---');
  console.log('#  셀 중심 y  = anchor_road_y - baseline_offset');
  console.log('#  좌상단 y   = 셀 중심 y - cell_h/2      (좌상단 x = anchor_x - cell_w/2)');
  console.log('#  baseline_offset = 불투명 바닥행 - cell_h/2  (셀 중심에서 바퀴까지)');
  console.log('chassis_sprite,cell_h,opaque_top,opaque_bottom,baseline_offset');
  const seen = new Set();
  for (const decl of Object.values(spec.cuts)) for (const s of decl.slots) {
    const f = s.sprite || spec.probe_sprite;
    if (seen.has(f)) continue; seen.add(f);
    const spr = machine(f), r = opaqueRows(spr);
    console.log(`${path.basename(f)},${spr.h},${r.top},${r.bot},${r.bot - (spr.h >> 1)}`);
  }
}

if (FAILED) { console.error(`\nCUT_LAYOUT FAIL 위반 ${FAILED}건`); process.exit(1); }
console.log(`\nCUT_LAYOUT PASS cuts=${Object.keys(spec.cuts).length}`);
