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
 * ── `--check` 가 하는 일.
 *    파라미터를 다시 합성해 **디스크의 WAV 와 바이트 대조**한다. 한쪽만 고쳐지는 것을 막는다
 *    (`icon_draw.js --check` 와 같은 계약). 겸해서 WAV 헤더 3항을 **파일 바이트에서 직접 읽어** 검사한다
 *    — 생성기가 스스로 보고한 헤더를 믿지 않는다.
 *
 * ── 한계 (검증한 척하지 않는다).
 *    **소리가 좋은지는 보지 않는다.** 이 도구가 보는 것은 규격(포맷·길이·클리핑·무음)뿐이고,
 *    톤 판정은 귀 소관이다(발주 §7.1 — 에셋은 표본까지). 루프 이음매의 매끄러움도 기계 밖이다.
 *
 * 사용:  node tools/audio/sfx_gen.js           (생성 — WAV 를 쓴다)
 *        node tools/audio/sfx_gen.js --check   (대조만 — 쓰지 않는다. 불일치 시 exit 1)
 */
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const sfxr = require('./vendor/sfxr.js');

const ROOT = path.resolve(__dirname, '..', '..');
const OUT_DIR = path.join(ROOT, 'godot', 'assets', 'audio', 'sfx');
const PARAMS = path.join(__dirname, 'sfx_params.json');
const CHECK_ONLY = process.argv.includes('--check');

// D12 §10.1 확정 포맷 — 항목별로 적지 않고 여기서 강제한다
const SAMPLE_RATE = 44100;
const SAMPLE_SIZE = 16;

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

function synth(entry) {
  const p = new sfxr.Params();
  p.sample_rate = SAMPLE_RATE;
  p.sample_size = SAMPLE_SIZE;
  for (const [k, v] of Object.entries(entry.params)) {
    if (!(k in p)) die(`${entry.id}: 미지의 파라미터 '${k}' — sfxr 규격 밖이다`);
    if (typeof v !== 'number' || !Number.isFinite(v)) die(`${entry.id}: ${k} 가 수가 아니다`);
    p[k] = v;
  }
  if (typeof entry.seed !== 'number') die(`${entry.id}: seed 가 없다 — 결정성이 보장되지 않는다`);

  const orig = Math.random;
  Math.random = mulberry32(entry.seed);
  try {
    const rendered = new sfxr.SoundEffect(p).generate();
    return { wav: Buffer.from(rendered.wav), clipping: rendered.clipping | 0 };
  } finally {
    Math.random = orig;
  }
}

// 헤더는 **파일 바이트에서** 읽는다. 합성기가 돌려준 header 객체를 쓰면 대조가 아니다.
function readWavHeader(buf, label) {
  if (buf.length < 44) return { err: `${label}: 44바이트 미만 — WAV 가 아니다` };
  if (buf.toString('ascii', 0, 4) !== 'RIFF') return { err: `${label}: RIFF 시그니처 없음` };
  if (buf.toString('ascii', 8, 12) !== 'WAVE') return { err: `${label}: WAVE 형식 아님` };
  let o = 12, fmt = null, dataSize = null;
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
      dataSize = sz;
      const frames = sz / (fmt ? fmt.blockAlign : 2);
      let peak = 0;
      for (let i = o + 8; i + 1 < Math.min(o + 8 + sz, buf.length); i += 2) {
        const v = Math.abs(buf.readInt16LE(i));
        if (v > peak) peak = v;
      }
      return { fmt, dataSize, frames, seconds: frames / (fmt ? fmt.sampleRate : SAMPLE_RATE), peak };
    }
    o += 8 + sz + (sz & 1);
  }
  return { err: `${label}: data 청크 없음`, fmt, dataSize };
}

// ─────────────────────────────────────────────────────────── 주행
const spec = JSON.parse(fs.readFileSync(PARAMS, 'utf8'));
const sounds = spec.sounds || [];
if (!sounds.length) die('sfx_params.json 에 항목이 없다');
if (!CHECK_ONLY) fs.mkdirSync(OUT_DIR, { recursive: true });

console.log(`SFX 절차 생성 ${CHECK_ONLY ? '대조' : ''} — ${sounds.length}식 · jsfxr 1.4.1(vendor)\n`);
const rows = [];

for (const e of sounds) {
  if (!/^[a-z0-9_]+$/.test(e.id)) die(`파일명 규약 위반: ${e.id}`);
  const file = path.join(OUT_DIR, e.id + '.wav');
  const { wav, clipping } = synth(e);

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
  const buf = CHECK_ONLY ? fs.readFileSync(file) : fs.readFileSync(file);
  const h = readWavHeader(buf, e.id);
  if (h.err) { fail(h.err); continue; }
  const f = h.fmt;
  if (f.audioFormat !== 1) fail(`${e.id}: audioFormat ${f.audioFormat} != 1(PCM)`);
  if (f.sampleRate !== SAMPLE_RATE) fail(`${e.id}: sampleRate ${f.sampleRate} != ${SAMPLE_RATE}`);
  if (f.bitsPerSample !== SAMPLE_SIZE) fail(`${e.id}: bitsPerSample ${f.bitsPerSample} != ${SAMPLE_SIZE}`);
  if (f.numChannels !== 1) fail(`${e.id}: numChannels ${f.numChannels} != 1(모노)`);
  if (h.peak === 0) fail(`${e.id}: 무음(피크 0) — 파라미터가 소리를 만들지 못했다`);
  if (clipping) warn(`${e.id}: 합성 중 클리핑 ${clipping}회 — 볼륨 재검 대상`);

  rows.push({
    id: e.id, bytes: buf.length, sec: h.seconds, peak: h.peak,
    dbfs: h.peak ? (20 * Math.log10(h.peak / 32768)) : -Infinity,
    loop: !!e.loop, sha: crypto.createHash('sha256').update(buf).digest('hex').slice(0, 12),
  });
}

console.log('  id          바이트   길이(s)  피크    dBFS    루프  sha256[12]');
for (const r of rows) {
  console.log(`  ${r.id.padEnd(10)} ${String(r.bytes).padStart(7)} ${r.sec.toFixed(3).padStart(8)} ${String(r.peak).padStart(6)} ${r.dbfs.toFixed(1).padStart(7)}  ${(r.loop ? '  ○' : '  -')}  ${r.sha}`);
}
console.log('');
console.log(`  포맷 전항 확인: PCM(1) · ${SAMPLE_RATE}Hz · ${SAMPLE_SIZE}bit · 모노 — D12 §10.1`);

if (fails) { console.error(`\nSFX_GEN FAIL fails=${fails}`); process.exit(1); }
console.log(`\nSFX_GEN ${CHECK_ONLY ? 'PASS' : 'OK'} sounds=${rows.length}`);
