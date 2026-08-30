#!/usr/bin/env bash
# G-7 결제 모듈 미포함·권한 검사 (D14 §5.7)
#
# 사용: tools/export/gate_g7.sh <출시 산출물(pck 또는 exe)>
#
# 검사 3항 중 **①②만 여기서 닫는다.** ③모바일 권한 매니페스트는 MS-3 범위 밖이다
# (D15 §1.1 — MS-3 = Steam EA). 모바일 프리셋의 *선언* 은 EXP 가 상시로 보지만,
# 실 매니페스트 대조는 모바일 마일스톤 몫이며 여기서 통과로 적지 않는다.
#
# **권한 검사를 여기에 다시 구현하지 않는다** — 검증기 EXP 가 허용 목록(D14 §5.7 확정
# 기준값)을 이미 쥐고 있고, 같은 규칙을 두 곳에 두면 한쪽만 낡는다.
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"

TARGET="${1:-}"
if [ ! -f "$TARGET" ]; then
	printf 'G7_FAIL 산출물 경로가 필요하다: gate_g7.sh <출시 pck 또는 exe>\n'
	exit 2
fi

fail=0

# ── 검사 ① IAP·결제 SDK 심볼 0 (TC-P10 동렬 — 심볼·문자열 스캔) ──
printf '── 검사 ① 결제·광고 SDK 심볼 (산출물 스캔)\n'
probe=$(bash tools/export/probe_pack.sh "$TARGET" 2>&1)
probe_code=$?
printf '%s\n' "$probe" | sed 's/^/   /'
if [ "$probe_code" -ne 0 ]; then
	fail=$((fail + 1))
fi

# ── 검사 ② 스토어 결제 권한 선언 0 ──
#
# Windows 는 권한 매니페스트 자체가 없다 — 그래서 "선언 0"이 **자동으로 참**이고, 그 참은
# 검사의 결과가 아니라 플랫폼의 성질이다. 실제로 볼 것이 있는 곳은 프리셋의 권한 열이며
# 그것을 EXP 가 본다. 여기서는 그 검사가 **돌았고 위반이 없었다**는 것만 확인한다.
printf '── 검사 ② 권한 선언 (검증기 EXP 축)\n'
validators=$("$GODOT" --headless --path . --script tools/validators/run_validators.gd 2>&1 || true)
exp_line=$(printf '%s' "$validators" | grep "^EXP " || true)
if [ -z "$exp_line" ]; then
	printf '   [FAIL] EXP 축이 보고하지 않았다 — 판정 없음은 위반 없음이 아니다\n'
	fail=$((fail + 1))
elif printf '%s' "$exp_line" | grep -q "PASS"; then
	printf '   [ok] %s\n' "$exp_line"
else
	printf '   [FAIL] %s\n' "$exp_line"
	printf '%s\n' "$validators" | grep "EXP:" | head -5 | sed 's/^/          /'
	fail=$((fail + 1))
fi

# ── 검사 ③ 모바일 권한 매니페스트 — MS-3 범위 밖 ──
printf '── 검사 ③ 모바일 매니페스트: **미실시** (MS-3 = Steam EA · D15 §1.1)\n'

if [ "$fail" -ne 0 ]; then
	printf '\nG7_FAIL 검사 %d건 불통과 — SV-1 등록 + 제출 중지 (D14 §5.7)\n' "$fail"
	exit 1
fi
printf '\nG7_PASS 데스크탑 2검사 통과 (모바일 1검사 = 범위 밖 이월)\n'
