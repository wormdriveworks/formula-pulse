#!/usr/bin/env bash
# G-6 봉인 노출 경로 0 — 3방법 집행 (D14 §5.6)
#
# 사용: tools/export/gate_g6.sh <출시팩> <검증팩>
#
# **하네스를 소스 트리가 아니라 팩에서 돌린다.** `--main-pack` 은 익스포트 산출물을 그대로
# 주 프로젝트로 세우므로, 여기서 도는 것은 "리포지토리의 코드"가 아니라 "빌드에 실린 코드"다.
# (실 바이너리 대조는 export template 이 있는 머신 몫 — 본 스크립트는 팩 층까지 닫는다.)
#
# **팩에서 원리적으로 성립하지 않는 축이 있다.** 익스포트는 `.gd` 를 `.gdc`+`.remap` 으로
# 치환하므로 **원본 문자열을 읽는 축**(AUDIO-W 결선 대조·UISCR 발신처 전수·TC-C 엔진 원본
# 적재)은 팩에서 파일을 찾지 못한다. 이것은 빌드의 결함이 아니라 **축의 성질**이다 —
# 그래서 G-6 는 **거동 축**만 팩에서 돌리고, 원본 대조 축은 소스 트리 게이트가 진다.
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"

RELEASE="${1:-}"
VERIFY="${2:-}"
if [ ! -f "$RELEASE" ] || [ ! -f "$VERIFY" ]; then
	printf 'G6_FAIL 팩 경로가 필요하다: gate_g6.sh <출시팩> <검증팩>\n'
	exit 2
fi

fail=0

# ── 방법 ① 정적 검사 — 디버그·검증 코드의 출시 빌드 제거 ──
printf '── 방법 ① 정적 검사 (출시 팩 검침)\n'
if bash tools/export/probe_pack.sh "$RELEASE" | sed 's/^/   /'; then
	printf '   판정: 통과\n'
else
	printf '   판정: 불통과\n'
	fail=$((fail + 1))
fi

# **대조군 — 출시 팩은 하네스를 열 수 없어야 한다.** 검침 목록이 0 이라는 것과 런타임이
# 그것을 못 연다는 것은 다른 사실이다(목록은 내가 세고, 이쪽은 엔진이 답한다).
printf '── 대조군: 출시 팩에서 하네스 적재 시도\n'
# **파이프로 판정하지 않는다.** `set -o pipefail` 아래에서 `godot | grep -q` 는 grep 이 찾아도
# 종료코드 1 을 낸다 — 적재 실패한 godot 자신의 1 이 파이프라인 상태를 이긴다. 즉 **찾았다는
# 사실이 못 찾았다로 뒤집힌다.** 출력을 먼저 담고 그 다음에 본다.
reject=$("$GODOT" --headless --main-pack "$RELEASE" --script tests/test_tc_c.gd 2>&1 || true)
if printf '%s' "$reject" | grep -q "Can't load script"; then
	printf "   [ok] 출시 팩은 하네스를 열지 못한다 (제외가 런타임에서 실재)\n"
else
	printf '   [FAIL] 출시 팩에서 하네스가 열렸다 — 제외가 이름뿐이다\n'
	fail=$((fail + 1))
fi

# ── 방법 ② 런타임 캡처 대조 — 5경로 노출 0 ──
#
# SEAL-E = 실화면을 세워 릴 정지 연출 전 UI 노출을 잡는 하네스. TC-C11 = 엔진 층 봉인 축.
printf '── 방법 ② 런타임 캡처 (검증 팩)\n'
seal=$("$GODOT" --headless --main-pack "$VERIFY" --script tests/test_seal_ui.gd 2>&1)
seal_checks=$(printf '%s' "$seal" | sed -n 's/.*SEAL_UI_TEST_PASS checks=\([0-9]*\).*/\1/p' | tail -1)
if [ -n "$seal_checks" ] && [ "$seal_checks" -ge 84 ]; then
	printf '   [ok] SEAL-E %s검사 통과 (5경로 노출 0)\n' "$seal_checks"
else
	printf '   [FAIL] SEAL-E 미통과 — checks=%s\n' "${seal_checks:-없음}"
	printf '%s\n' "$seal" | grep "\[FAIL\]" | head -5 | sed 's/^/          /'
	fail=$((fail + 1))
fi

# TC-C11 — **알려진 원본 대조 축 1개만 실패해야 한다.** 허용 목록을 명시해 두는 이유는
# 그래야 TC-C11 축이 깨졌을 때 그 실패가 "원래 하나 실패한다"에 묻히지 않기 때문이다.
tcc=$("$GODOT" --headless --main-pack "$VERIFY" --script tests/test_tc_c.gd 2>&1)
tcc_checks=$(printf '%s' "$tcc" | sed -n 's/.*checks=\([0-9]*\).*/\1/p' | tail -1)
unexpected=$(printf '%s' "$tcc" | grep "\[FAIL\]" | grep -v "엔진 원본 적재" || true)
if [ -n "$tcc_checks" ] && [ "$tcc_checks" -ge 2241 ] && [ -z "$unexpected" ]; then
	printf '   [ok] TC-C %s검사 — 봉인 축 전건 통과 (원본 대조 축 1건은 팩 성질)\n' "$tcc_checks"
else
	printf '   [FAIL] TC-C — checks=%s\n' "${tcc_checks:-없음}"
	printf '%s\n' "$unexpected" | head -5 | sed 's/^/          /'
	fail=$((fail + 1))
fi

# ── 방법 ③ 오디오 발화 로그 대조 — 정지 전 결과 암시음 0 (D11 층위 원칙) ──
printf '── 방법 ③ 오디오 발화 (검증 팩)\n'
audio=$("$GODOT" --headless --main-pack "$VERIFY" --script tests/test_audio.gd 2>&1)
audio_checks=$(printf '%s' "$audio" | sed -n 's/.*AUDIO_TEST_PASS checks=\([0-9]*\).*/\1/p' | tail -1)
if [ -n "$audio_checks" ] && [ "$audio_checks" -ge 384 ]; then
	printf '   [ok] AUDIO %s검사 통과 (봉인 개폐·결과 암시음 0)\n' "$audio_checks"
else
	printf '   [FAIL] AUDIO 미통과 — checks=%s\n' "${audio_checks:-없음}"
	printf '%s\n' "$audio" | grep "\[FAIL\]" | head -5 | sed 's/^/          /'
	fail=$((fail + 1))
fi

if [ "$fail" -ne 0 ]; then
	printf '\nG6_FAIL 방법 %d건 불통과 — 위반은 SV-1 차단 결함으로 등록한다 (D14 §5.6)\n' "$fail"
	exit 1
fi
printf '\nG6_PASS 3방법 전건 노출 0\n'
