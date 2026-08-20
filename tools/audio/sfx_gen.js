#!/usr/bin/env node
/*
 * SFX 절차 생성기 — `sfx_params.json` → `godot/assets/audio/sfx/*.wav`
 *
 * 소유: 에셋 트랙 (`tools/audio/` — 총괄 발주 §7.1 소유 경로 확장 선언분)
 * 전례: `tools/palette/swatch_gen.js` · `tools/assets/icon_draw.js` — **재현 = 같은 명령.**
 *
 * ── 도구 선정 (근거는 회신문 §1, 요지만 적는다).
 *    jsfxr 1.4.1 을 **벤더링**해 쓴다(`vendor/` · UNLICENSE = 퍼블릭 도메인 · 런타임 의존 0).
 *    npm 의존이 아니라 사본인 이유 = 재생성이 네트워크·레지스트리·버전 해석에 걸리면
 *    재현 계약이 성립하지 않기 때문이다. 상류 대조 해시는 `vendor/PROVENANCE.md`.
 *
 * ── 결정성 (이 파일의 핵심 장치).
 *    상류는 잡음 합성에 `Math.random` 을 쓴다 — 그대로 두면 **같은 파라미터가 다른 바이트**를 낸다
 *    (실측: wave_type 3 에서 2회 생성 해시 불일치). 그래서 생성 구간에만 `Math.random` 을
 *    **항목별 seed 의 PRNG(mulberry32)로 갈아끼우고 끝나면 되돌린다.**
 *    벤더 사본은 한 바이트도 고치지 않는다 — 고치면 상류 해시 대조가 죽는다.
 *
 * ── `compose` (2026-08-19 신설 · 잔여 60식 회차).
 *    sfxr 포락선은 **어택·서스테인·디케이 1벌**이라 한 번의 합성으로 "2타"를 낼 수 없다
 *    (`p_repeat_speed` 는 주파수만 되돌리고 진폭 포락선은 되돌리지 않는다 — 상류 실독).
 *    D11 이 타수를 확정으로 못박은 항목(`se_t02` "고음·2타" · `se_u18` 시그널 시퀀스)이 있으므로
 *    **단계별 합성 → 무음 간격으로 이어붙이기**를 생성기 층에 둔다. 각 단계는 `params` 를
 *    상속하고 덮어쓰기만 선언한다. **seed = entry.seed + 단계 인덱스** 로 단계마다 결정적이다.
 *    이어붙이기는 **1단계 산출물의 WAV 헤더 44바이트를 그대로 재사용**하고 크기 2필드만 고쳐
 *    비합성 항목과 헤더 형식이 갈리지 않게 한다.
 *
 * ── `--check` 가 하는 일.
 *    파라미터를 다시 합성해 **디스크의 WAV 와 바이트 대조**한다. 한쪽만 고쳐지는 것을 막는다
 *    (`icon_draw.js --check` 와 같은 계약). 겸해서 WAV 헤더 3항을 **파일 바이트에서 직접 읽어** 검사한다
 *    — 생성기가 스스로 보고한 헤더를 믿지 않는다. `--twice` 는 디스크를 보지 않고
 *    **같은 항목을 2회 합성해 해시를 대조**한다(잡음 계열 결정성의 독립 축).
 *
 * ── 한계 (검증한 척하지 않는다).
 *    **소리가 좋은지는 보지 않는다.** 이 도구가 보는 것은 규격(포맷·길이·클리핑·무음)뿐이고,
 *    톤 판정은 귀 소관이다(발주 §7.1·잔여 60식 발주 §5-⑥ — 에셋은 표본까지).
 *    다만 **선언한 파라미터가 출력에 도달하는지는 본다**(`deadParams` — 아르페지오·반복·비브라토의
 *    발화 시점이 포락선 길이 밖이면 경고). 이것은 소리의 좋음이 아니라 파라미터의 실효 여부다.
 *    루프 항목의 `seam` 은 **첫·끝 샘플 진폭 차**일 뿐이다 — 위상 불연속·잡음 질감의 이음매는
 *    이 수치가 0 이어도 들릴 수 있다. 수치는 단서이고 판정이 아니다.
 *
 * ── 소관 (2026-08-20 확장).
 *    SFX 68식(`audio/sfx/`) + **징글 5식(`audio/jingle/` — 항목이 `dir` 로 선언한다)**.
 *    징글은 SFX 버스 귀속·덕킹 주체라 SFX 포맷을 준용한다(대장 §9-② [가안] 유지).
 *    `jg_04` 는 **메인 모티프를 인용**하며 원장은 `motif.json` 이다 — `checkMotif` 가 대조한다.
 *
 * 사용:  node tools/audio/sfx_gen.js           (생성 — WAV 를 쓴다)
 *        node tools/audio/sfx_gen.js --check   (대조만 — 쓰지 않는다. 불일치 시 exit 1)
 *        node tools/audio/sfx_gen.js --twice   (2회 합성 해시 대조 — 디스크 무관)
 *        node tools/audio/sfx_gen.js --only=se_t02,amb_01   (부분 주행 — 생성 회차 분할 · deadParams 차단 우회)
 */
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const sfxr = require('./vendor/sfxr.js');

const ROOT = path.resolve(__dirname, '..', '..');
const AUDIO_ROOT = path.join(ROOT, 'godot', 'assets', 'audio');
const outDirFor = (e) => path.join(AUDIO_ROOT, e.dir || 'sfx');   // 항목이 dir 을 선언하면 그 하위 (징글 = 'jingle')
const PARAMS = path.join(__dirname, 'sfx_params.json');
const MOTIF = path.join(__dirname, 'motif.json');
const CHECK_ONLY = process.argv.includes('--check');
const TWICE = process.argv.includes('--twice');
const ONLY = (() => {
  const a = process.argv.find((x) => x.startsWith('--only='));
  return a ? new Set(a.slice(7).split(',').filter(Boolean)) : null;
})();

// D12 §10.1 확정 포맷 — 항목별로 적지 않고 여기서 강제한다
const SAMPLE_RATE = 44100;
const SAMPLE_SIZE = 16;
const HEADER_BYTES = 44;   // RIFF(12) + fmt (24) + data 헤더(8) — riffwave 산출 형식

let fails = 0;
const fail = (m) => { console.error('  ✗ ' + m); fails++; };
const warn = (m) => { console.log('  ⚠ ' + m); };
const die = (m) => { console.error('FATAL: ' + m); process.exit(2); };

// mulberry32 — 짧고 결정적. 암호 용도가 아니라 재현 용도다.
function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// 단발 합성 — params 한 벌 · seed 한 개.
function synthOne(id, params, seed) {
  const p = new sfxr.Params();
  p.sample_rate = SAMPLE_RATE;
  p.sample_size = SAMPLE_SIZE;
  for (const [k, v] of Object.entries(params)) {
    if (!(k in p)) die(`${id}: 미지의 파라미터 '${k}' — sfxr 규격 밖이다`);
    if (typeof v !== 'number' || !Number.isFinite(v)) die(`${id}: ${k} 가 수가 아니다`);
    p[k] = v;
  }
  const orig = Math.random;
  Math.random = mulberry32(seed);
  try {
    const rendered = new sfxr.SoundEffect(p).generate();
    return { wav: Buffer.from(rendered.wav), clipping: rendered.clipping | 0 };
  } finally {
    Math.random = orig;
  }
}

// 항목 합성 — compose 선언이 있으면 단계별로 합성해 이어붙인다.
function synth(entry) {
  if (typeof entry.seed !== 'number') die(`${entry.id}: seed 가 없다 — 결정성이 보장되지 않는다`);
  if (!entry.compose) return synthOne(entry.id, entry.params, entry.seed);

  const c = entry.compose;
  if (!Array.isArray(c.steps) || c.steps.length < 2) die(`${entry.id}: compose.steps 가 2 미만이다`);
  if (typeof c.gap_ms !== 'number' || c.gap_ms < 0) die(`${entry.id}: compose.gap_ms 가 없다`);
  const gapBytes = Math.round(c.gap_ms / 1000 * SAMPLE_RATE) * 2;

  let clipping = 0;
  let head = null;
  const chunks = [];
  c.steps.forEach((over, i) => {
    if (typeof over !== 'object' || over === null) die(`${entry.id}: compose.steps[${i}] 가 객체가 아니다`);
    const merged = Object.assign({}, entry.params, over);
    const r = synthOne(entry.id, merged, entry.seed + i);
    clipping += r.clipping;
    if (head === null) head = r.wav.subarray(0, HEADER_BYTES);
    const h = readWavHeader(r.wav, entry.id);
    if (h.err) die(h.err);
    if (h.dataStart !== HEADER_BYTES) die(`${entry.id}: 단계 ${i} 헤더가 ${h.dataStart}B — 44B 전제와 다르다`);
    if (i > 0 && gapBytes > 0) chunks.push(Buffer.alloc(gapBytes));
    chunks.push(r.wav.subarray(h.dataStart, h.dataStart + h.dataSize));
  });

  const data = Buffer.concat(chunks);
  const wav = Buffer.concat([Buffer.from(head), data]);
  wav.writeUInt32LE(36 + data.length, 4);    // RIFF 크기
  wav.writeUInt32LE(data.length, 40);        // data 크기
  return { wav, clipping };
}

// 선언한 파라미터가 출력에 도달하는가 (2026-08-19 신설 · **차단형 전환 2026-08-20 IMPL-265**).
// sfxr 의 아르페지오·반복·비브라토는 **시점**을 가진다 — 발화 시점이 포락선 길이 밖이면
// 값을 적어도 소리에 없다. 실제로 6건이 이 상태로 생성됐고(같은 파라미터의 두 항목이
// 바이트까지 동일해져서 드러났다 — `se_u02`/`se_u03` 은 방향 반전 쌍이 같은 파일이 되는 사고였다),
// 그중 1건은 파일럿 `se_r04` 였다.
//
// **차단형 (총괄 판정 IMPL-261 ⑧ 승인 — 조건 2건 명문).**
//   ⓐ **차단 대상이 빌드가 아니라 생성이다.** 이 검사의 거처는 생성기이므로 미발화 1건으로
//      전량 생성이 멈춘다(검증기의 빌드 게이트 차단과 성격이 다르다 — 대장·검증기 열거에서
//      성격을 갈라 적는다). 작업 중 부분 주행은 `--only=<id>` 로 우회한다.
//   ⓑ **이 공식은 `vendor/sfxr.js` 산술의 복제다.** 벤더 사본을 갱신하면 공식이 어긋날 수 있고
//      그때는 **정상 파라미터가 생성을 막는다.** 따라서 **벤더 갱신 시 발화 시점 공식 재확인이
//      절차 조건**이다(대장 §7 전사분). 현행 위험은 잠재적이다 — `vendor/PROVENANCE.md` 가
//      1.4.1 을 핀하고 사본이 바이트 동결이며 갱신은 명시적 행위다.
//
// 경고형으로 둔 유일한 사유(파일럿 `se_r04` 존치)는 IMPL-262 의 수정으로 소멸했다.
// 커버리지 실측 — "선언했는데 무력한 값" 의 다른 갈래 5종(듀티/비구형파 · LPF램프·공진/필터꺼짐 ·
// HPF램프/HPF0 · 비브속도/강도0 · arp속도/mod0)은 68식 전수에서 **0건**이라 확장을 넣지 않았다.
// 주체가 0건인 규칙을 세우면 검사만 커지고 지키는 것이 없다(총괄 승인·기록).
function deadParams(id, p) {
  const env = Math.floor((p.p_env_attack || 0) ** 2 * 1e5)
    + Math.floor((p.p_env_sustain || 0) ** 2 * 1e5)
    + Math.floor((p.p_env_decay || 0) ** 2 * 1e5);
  const out = [];
  if (p.p_arp_mod) {
    const at = p.p_arp_speed === 1 ? 0 : Math.floor((1 - (p.p_arp_speed || 0)) ** 2 * 20000 + 32);
    if (at >= env) out.push(`아르페지오 미발화 (발화 ${at}샘플 >= 길이 ${env}샘플)`);
  }
  if (p.p_repeat_speed) {
    const rt = Math.floor((1 - p.p_repeat_speed) ** 2 * 20000 + 32);
    if (rt >= env) out.push(`반복 미발화 (주기 ${rt}샘플 >= 길이 ${env}샘플)`);
  }
  if (p.p_vib_strength && !p.p_vib_speed) out.push('비브라토 미발화 (p_vib_speed 0)');
  for (const m of out) fail(`${id}: ${m} — 선언이 출력에 도달하지 않는다`);
}


// 메인 모티프 대조 (2026-08-20 신설 · 총괄 기안 §2.1 "모티프의 원장은 한 곳").
// `motif.json` 이 원장이고 `jg_04` 가 그것을 인용한다 — 두 곳에 값이 있으므로 대조한다
// (대장 §9-⑬ *"대조는 값이 두 곳에 있을 때만 성립한다"* 의 반전 적용 · `icon_draw.js` 와 같은 계약).
// BGM-01·BGM-12 도 이 원장을 승계하므로 여기서 갈리면 세 곳이 조용히 어긋난다.
function checkMotif(sounds) {
  if (!fs.existsSync(MOTIF)) { fail('motif.json 부재 — 모티프 원장이 없다'); return; }
  const motif = JSON.parse(fs.readFileSync(MOTIF, 'utf8')).main;
  const notes = ((motif.rendered_in_jingle || {}).notes) || [];
  const deg = motif.degrees_semitones_from_root || [];
  if (notes.length !== deg.length) {
    fail(`motif.json: 음 ${notes.length}개 != 오프셋 ${deg.length}개`);
    return;
  }
  // 오프셋 → 헤르츠가 실제로 맞는가 (원장 자체의 자기 정합 — 반음비 2^(1/12))
  const rootHz = ((motif.root_reference || {}).hz) || 0;
  notes.forEach((n, i) => {
    const want = rootHz * Math.pow(2, deg[i] / 12);
    if (Math.abs(1200 * Math.log2(n.hz / want)) > 1) {
      fail(`motif.json[${i}] ${n.name}: ${n.hz}Hz 가 오프셋 ${deg[i]} 반음(${want.toFixed(2)}Hz)과 어긋난다`);
    }
  });
  const jg = sounds.find((s) => s.id === 'jg_04');
  if (!jg) {
    // 부분 주행이면 대상 밖이다. 전량 주행에서 없으면 **원장만 있고 인용부가 없는 상태**이므로 실패다.
    if (!ONLY) fail('jg_04 미등재 — 모티프 원장이 있는데 인용부가 없다');
    return;
  }
  const steps = (jg.compose || {}).steps || [];
  if (steps.length !== notes.length) {
    fail(`jg_04: compose 단계 ${steps.length} != 모티프 음 ${notes.length}개`);
    return;
  }
  steps.forEach((s, i) => {
    const got = s.p_base_freq !== undefined ? s.p_base_freq : jg.params.p_base_freq;
    if (got !== notes[i].p_base_freq) {
      fail(`jg_04 단계 ${i}: p_base_freq ${got} != 모티프 원장 ${notes[i].p_base_freq} (${notes[i].name}) — 한쪽만 고쳐졌다`);
    }
  });
}

// 헤더는 **파일 바이트에서** 읽는다. 합성기가 돌려준 header 객체를 쓰면 대조가 아니다.
function readWavHeader(buf, label) {
  if (buf.length < 44) return { err: `${label}: 44바이트 미만 — WAV 가 아니다` };
  if (buf.toString('ascii', 0, 4) !== 'RIFF') return { err: `${label}: RIFF 시그니처 없음` };
  if (buf.toString('ascii', 8, 12) !== 'WAVE') return { err: `${label}: WAVE 형식 아님` };
  let o = 12, fmt = null;
  while (o + 8 <= buf.length) {
    const id = buf.toString('ascii', o, o + 4);
    const sz = buf.readUInt32LE(o + 4);
    if (id === 'fmt ') {
      fmt = {
        audioFormat: buf.readUInt16LE(o + 8),
        numChannels: buf.readUInt16LE(o + 10),
        sampleRate: buf.readUInt32LE(o + 12),
        byteRate: buf.readUInt32LE(o + 16),
        blockAlign: buf.readUInt16LE(o + 20),
        bitsPerSample: buf.readUInt16LE(o + 22),
      };
    } else if (id === 'data') {
      const align = fmt ? fmt.blockAlign : 2;
      const frames = sz / align;
      let peak = 0;
      const end = Math.min(o + 8 + sz, buf.length);
      for (let i = o + 8; i + 1 < end; i += 2) {
        const v = Math.abs(buf.readInt16LE(i));
        if (v > peak) peak = v;
      }
      const first = sz >= 2 ? buf.readInt16LE(o + 8) : 0;
      const last = sz >= 2 ? buf.readInt16LE(end - 2) : 0;
      return {
        fmt, dataSize: sz, dataStart: o + 8, frames,
        seconds: frames / (fmt ? fmt.sampleRate : SAMPLE_RATE), peak, first, last,
      };
    }
    o += 8 + sz + (sz & 1);
  }
  return { err: `${label}: data 청크 없음`, fmt };
}

// ─────────────────────────────────────────────────────────── 주행
const spec = JSON.parse(fs.readFileSync(PARAMS, 'utf8'));
let sounds = spec.sounds || [];
if (!sounds.length) die('sfx_params.json 에 항목이 없다');
if (ONLY) {
  for (const id of ONLY) if (!sounds.some((s) => s.id === id)) die(`--only: 미등재 항목 '${id}'`);
  sounds = sounds.filter((s) => ONLY.has(s.id));
}
const seen = new Set();
for (const e of sounds) {
  if (seen.has(e.id)) die(`중복 항목: ${e.id}`);
  seen.add(e.id);
}

checkMotif(sounds);

const mode = TWICE ? '결정성 대조' : (CHECK_ONLY ? '대조' : '');
console.log(`SFX 절차 생성 ${mode} — ${sounds.length}식 · jsfxr 1.4.1(vendor)\n`);
const rows = [];

for (const e of sounds) {
  if (!/^[a-z0-9_]+$/.test(e.id)) die(`파일명 규약 위반: ${e.id}`);
  const dir = outDirFor(e);
  if (!CHECK_ONLY && !TWICE) fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, e.id + '.wav');
  const { wav, clipping } = synth(e);
  if (e.compose) e.compose.steps.forEach((o, i) => deadParams(`${e.id}[${i}]`, Object.assign({}, e.params, o)));
  else deadParams(e.id, e.params);

  if (TWICE) {
    // 같은 항목을 다시 합성한다 — 디스크를 보지 않는 결정성 축.
    const again = synth(e).wav;
    const h1 = crypto.createHash('sha256').update(wav).digest('hex');
    const h2 = crypto.createHash('sha256').update(again).digest('hex');
    if (h1 !== h2) fail(`${e.id}: 2회 합성 해시 불일치 — 비결정 합성이다`);
    const noisy = e.params.wave_type === 3
      || (e.compose && e.compose.steps.some((s) => s.wave_type === 3));
    rows.push({ id: e.id, bytes: wav.length, sec: 0, peak: 0, dbfs: -Infinity,
      loop: !!e.loop, seam: null, noise: noisy, sha: h1.slice(0, 12) });
    continue;
  }

  if (CHECK_ONLY) {
    if (!fs.existsSync(file)) { fail(`${e.id}.wav 부재 — 파라미터만 있고 실물이 없다`); continue; }
    const disk = fs.readFileSync(file);
    if (!disk.equals(wav)) {
      fail(`${e.id}.wav 가 파라미터와 다르다 — 디스크 ${disk.length}B / 재합성 ${wav.length}B (한쪽만 고쳐졌다)`);
      continue;
    }
  } else {
    fs.writeFileSync(file, wav);
  }

  // 규격 검사 — 항상 **디스크 바이트**로 한다
  const buf = fs.readFileSync(file);
  const h = readWavHeader(buf, e.id);
  if (h.err) { fail(h.err); continue; }
  const f = h.fmt;
  if (f.audioFormat !== 1) fail(`${e.id}: audioFormat ${f.audioFormat} != 1(PCM)`);
  if (f.sampleRate !== SAMPLE_RATE) fail(`${e.id}: sampleRate ${f.sampleRate} != ${SAMPLE_RATE}`);
  if (f.bitsPerSample !== SAMPLE_SIZE) fail(`${e.id}: bitsPerSample ${f.bitsPerSample} != ${SAMPLE_SIZE}`);
  if (f.numChannels !== 1) fail(`${e.id}: numChannels ${f.numChannels} != 1(모노)`);
  if (h.peak === 0) fail(`${e.id}: 무음(피크 0) — 파라미터가 소리를 만들지 못했다`);
  // 길이 상한 — D13 결속 항목(L군 스팅)만 선언한다. 선언이 없으면 검사하지 않는다.
  if (typeof e.max_sec === 'number' && h.seconds > e.max_sec) {
    fail(`${e.id}: 길이 ${h.seconds.toFixed(3)}s > 상한 ${e.max_sec}s (D13 확정 기준값)`);
  }
  if (clipping) warn(`${e.id}: 합성 중 클리핑 ${clipping}회 — 볼륨 재검 대상`);

  rows.push({
    id: e.id, bytes: buf.length, sec: h.seconds, peak: h.peak,
    dbfs: h.peak ? (20 * Math.log10(h.peak / 32768)) : -Infinity,
    loop: !!e.loop,
    seam: e.loop && h.peak ? Math.abs(h.first - h.last) / h.peak : null,
    noise: e.params.wave_type === 3 || (e.compose && e.compose.steps.some((s) => s.wave_type === 3)),
    sha: crypto.createHash('sha256').update(buf).digest('hex').slice(0, 12),
  });
}

if (TWICE) {
  console.log('  id          바이트  잡음  sha256[12]');
  for (const r of rows) {
    console.log(`  ${r.id.padEnd(10)} ${String(r.bytes).padStart(7)}  ${r.noise ? ' ○' : ' -'}   ${r.sha}`);
  }
  console.log(`\n  잡음 계열 ${rows.filter((r) => r.noise).length}식 포함 — seed 가 출력에 실제로 관여하는 구간이다.`);
  if (fails) { console.error(`\nSFX_DET FAIL fails=${fails}`); process.exit(1); }
  console.log(`\nSFX_DET PASS sounds=${rows.length}`);
} else {
  console.log('  id          바이트   길이(s)  피크    dBFS    루프  seam   sha256[12]');
  for (const r of rows) {
    const seam = r.seam === null ? '    -' : (r.seam * 100).toFixed(1).padStart(5);
    console.log(`  ${r.id.padEnd(10)} ${String(r.bytes).padStart(7)} ${r.sec.toFixed(3).padStart(8)} ${String(r.peak).padStart(6)} ${r.dbfs.toFixed(1).padStart(7)}  ${(r.loop ? '  ○' : '  -')} ${seam}  ${r.sha}`);
  }
  console.log('');
  console.log(`  포맷 전항 확인: PCM(1) · ${SAMPLE_RATE}Hz · ${SAMPLE_SIZE}bit · 모노 — D12 §10.1`);
  console.log('  seam = 루프 항목의 첫·끝 샘플 진폭 차(피크 대비 %) — 단서이지 판정이 아니다(위상·질감은 귀 소관)');
  if (fails) { console.error(`\nSFX_GEN FAIL fails=${fails}`); process.exit(1); }
  console.log(`\nSFX_GEN ${CHECK_ONLY ? 'PASS' : 'OK'} sounds=${rows.length}`);
}
