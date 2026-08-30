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
	"tests/test_tc_c.gd:2259"
	"tests/test_tc_p.gd:153"
	"tests/test_events.gd:7039"
	"tests/test_season.gd:497"
	"tests/test_tc_o.gd:395"
	"tests/test_narrative.gd:235"
	# AUDIO — 오디오 디스패처 정책 4종(봉인·게이트·채널 상한·P1 보호) + 표 전수 대조.
	"tests/test_audio.gd:384"
	# AUDIO-A — 오디오 **실물** 68식. 표·디스패처 검사(AUDIO)와 파일 검사(검증기 AUD)가 못 보는
	# 자리 = 임포트 결과다. 임포터 `edit/loop_mode` 열거는 런타임 상수와 한 칸 어긋나서
	# 선언을 읽는 것으로는 루프 판정이 성립하지 않는다(IMPL-245 등재 함정) — 되읽기만이 증거다.
	"tests/test_audio_assets.gd:340"
	# AUDIO-W — 표와 화면 사이의 공백. 부를 곳이 없는 행은 실물이 유입돼도 영원히 울리지
	# 않는데, 무음 폴백 단계에서는 그 침묵이 정상과 구분되지 않는다.
	"tests/test_audio_wiring.gd:107"
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
	"tests/test_glyph_coverage.gd:3240"
	# G4W — 게이트 G-4(최장 키 언어 라벨 · D12 §8.5 · D14 §5.4). V3 는 **자수**를 규칙과
	# 대조하고 이 스위트는 **실 원도 픽셀 폭**을 **실 슬롯 폭**과 대조한다 — 같은 자수라도
	# 원도별 글자 폭이 다르고 en 은 반각이라 자수는 작고 픽셀은 크다.
	"tests/test_label_width.gd:2520"
	# UISCR — 화면을 실제로 세워 본다. 문맥 결손(무커리어 진입)·포커스 부재는 데이터·코어
	# 검사가 원리적으로 닿지 못하고, 커리어를 연 경로에서는 멀쩡해 보인다.
	"tests/test_ui_screens.gd:812"
	# CG — 전용 CG 6종의 대장·실물 **양방향** 대조. AUDIO-A 와 같은 사유로 검증기가 아니다
	# (프로젝트리스 실행은 `res://` 텍스처를 적재하지 못한다). 역방향(파일 → 행)이 이 축의
	# 요지다 — 그림이 들어왔는데 행이 없으면 **아무도 그 그림을 띄우지 않는다.**
	"tests/test_cg_assets.gd:69"
	# SCENE — 씬 컷 합성. 역방향(요소 → 소비 컷)이 요지다: 29차 착수 사유가 "`fx_*` 8 ·
	# `stage_*` 5 소비부 0건"이었으므로 이 축이 그 0 을 다시 만들지 않는다는 보장이다.
	# 우선순위는 표의 숫자가 아니라 `resolve()` 호출 결과로 잰다.
	"tests/test_scene_cuts.gd:577"
	# SEAL-E — 실화면을 인스턴스화해 릴 정지 연출 전 UI 노출을 잡는다.
	# 라운드 수가 GP 길이(12~15턴 + 듀얼 삽입)에 따라 달라지므로 하한은 최소 GP 기준이다.
	"tests/test_seal_ui.gd:84"
)
# ── 실 프로필 무접촉 (25차 · 차단급) ──
#
# **실피해가 먼저 있었다**: 게이트가 실 프로필의 진행 세이브를 지우고 백업을 덮었다.
# `SaveManager` 격리 훅과 UISCR ㉑(전 하네스 훅 경유)이 안쪽 방어이고, 이것이 밖의 방어다 —
# **훅을 우회하는 경로가 새로 생기면 스위트 검사로는 보이지 않고 실 파일만 바뀐다.**
# 그래서 게이트 전후로 실 저장 파일 바이트를 대조한다. 훅이 아니라 **피해 자체**를 본다.
# **경로를 엔진에게 묻는다.** 손으로 적거나 환경 변수로 받으면 대조 대상과 기록 대상이
# 갈린다 — `GODOT_USER_DIR` 는 Godot 이 모르는 이름이라(실측: 값을 바꿔도
# `OS.get_user_data_dir()` 불변) 그 변수를 신뢰하면 **스냅숏 경로만 옮겨지고 실 파일은
# 그대로 변조되면서 대조는 녹색**이 된다. 26차 벽두 교정 — 내러티브 8차 실측 채택.
USER_DIR=$("$GODOT" --headless --path godot --script tests/print_user_dir.gd 2>/dev/null \
	| sed -n 's/^USER_DATA_DIR=//p' | tail -1)
if [ -z "$USER_DIR" ]; then
	printf '\nTESTS_FAIL 실 저장 경로를 엔진에서 얻지 못했다 — 무접촉 대조가 성립하지 않는다\n'
	exit 1
fi
printf '실 저장 경로(엔진 보고): %s\n' "$USER_DIR"
snapshot_real_saves() {
	if [ ! -d "$USER_DIR" ]; then
		return
	fi
	# `test_profiles/` 는 격리 루트이므로 제외한다 — 그쪽은 바뀌는 것이 정상이다.
	( cd "$USER_DIR" && find . -type f -name '*.json' -not -path './test_profiles/*' \
		| LC_ALL=C sort | xargs -r md5sum ) 2>/dev/null
}
real_before=$(snapshot_real_saves)

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

real_after=$(snapshot_real_saves)
if [ "$real_before" != "$real_after" ]; then
	printf '\n실 프로필 변조 감지 — 스위트가 격리 루트를 벗어났다\n'
	diff <(printf '%s\n' "$real_before") <(printf '%s\n' "$real_after") | head -20
	failures=$((failures + 1))
else
	printf '\n실 프로필 무접촉 확인 (바이트 불변)\n'
fi

if [ "$failures" -ne 0 ]; then
	printf '\nTESTS_FAIL suites=%d\n' "$failures"
	exit 1
fi
printf '\nTESTS_PASS suites=%d\n' "${#TESTS[@]}"
