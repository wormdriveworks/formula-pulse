# 결산 진입 직후 오입력 방어 창 (개선 2026-09-03 — 회차 1 이월 "짧은 입력 무시 창").
#
# 레이스 끝까지 확정 키(Space·Enter·A)를 연타하던 손이 결산 화면에 그대로 닿으면 결산이 한
# 프레임도 읽히기 전에 지나간다 — RACE-03 은 저장 지점이자 수입·순위표를 보이는 유일한 자리라
# 지나가면 되돌릴 수 없다. 개러지 초기 포커스 반전(회차 2 H6)이 최악 사례(출발까지 연쇄 통과)를
# 끊었고, 이 창은 결산 3화면(RACE-03·SET-01·SET-02) 자체를 지킨다.
#
# **화면의 자식 노드 1개다** — 베이스(FlowScreen)에 `_input`/`_process` 를 두지 않는다. GDScript
# 는 자동 super 호출이 없어 같은 이름을 정의한 화면(race_screen)에서 조용히 죽는다
# (flow_screen.gd `_shortcut_input` 주석과 같은 사유). 자식 노드는 상속 계층과 무관하게 선다.
#
# 삼키는 것은 **진행 계열만**이다: `ui_accept` 액션(눌림·뗌·에코 전부 — 뗌만 흘려도 Button 은
# press_attempt 없는 뗌을 무시하지만, 대칭으로 닫아 둔다)과 마우스 버튼. Esc·일시정지·포커스
# 이동은 지나간다 — 방어 대상은 '진행'이지 '조작'이 아니다.
# `_input` 은 GUI 입력보다 앞서 도는 층이라 여기서 소비하면 포커스 버튼이 그 입력을 보지 못한다.
class_name InputGuard
extends Node

var remaining := 0.0


# 호스트 화면에 붙여 `seconds` 동안 무장한다. 값 창구 = D13 `param_settle_input_guard_sec`
# (호출부가 읽어 넘긴다 — 이 노드는 세션을 모른다). 0 이하면 아무것도 붙이지 않는다.
static func arm(host: Node, seconds: float) -> InputGuard:
	if host == null or seconds <= 0.0:
		return null
	var guard := InputGuard.new()
	guard.name = "InputGuard"
	guard.remaining = seconds
	host.add_child(guard)
	return guard


func _process(delta: float) -> void:
	remaining -= delta
	if remaining <= 0.0:
		queue_free()


func _input(event: InputEvent) -> void:
	if event.is_action("ui_accept") or event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
