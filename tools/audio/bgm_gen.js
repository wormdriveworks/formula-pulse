#!/usr/bin/env node
/*
 * BGM 절차 합성기 — `bgm_params.json` → PCM 마스터(WAV) → `oggenc` → `godot/assets/audio/bgm/*.ogg`
 *
 * 소유: 에셋 트랙 (`tools/audio/`) · 총괄 기안 `BGM징글_조달기안.md` §5.2 경로 A(절차 합성 파일럿)
 * 전례: `sfx_gen.js` 와 같은 계약 — **재현 = 같은 명령.** 파라미터·시드가 커밋돼 있고 `--check` 가 대조한다.
 *
 * ── 왜 신시사이저를 새로 썼는가.
 *    jsfxr(SFX 경로)은 **단발 효과음 합성기**다 — 포락선 1벌·단성·길이 상한 6.8초.
 *    지속 다성 음악을 낼 수 없으므로 오실레이터·ADSR·1극 필터·믹서를 여기 직접 뒀다.
 *    **SFX 경로는 무접촉이다**(`sfx_gen.js`·`vendor/` 불변) — 두 파이프라인은 공유하지 않는다.
 *
 * ── 심리스 루프의 실체 두 가지 (D11 §4.4 "전 트랙 심리스 루프 필수").
 *    ① **그리드 정수배** — BPM 은 박당 샘플 수가 정수가 되는 값에서만 고른다(2646000/BPM 정수).
 *       아니면 마디마다 소수점 오차가 쌓여 루프 길이가 정수 샘플이 아니게 되고 그 자리에서 깨진다.
 *    ② **꼬리 감김(wrap)** — 루프 끝을 넘는 잔향을 버리지 않고 버퍼 앞쪽에 되감아 더한다.
 *       꼬리를 자르면 이음매에서 소리가 끊기고, 그냥 두면 마지막 마디가 비어 들린다.
 *    산술이 이음매를 없애고, **안 들리게 하는 것은 편성**이다(마지막 8마디를 첫 8마디와 같은 밀도로).
 *
 * ── OGG 재현 계약 (실측으로 잡은 조건).
 *    `oggenc` 는 **기본적으로 비결정적이다** — 같은 입력·같은 설정이 매번 다른 바이트를 낸다
 *    (스트림 시리얼과 그것에 딸린 CRC 32바이트). **`--serial` 을 고정하면 결정적**이다(3/3 동일 실측).
 *    그래서 시리얼을 파라미터에 커밋한다. 고정하지 않으면 `--check` 가 성립하지 않는다.
 *    **q 매핑:** D12 §10.1 "~q0.7" = libvorbis 정규화 품질(−0.1~1.0) · `oggenc -q` 는 그 10배 스케일 → `-q 7`.
 *
 * ── 한계 (검증한 척하지 않는다).
 *    **음악이 좋은지는 보지 않는다.** 이 도구가 보는 것은 규격(샘플레이트·채널·길이·피크·클리핑)과
 *    산술(그리드 정수배·이음매 진폭)뿐이다. 무드 정합·루프가 실제로 안 들리는지·편성의 지루함은 귀 소관이다.
 *
 * 사용:  node tools/audio/bgm_gen.js            (생성 — WAV 마스터 + OGG)
 *        node tools/audio/bgm_gen.js --check    (대조만 — 재합성·재인코딩해 디스크와 바이트 비교)
 *        node tools/audio/bgm_gen.js --keep-wav (PCM 마스터를 build/ 에 남긴다 — 진단용·커밋 대상 아님)
 */
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const OUT_DIR = path.join(ROOT, 'godot', 'assets', 'audio', 'bgm');
const PARAMS = path.join(__dirname, 'bgm_params.json');
const CHECK_ONLY = process.argv.includes('--check');
const KEEP_WAV = process.argv.includes('--keep-wav');
// ⚠ **모르는 플래그를 무시하지 않는다.** `--only`(이 도구에 없는 플래그)를 넘겼더니 조용히 무시되고
//    **전량 재생성**이 돌아 돌연변이 상태의 파라미터로 실물이 덮였다(2026-08-22 실사고).
//    생성기는 파일을 쓰는 도구이므로 "몰랐으면 안 쓴다"가 맞다.
{
  const KNOWN = new Set(['--check', '--keep-wav']);
  const bad = process.argv.slice(2).filter((a) => a.startsWith('-') && !KNOWN.has(a));
  if (bad.length) {
    console.error(`FATAL: 미지의 플래그 ${bad.join(' ')} — 아는 것은 ${[...KNOWN].join(' ')} 뿐이다`);
    process.exit(2);
  }
}

const SR = 44100;
const BITS = 16;

let fails = 0;
const fail = (m) => { console.error('  ✗ ' + m); fails++; };
const warn = (m) => { console.log('  ⚠ ' + m); };
const die = (m) => { console.error('FATAL: ' + m); process.exit(2); };

function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const hz = (rootHz, semitones) => rootHz * Math.pow(2, semitones / 12);

// ── 오실레이터. 위상은 0~1 정규화한다(파형별 분기를 한 자리에 모으기 위해).
function osc(wave, phase, duty, rnd) {
  switch (wave) {
    case 'square': return phase < (duty === undefined ? 0.5 : duty) ? 1 : -1;
    case 'saw': return 2 * phase - 1;
    case 'triangle': return phase < 0.5 ? (4 * phase - 1) : (3 - 4 * phase);
    case 'sine': return Math.sin(2 * Math.PI * phase);
    case 'noise': return rnd() * 2 - 1;
    default: die(`미지의 파형 '${wave}'`);
  }
}

// ── ADSR. [attack, decay, sustainLevel, release] — 앞 둘과 마지막은 ms, 셋째는 0~1 레벨.
function envAt(adsr, i, noteSamples) {
  const a = Math.max(1, Math.round(adsr[0] * SR / 1000));
  const d = Math.max(1, Math.round(adsr[1] * SR / 1000));
  const s = adsr[2];
  const r = Math.max(1, Math.round(adsr[3] * SR / 1000));
  if (i < a) return i / a;
  if (i < a + d) return 1 - (1 - s) * ((i - a) / d);
  if (i < noteSamples) return s;
  const k = i - noteSamples;
  return k < r ? s * (1 - k / r) : 0;
}

// ── 한 음을 버퍼에 더한다. **버퍼 끝을 넘는 꼬리는 앞쪽으로 감긴다** (심리스의 실체).
function renderNote(buf, opts, rnd) {
  const { start, noteSamples, freq, wave, duty, gain, adsr } = opts;
  const rel = Math.max(1, Math.round(adsr[3] * SR / 1000));
  const total = noteSamples + rel;
  const n = buf.length;

  // 1극 필터 상태는 음마다 독립이다 — 음 사이로 상태가 새면 같은 파라미터가 다른 소리를 낸다.
  let lp = 0, hp = 0, prevIn = 0;
  const lpK = opts.lpfHz ? 1 - Math.exp(-2 * Math.PI * opts.lpfHz / SR) : null;
  const hpK = opts.hpfHz ? Math.exp(-2 * Math.PI * opts.hpfHz / SR) : null;

  const drop = opts.pitchDropHz !== undefined;
  let phase = 0, phase2 = 0;
  const det = opts.detuneCents ? Math.pow(2, opts.detuneCents / 1200) : null;

  for (let i = 0; i < total; i++) {
    const e = envAt(adsr, i, noteSamples);
    if (e <= 0) continue;
    const f = drop ? (freq + (opts.pitchDropHz - freq) * Math.min(1, i / Math.max(1, noteSamples))) : freq;
    phase += f / SR; if (phase >= 1) phase -= Math.floor(phase);
    let v = osc(wave, phase, duty, rnd);
    if (det) {
      phase2 += (f * det) / SR; if (phase2 >= 1) phase2 -= Math.floor(phase2);
      v = (v + osc(wave, phase2, duty, rnd)) * 0.5;
    }
    if (lpK !== null) { lp += (v - lp) * lpK; v = lp; }
    if (hpK !== null) { hp = hpK * (hp + v - prevIn); prevIn = v; v = hp; }
    buf[(start + i) % n] += v * e * gain;      // ← 감김
  }
}

// ── 메인 모티프 대조. 원장은 `motif.json` 이고 인용부는 **여러 트랙**이다(BGM-01 원형 · BGM-12 회귀 ·
//    BGM-07 총화 · JG-04 징글). 값이 여러 곳에 있으므로 대조한다 — 한쪽만 고치면 나머지가 조용히 어긋난다.
//    트랙은 `motif: {voice, degrees}` 로 선언하고, 그 `degrees` 가 원장과 같아야 하며
//    선언한 보이스의 프레이즈 도수 열이 그 `degrees` 로 시작해야 한다(뒤에 붙는 음은 트랙 재량 — §3-①).
function checkMotifTracks(tracks) {
  const MOTIF = path.join(__dirname, 'motif.json');
  if (!fs.existsSync(MOTIF)) { fail('motif.json 부재 — 모티프 원장이 없다'); return []; }
  const ledger = JSON.parse(fs.readFileSync(MOTIF, 'utf8')).main.degrees_semitones_from_root;
  const quoted = [];
  for (const t of tracks) {
    if (!t.motif) continue;
    quoted.push(t.id);
    const d = t.motif.degrees;
    if (JSON.stringify(d) !== JSON.stringify(ledger)) {
      fail(`${t.id}: 모티프 도수 ${JSON.stringify(d)} != 원장 ${JSON.stringify(ledger)} — 한쪽만 고쳐졌다`);
      continue;
    }
    const v = t.voices[t.motif.voice];
    if (!v || !v.phrase) { fail(`${t.id}: 모티프 보이스 '${t.motif.voice}' 에 프레이즈가 없다`); continue; }
    if (v.rel !== 'tonic') fail(`${t.id}.${t.motif.voice}: 모티프 인용부는 rel='tonic' 이어야 한다(원장 도수를 그대로 쓴다)`);
    const head = v.phrase.slice(0, d.length).map((n) => n.degree);
    if (JSON.stringify(head) !== JSON.stringify(d)) {
      fail(`${t.id}.${t.motif.voice}: 프레이즈 선두 ${JSON.stringify(head)} != 모티프 ${JSON.stringify(d)}`);
    }
  }
  return quoted;
}

// ── 프리셋 병합. 음색 계열을 트랙마다 다시 적지 않게 하고, 겸해서
//    "같은 계열" 이라는 주장을 **같은 프리셋 참조**로 기계화한다(BGM-09/10 정조 쌍이 그 요구다).
function resolveVoice(spec, presets, name) {
  const v = spec.voices[name];
  if (!v) die(`미지의 보이스 '${name}'`);
  if (!v.preset) return v;
  const base = presets[v.preset];
  if (!base) die(`미지의 프리셋 '${v.preset}'`);
  return Object.assign({}, base, v);
}

// ── 코드 도수 → 절대 반음. `rel` 이 'bass' 면 화음의 베이스 기준, 아니면 화음 근음 기준이다.
function degOf(chord, v, deg) {
  // 'tonic' = 트랙 근음(0) 기준. 모티프 인용부가 이것을 쓴다 — 원장의 도수를 **그대로** 적어야
  // `checkMotif` 대조가 성립하고, 화음 기준으로 적으면 같은 선율이 마디마다 다른 숫자가 된다.
  const anchor = v.rel === 'tonic' ? 0 : (v.rel === 'bass' ? chord.bass : chord.chord[0]);
  return anchor + deg + (v.octave || 0);
}

// ── 트랙 합성
function synth(track, presets) {
  const spb = SR * 60 / track.bpm;
  if (!Number.isInteger(spb)) die(`${track.id}: BPM ${track.bpm} → 박당 ${spb} 샘플 (정수가 아니다 — 루프가 깨진다)`);
  const beatsPerBar = track.beats_per_bar;
  const total = track.bars * beatsPerBar * spb;
  const buf = new Float64Array(total);
  const rnd = mulberry32(track.seed);
  const prog = track.progression;
  const order = Object.keys(track.voices);      // 선언 순서 = 렌더 순서 (잡음 PRNG 소비 순서가 여기 걸린다)

  const activeAt = (bar) => {
    for (const s of track.sections) if (bar >= s.from_bar && bar < s.to_bar) return s.voices;
    return [];
  };

  for (let bar = 0; bar < track.bars; bar++) {
    const on = activeAt(bar);
    const chord = prog[bar % prog.length];
    const barStart = bar * beatsPerBar * spb;

    for (const name of order) {
      if (!on.includes(name)) continue;
      const v = resolveVoice(track, presets, name);
      const common = { wave: v.wave, duty: v.duty, gain: v.gain, adsr: v.adsr_ms,
        lpfHz: v.lpf_hz, hpfHz: v.hpf_hz, detuneCents: v.detune_cents };

      switch (v.kind) {
        case 'hit':          // 고정 음정 타격 — 탭·킥. 음정 하강 포함
          for (const b of v.beats) renderNote(buf, Object.assign({}, common, {
            start: barStart + Math.round(b * spb), noteSamples: Math.round((v.hit_ms || 50) / 1000 * SR),
            freq: v.pitch_hz, pitchDropHz: v.pitch_drop_hz }), rnd);
          break;
        case 'noise':        // 잡음 타격 — 햇·셰이커
          for (const b of v.beats) renderNote(buf, Object.assign({}, common, {
            start: barStart + Math.round(b * spb), noteSamples: Math.round((v.hit_ms || 20) / 1000 * SR),
            freq: 1 }), rnd);
          break;
        case 'bassline':
          for (const nt of v.notes) renderNote(buf, Object.assign({}, common, {
            start: barStart + Math.round(nt.beat * spb), noteSamples: Math.round(nt.len_beats * spb),
            freq: hz(track.root_hz, chord.bass + nt.degree + (v.octave || 0)) }), rnd);
          break;
        case 'chord':        // 화음 전음 동시 — 패드·스탭
          for (const beat of (v.beats || [0])) for (const deg of chord.chord)
            renderNote(buf, Object.assign({}, common, {
              start: barStart + Math.round(beat * spb),
              noteSamples: Math.round(v.len_beats * spb),
              freq: hz(track.root_hz, deg + (v.octave || 0)) }), rnd);
          break;
        case 'arp': {        // 화음 구성음을 세분박으로 순회 — 네온 계열의 구동
          const step = v.step_beats;
          const count = Math.round(beatsPerBar / step);
          for (let i = 0; i < count; i++) {
            const deg = chord.chord[i % chord.chord.length]
              + ((v.rise_octave && i >= count / 2) ? 12 : 0);
            renderNote(buf, Object.assign({}, common, {
              start: barStart + Math.round(i * step * spb),
              noteSamples: Math.round(step * spb * (v.gate || 0.9)),
              freq: hz(track.root_hz, deg + (v.octave || 0)) }), rnd);
          }
          break;
        }
        case 'phrase': {     // 선율 — every_bars 마디 주기의 프레이즈
          const every = v.every_bars || 1;
          if (bar % every !== 0) break;
          for (const nt of v.phrase) {
            const cAt = prog[(bar + Math.floor(nt.beat / beatsPerBar)) % prog.length];
            renderNote(buf, Object.assign({}, common, {
              start: barStart + Math.round(nt.beat * spb),
              noteSamples: Math.round(nt.len_beats * spb),
              freq: hz(track.root_hz, degOf(cAt, v, nt.degree)) }), rnd);
          }
          break;
        }
        default: die(`${track.id}.${name}: 미지의 kind '${v.kind}'`);
      }
    }
  }
  return buf;
}

function toWav(buf, targetDbfs) {
  let peak = 0;
  for (let i = 0; i < buf.length; i++) if (Math.abs(buf[i]) > peak) peak = Math.abs(buf[i]);
  if (peak === 0) die('무음 — 합성이 소리를 만들지 못했다');
  const want = Math.pow(10, targetDbfs / 20);
  const g = want / peak;                       // 리미터가 아니라 정규화다(라우드니스 전쟁 금지 — D11 §1.1)
  const data = Buffer.alloc(buf.length * 2);
  for (let i = 0; i < buf.length; i++) {
    let v = Math.round(buf[i] * g * 32767);
    if (v > 32767) v = 32767; else if (v < -32768) v = -32768;
    data.writeInt16LE(v, i * 2);
  }
  const head = Buffer.alloc(44);
  head.write('RIFF', 0); head.writeUInt32LE(36 + data.length, 4); head.write('WAVE', 8);
  head.write('fmt ', 12); head.writeUInt32LE(16, 16); head.writeUInt16LE(1, 20);
  head.writeUInt16LE(1, 22); head.writeUInt32LE(SR, 24); head.writeUInt32LE(SR * 2, 28);
  head.writeUInt16LE(2, 32); head.writeUInt16LE(BITS, 34);
  head.write('data', 36); head.writeUInt32LE(data.length, 40);
  return { wav: Buffer.concat([head, data]), rawPeak: peak, gain: g };
}

// ── 주행
const spec = JSON.parse(fs.readFileSync(PARAMS, 'utf8'));
const tracks = spec.tracks || [];
if (!tracks.length) die('bgm_params.json 에 트랙이 없다');
if (!CHECK_ONLY) fs.mkdirSync(OUT_DIR, { recursive: true });

console.log(`BGM 절차 합성 ${CHECK_ONLY ? '대조' : ''} — ${tracks.length}트랙 · oggenc -q/--serial 고정\n`);
const rows = [];
const pairs = [];
const quotedMotif = checkMotifTracks(tracks);

for (const t of tracks) {
  if (!/^[a-z0-9_]+$/.test(t.id)) die(`파일명 규약 위반: ${t.id}`);
  const buf = synth(t, spec.voice_presets || {});
  const { wav, gain } = toWav(buf, t.target_peak_dbfs);

  const tmp = path.join(os.tmpdir(), `${t.id}_${process.pid}.wav`);
  fs.writeFileSync(tmp, wav);
  const oggTmp = path.join(os.tmpdir(), `${t.id}_${process.pid}.ogg`);
  try {
    execFileSync('oggenc', ['-Q', '-q', String(t.ogg_quality), '--serial', String(t.ogg_serial),
      '-o', oggTmp, tmp], { stdio: 'pipe' });
  } catch (e) {
    die(`oggenc 실행 실패 — 인코더가 없거나 옵션이 다르다: ${e.message}`);
  }
  const ogg = fs.readFileSync(oggTmp);
  const file = path.join(OUT_DIR, t.id + '.ogg');

  if (CHECK_ONLY) {
    if (!fs.existsSync(file)) { fail(`${t.id}.ogg 부재 — 파라미터만 있고 실물이 없다`); continue; }
    const disk = fs.readFileSync(file);
    if (!disk.equals(ogg)) {
      fail(`${t.id}.ogg 가 파라미터와 다르다 — 디스크 ${disk.length}B / 재인코딩 ${ogg.length}B (한쪽만 고쳐졌다)`);
    }
  } else {
    fs.writeFileSync(file, ogg);
  }
  if (KEEP_WAV) {
    const bdir = path.join(__dirname, 'build');
    fs.mkdirSync(bdir, { recursive: true });
    fs.writeFileSync(path.join(bdir, t.id + '.wav'), wav);   // 진단용 — 커밋 대상 아님
  }

  // ── 규격·산술 검사
  const frames = buf.length;
  const seconds = frames / SR;
  if (seconds < 90 || seconds > 150) fail(`${t.id}: 길이 ${seconds.toFixed(1)}s 가 90~150초 밖이다 (D11 §4.4)`);
  const spb = SR * 60 / t.bpm;
  if (frames !== t.bars * t.beats_per_bar * spb) fail(`${t.id}: 프레임 수가 그리드 정수배가 아니다`);

  // 디코드 왕복 — Vorbis 는 블록 단위 코덱이라 길이가 어긋날 수 있다.
  // **샘플 수가 어긋나면 심리스 루프가 성립하지 않는다**(되감기 지점이 밀린다).
  const decTmp = path.join(os.tmpdir(), `${t.id}_${process.pid}_dec.wav`);
  execFileSync('oggdec', ['-Q', '-o', decTmp, oggTmp], { stdio: 'pipe' });
  const dec = fs.readFileSync(decTmp);
  const decFrames = dec.readUInt32LE(40) / 2;
  if (decFrames !== frames) fail(`${t.id}: 디코드 왕복 길이 불일치 — 원본 ${frames} 프레임 / 디코드 ${decFrames} (심리스 루프 불성립)`);

  // 이음매 — 끝과 시작의 진폭 차. 꼬리 감김이 들었으면 작아야 한다.
  let peak16 = 0;
  for (let o = 44; o + 1 < dec.length; o += 2) { const v = Math.abs(dec.readInt16LE(o)); if (v > peak16) peak16 = v; }
  const first = dec.readInt16LE(44);
  const last = dec.readInt16LE(dec.length - 2);
  const seam = peak16 ? Math.abs(first - last) / peak16 : 0;

  rows.push({ id: t.id, bytes: ogg.length, sec: seconds, bars: t.bars, bpm: t.bpm, frames: frames,
    pcm: /_[ab]$/.test(t.id) ? dec.subarray(44) : null,
    peak: peak16, dbfs: 20 * Math.log10(peak16 / 32768), seam,
    kbps: (ogg.length * 8 / seconds / 1000),
    sha: crypto.createHash('sha256').update(ogg).digest('hex').slice(0, 12) });
  for (const f of [tmp, oggTmp, decTmp]) { try { fs.unlinkSync(f); } catch (_) {} }
}

// ── A/B 스템 쌍 검사 (발주 §2 "동일 길이 샘플 단위 일치 · B = A 위 가산 스템").
//    길이가 1샘플만 어긋나도 두 스템이 서로 밀려 박 동기가 깨진다. 그리고 **합산이 클리핑하면
//    가산 레이어가 성립하지 않는다** — 재생기는 B 볼륨만 켜므로 두 파일이 동시에 울린다.
for (const r of rows) {
  if (!r.id.endsWith('_a')) continue;
  const bId = r.id.slice(0, -2) + '_b';
  const b = rows.find((x) => x.id === bId);
  if (!b) { fail(`${r.id}: 짝 ${bId} 가 없다 — A/B 는 쌍으로만 성립한다`); continue; }
  if (r.frames !== b.frames) {
    fail(`${r.id}/${bId}: 프레임 ${r.frames} vs ${b.frames} — 샘플 단위 불일치(박 동기 파손)`);
  }
  if (r.bpm !== b.bpm || r.bars !== b.bars) {
    fail(`${r.id}/${bId}: 템포·마디 불일치 (${r.bpm}/${r.bars} vs ${b.bpm}/${b.bars})`);
  }
  if (r.pcm && b.pcm) {
    let sumPeak = 0;
    const n = Math.min(r.pcm.length, b.pcm.length) / 2;
    for (let i = 0; i < n; i++) {
      const v = Math.abs(r.pcm.readInt16LE(i * 2) + b.pcm.readInt16LE(i * 2));
      if (v > sumPeak) sumPeak = v;
    }
    const db = 20 * Math.log10(sumPeak / 32768);
    pairs.push({ a: r.id, b: bId, frames: r.frames, sumPeak, db });
    if (sumPeak >= 32768) fail(`${r.id}+${bId}: 합산 피크 ${sumPeak} — 동시 재생이 클리핑한다(가산 레이어 불성립)`);
  }
}
if (pairs.length) {
  console.log('  A/B 쌍       프레임      합산피크  합산dBFS');
  for (const p2 of pairs) {
    console.log(`  ${p2.a}/${p2.b.slice(-1)}  ${String(p2.frames).padStart(9)}  ${String(p2.sumPeak).padStart(8)}  ${p2.db.toFixed(1).padStart(7)}`);
  }
  console.log('');
}
console.log('  id       바이트    길이(s)  마디 BPM   피크   dBFS   seam   kbps  sha256[12]');
for (const r of rows) {
  console.log(`  ${r.id.padEnd(8)} ${String(r.bytes).padStart(8)} ${r.sec.toFixed(3).padStart(8)} ${String(r.bars).padStart(5)} ${String(r.bpm).padStart(4)} ${String(r.peak).padStart(6)} ${r.dbfs.toFixed(1).padStart(6)} ${(r.seam * 100).toFixed(2).padStart(6)}% ${r.kbps.toFixed(0).padStart(5)}  ${r.sha}`);
}
console.log('');
console.log(`  포맷: OGG Vorbis ${SR}Hz 모노 · q0.7(oggenc -q 7) · 시리얼 고정 — D12 §10.1`);
if (quotedMotif.length) console.log(`  모티프 인용 ${quotedMotif.length}처 원장 대조 통과: ${quotedMotif.join(' · ')} (원장 = motif.json)`);
console.log('  seam = 디코드 후 첫·끝 샘플 진폭 차(피크 대비) — 꼬리 감김의 결과이며 위상·질감은 귀 소관이다');

if (fails) { console.error(`\nBGM_GEN FAIL fails=${fails}`); process.exit(1); }
console.log(`\nBGM_GEN ${CHECK_ONLY ? 'PASS' : 'OK'} tracks=${rows.length}`);
