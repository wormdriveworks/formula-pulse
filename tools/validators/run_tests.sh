#!/usr/bin/env bash
# 헤드리스 로직 테스트 일괄 실행 (TL-3 — D14 §1 통합 테스트 레벨).
# 테스트 목록을 CI YAML과 로컬 양쪽에 중복 기입하지 않는다 —
# 여기 한 곳에 두어 "CI에서만 도는 테스트 / 로컬에서만 도는 테스트"가 갈리지 않게 한다.
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
TESTS=(
	tests/test_core_loop.gd
	tests/test_save_reload.gd
	tests/test_tc_c.gd
	tests/test_tc_p.gd
)
failures=0
for test_path in "${TESTS[@]}"; do
	printf '── %s\n' "$test_path"
	if ! "$GODOT" --headless --path godot --script "$test_path"; then
		printf '   FAILED: %s\n' "$test_path"
		failures=$((failures + 1))
	fi
done
if [ "$failures" -ne 0 ]; then
	printf '\nTESTS_FAIL suites=%d\n' "$failures"
	exit 1
fi
printf '\nTESTS_PASS suites=%d\n' "${#TESTS[@]}"
