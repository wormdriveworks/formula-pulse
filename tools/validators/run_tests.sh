#!/usr/bin/env bash
# 헤드리스 로직 테스트 일괄 실행 (TL-3 — D14 §1 통합 테스트 레벨).
# 테스트 목록을 CI YAML과 로컬 양쪽에 중복 기입하지 않는다 —
# 여기 한 곳에 두어 "CI에서만 도는 테스트 / 로컬에서만 도는 테스트"가 갈리지 않게 한다.
#
# 게이트 3중:
#  ①컴파일 게이트 — 전 .gd 로드 성립 (파스 에러가 통과하는 구멍을 막는다)
#  ②스위트 종료코드
#  ③**검사 수 하한** — 클래스 로드 실패 등으로 스위트가 쪼그라들면 종료코드 0으로도 실패시킨다.
#    실측 사례: save_manager.gd 파스 에러 시 TC-P 검사 수가 108 → 2로 붕괴했는데 exit=0이었다.
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"

printf '── compile gate\n'
if ! "$GODOT" --headless --path godot --script tests/compile_gate.gd; then
	printf '\nTESTS_FAIL compile gate\n'
	exit 1
fi

# 스위트 : 최소 검사 수 (검사를 줄이려면 이 값을 함께 내려야 한다 — 의도적 축소만 통과)
TESTS=(
	"tests/test_core_loop.gd:0"
	"tests/test_save_reload.gd:0"
	"tests/test_tc_c.gd:850"
	"tests/test_tc_p.gd:110"
	"tests/test_events.gd:6000"
	"tests/test_season.gd:450"
	"tests/test_tc_o.gd:239"
	"tests/test_narrative.gd:68"
)
failures=0
for entry in "${TESTS[@]}"; do
	test_path="${entry%%:*}"
	min_checks="${entry##*:}"
	printf '── %s\n' "$test_path"
	output=$("$GODOT" --headless --path godot --script "$test_path" 2>&1)
	code=$?
	printf '%s\n' "$output"
	if [ "$code" -ne 0 ]; then
		printf '   FAILED: %s\n' "$test_path"
		failures=$((failures + 1))
		continue
	fi
	if [ "$min_checks" -gt 0 ]; then
		checks=$(printf '%s' "$output" | sed -n 's/.*checks=\([0-9]*\).*/\1/p' | tail -1)
		if [ -z "$checks" ]; then
			printf '   FAILED: %s — 검사 수를 보고하지 않았다\n' "$test_path"
			failures=$((failures + 1))
		elif [ "$checks" -lt "$min_checks" ]; then
			printf '   FAILED: %s — 검사 수 %s < 하한 %s (스위트가 쪼그라들었다)\n' \
				"$test_path" "$checks" "$min_checks"
			failures=$((failures + 1))
		fi
	fi
done
if [ "$failures" -ne 0 ]; then
	printf '\nTESTS_FAIL suites=%d\n' "$failures"
	exit 1
fi
printf '\nTESTS_PASS suites=%d\n' "${#TESTS[@]}"
