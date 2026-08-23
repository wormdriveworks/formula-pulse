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
gate_output=$("$GODOT" --headless --path godot --script tests/compile_gate.gd 2>&1)
gate_code=$?
printf '%s\n' "$gate_output"
# 게이트가 자기 파스 에러로 죽으면 종료코드는 잡히지만 진단이 사라진다 —
# **성공 토큰의 부재 자체**를 실패로 본다 (게이트는 자기 자신을 검사하지 못한다).
if [ "$gate_code" -ne 0 ] || ! printf '%s' "$gate_output" | grep -q "COMPILE_GATE_PASS"; then
	printf '\nTESTS_FAIL compile gate (종료코드 %d · 성공 토큰 %s)\n' \
		"$gate_code" "$(printf '%s' "$gate_output" | grep -q COMPILE_GATE_PASS && echo 있음 || echo 없음)"
	exit 1
fi

# 스위트 : 최소 검사 수 (검사를 줄이려면 이 값을 함께 내려야 한다 — 의도적 축소만 통과)
TESTS=(
	"tests/test_core_loop.gd:0"
	"tests/test_save_reload.gd:0"
	"tests/test_tc_c.gd:2229"
	"tests/test_tc_p.gd:153"
	"tests/test_events.gd:7039"
	"tests/test_season.gd:497"
	"tests/test_tc_o.gd:395"
	"tests/test_narrative.gd:156"
	# AUDIO — 오디오 디스패처 정책 4종(봉인·게이트·채널 상한·P1 보호) + 표 전수 대조.
	"tests/test_audio.gd:384"
	# AUDIO-A — 오디오 **실물** 68식. 표·디스패처 검사(AUDIO)와 파일 검사(검증기 AUD)가 못 보는
	# 자리 = 임포트 결과다. 임포터 `edit/loop_mode` 열거는 런타임 상수와 한 칸 어긋나서
	# 선언을 읽는 것으로는 루프 판정이 성립하지 않는다(IMPL-245 등재 함정) — 되읽기만이 증거다.
	"tests/test_audio_assets.gd:340"
	# AUDIO-W — 표와 화면 사이의 공백. 부를 곳이 없는 행은 실물이 유입돼도 영원히 울리지
	# 않는데, 무음 폴백 단계에서는 그 침묵이 정상과 구분되지 않는다.
	"tests/test_audio_wiring.gd:99"
	"tests/test_data_driven.gd:69"
	# AUDIO-P — 재생기(표현 층). 헤드리스 더미 드라이버에서도 버스·볼륨·재생 상태·`finished`
	# 통지가 실재하므로 **소리 없이 상태 검증이 성립**한다. 관측은 전부 `AudioServer` 되읽기다 —
	# 설정 호출의 성공은 증거가 아니다(`.import` 문면 함정의 오디오 서버 층 적용).
	"tests/test_audio_player.gd:107"
	# UIOPT — 화면 층 옵션 소비부. 항목만 있고 소비부가 없으면 설정은 켜지는데 화면은 그대로다.
	"tests/test_ui_options.gd:54"
	# GLYPH — 원도 커버리지. 판정 대상이 "원도가 이 문자를 실제로 그릴 수 있는가"이고 그 답의
	# 정본은 엔진이 적재한 폰트다 — 검증기는 프로젝트리스라 `FontFile` 을 적재할 수 없고,
	# cmap 자작 파서가 엔진과 한 칸 갈리면 그 차이가 곧 오검출이거나 누락이다(AUD/AUDIO-A 전례).
	"tests/test_glyph_coverage.gd:2560"
	# UISCR — 화면을 실제로 세워 본다. 문맥 결손(무커리어 진입)·포커스 부재는 데이터·코어
	# 검사가 원리적으로 닿지 못하고, 커리어를 연 경로에서는 멀쩡해 보인다.
	"tests/test_ui_screens.gd:332"
	# SEAL-E — 실화면을 인스턴스화해 릴 정지 연출 전 UI 노출을 잡는다.
	# 라운드 수가 GP 길이(12~15턴 + 듀얼 삽입)에 따라 달라지므로 하한은 최소 GP 기준이다.
	"tests/test_seal_ui.gd:84"
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
