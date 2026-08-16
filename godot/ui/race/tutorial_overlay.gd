# TUT-01 튜토리얼 오버레이 — D09 §6 · 별첨A §A-25 · D04 §8.1. RACE-01 내부 오버레이(라우터 비경유).
#
# **별도 튜토리얼 스테이지를 신설하지 않는다** (§6 확정) — 첫 그랑프리 실주행 위에 얹는다.
# 구성: 대상 요소 하이라이트(마스크 컷아웃) + 베인 콜아웃 확장 패널 + 스킵.
# **단계 진행 = 지시 행동 수행** — 시간 경과나 클릭이 아니라 그 단계가 지목한 행동을 해야 넘어간다.
# 화자 = 베인 1단계 전속(D04 §8.1 — '설명이 서툰 실험체'가 곧 세계관 정합적 튜토리얼 화자).
#
# **문면은 아직 없다.** 단계 표(`tutorial_steps.csv`)의 `text_key` 는 스트링 키를 가리키지만
# 값은 미유입 표식이다 — 콜아웃 문안은 D04 트랙(T7) 산출물이고 구현이 지어내지 않는다
# (불변규칙 9). 문안이 들어오면 `strings.csv` 값만 채우면 되고 코드·데이터는 손대지 않는다.
#
# **단계 순서의 도달 가능성 제약 [가안]:** GP 개시 차지는 0이고 홀드는 1·차지 개입은 2를 요구한다
# (D13 §2.2). 따라서 **무비용 행동(스핀·확정)이 자원 소모 개입보다 앞서야** 순서대로 밟힌다 —
# 현행 표는 스핀 → 확정 → 홀드 → 리스핀 → 차지 개입이다. 순서를 D04 가 다시 짜더라도 이 제약은
# 남는다. 다만 규격상 **잠기지는 않는다**: 지목하지 않은 행동은 무시될 뿐 진행을 막지 않으므로,
# 플레이어는 계속 주행하며 자원을 쌓다가 해당 행동을 하는 시점에 그 단계를 넘긴다.
extends Control

signal finished

const ONBOARDING_ID := "tut01"
# 하이라이트 여백 — 대상에 딱 붙으면 테두리가 잘려 보인다. [가안] 표현 층 국소값.
const HIGHLIGHT_PAD := 3.0
# 콜아웃 패널의 화면 가장자리 여백. [가안] 표현 층 국소값.
const CALLOUT_MARGIN := 8.0

var _steps: Array = []
var _index := 0
var _session: RunSession
var _host: Control
var _anchor: Control


# 컷아웃은 **딤 4분할**로 만든다 — 대상 사각형의 위·아래·왼·오른쪽만 덮으면 가운데가 빈다.
# 셰이더 없이 성립하고, 딤이 대상 위에 겹치지 않으므로 하이라이트 대상의 색이 왜곡되지 않는다.
@onready var _dims: Array[ColorRect] = [%DimTop, %DimBottom, %DimLeft, %DimRight]
@onready var _callout: Label = %CalloutText
@onready var _callout_panel: PanelContainer = %CalloutPanel
@onready var _step_label: Label = %StepLabel
@onready var _skip: Button = %SkipButton


# host = 하이라이트 대상 노드를 찾을 화면 루트 (RACE-01).
func setup(run_session: RunSession, host: Control) -> void:
	_session = run_session
	_host = host
	_steps = _session.data.tutorial_steps
	var s := _session.data.strings
	_skip.text = s.text("ui.tutorial.skip")
	_skip.pressed.connect(_on_skip)
	# 씬에 놓인 노드라 프로젝트 기본 크기가 먹지만, 본문 계열은 D10 §5.7 확정단이므로
	# 데이터 창구에서 읽어 명시한다 (IMPL-125와 같은 규율 — 코드에 9를 적지 않는다).
	var body_size := int(_session.data.param("param_font_size_body"))
	for label in [_callout, _step_label]:
		label.add_theme_font_size_override("font_size", body_size)
	_skip.add_theme_font_size_override("font_size", body_size)


# 이번 GP 에서 튜토리얼을 켜야 하는가 — 1회성이며 옵션 초기화로 재활성된다(§A-25 확정).
func should_run() -> bool:
	return not _session.options.onboarding_seen.has(ONBOARDING_ID)


func begin() -> void:
	_index = 0
	visible = true
	_show_step()


# 지시 행동이 수행됐을 때 화면이 부른다. 현재 단계가 지목한 행동일 때만 넘어간다 —
# 다른 행동을 해도 튜토리얼이 진행되면 '지시 행동 수행'이라는 진행 규격이 무너진다.
func notify_action(action: String) -> void:
	if not visible or _index >= _steps.size():
		return
	if String(_steps[_index]["advance_on"]) != action:
		return
	_index += 1
	if _index >= _steps.size():
		_complete()
		return
	_show_step()


func _show_step() -> void:
	var step: Dictionary = _steps[_index]
	var s := _session.data.strings
	var callout_text := s.text(String(step["text_key"]))
	_callout.text = callout_text
	var step_text := s.text("ui.tutorial.stepFormat", {
		"current": _index + 1, "total": _steps.size(),
	})
	_step_label.text = step_text
	_anchor = null
	if _host != null:
		# 노드 이름으로 찾는다 — 씬 경로를 코드에 박으면 레이아웃 개편마다 깨진다.
		var found := _host.find_child(String(step["anchor_node"]), true, false)
		if found is Control:
			_anchor = found
	_update_mask()


# 하이라이트 = 대상 사각형만 남기고 나머지를 딤으로 덮는다.
# 대상을 못 찾으면 딤 전체를 끈다 — 엉뚱한 자리를 지목하느니 지목하지 않는 편이 낫다
# (전면을 덮어 버리면 튜토리얼이 화면을 가려 진행 자체가 막힌다).
func _update_mask() -> void:
	if _anchor == null or not _anchor.is_visible_in_tree():
		for dim in _dims:
			dim.visible = false
		return
	var hole := _anchor.get_global_rect().grow(HIGHLIGHT_PAD)
	var full := get_global_rect()
	for dim in _dims:
		dim.visible = true
	_place(_dims[0], Rect2(full.position, Vector2(full.size.x, hole.position.y - full.position.y)))
	_place(_dims[1], Rect2(Vector2(full.position.x, hole.end.y),
		Vector2(full.size.x, full.end.y - hole.end.y)))
	_place(_dims[2], Rect2(Vector2(full.position.x, hole.position.y),
		Vector2(hole.position.x - full.position.x, hole.size.y)))
	_place(_dims[3], Rect2(Vector2(hole.end.x, hole.position.y),
		Vector2(full.end.x - hole.end.x, hole.size.y)))
	_place_callout(hole, full)


# **콜아웃은 하이라이트 반대편에 둔다.** 지목한 요소를 설명 패널이 덮으면 튜토리얼이
# 자기가 가리킨 것을 가린다 — 실측에서 확정 버튼(캔버스 y 309)을 하단 패널이 그대로 덮었다.
func _place_callout(hole: Rect2, full: Rect2) -> void:
	# 앵커를 쓰지 않고 코드가 크기를 쥔다 — 앵커 스트레치와 코드 배치가 겹치면 패널이 늘어난다.
	var width := full.size.x - CALLOUT_MARGIN * 2.0
	_callout_panel.size = Vector2(width, _callout_panel.get_combined_minimum_size().y)
	var top := full.position.y + CALLOUT_MARGIN
	if hole.get_center().y < full.get_center().y:
		top = full.end.y - _callout_panel.size.y - CALLOUT_MARGIN
	_callout_panel.global_position = Vector2(full.position.x + CALLOUT_MARGIN, top)


func _place(rect_node: ColorRect, area: Rect2) -> void:
	rect_node.global_position = area.position
	rect_node.size = Vector2(maxf(area.size.x, 0.0), maxf(area.size.y, 0.0))


func _process(_delta: float) -> void:
	if visible and _anchor != null:
		_update_mask()   # 레이아웃이 움직이면 하이라이트도 따라간다


func _on_skip() -> void:
	_complete()


func _complete() -> void:
	_session.options.mark_onboarding(ONBOARDING_ID)
	visible = false
	finished.emit()
