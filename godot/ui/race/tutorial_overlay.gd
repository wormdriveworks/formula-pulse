# TUT-01 튜토리얼 오버레이 — D09 §6 · 별첨A §A-25 · D04 §8.1. RACE-01 내부 오버레이(라우터 비경유).
#
# **별도 튜토리얼 스테이지를 신설하지 않는다** (§6 확정) — 첫 그랑프리 실주행 위에 얹는다.
# 구성: 대상 요소 하이라이트(마스크 컷아웃) + 베인 콜아웃 확장 패널 + 스킵.
# **단계 진행 = 지시 행동 수행** — 시간 경과나 클릭이 아니라 그 단계가 지목한 행동을 해야 넘어간다.
# 화자 = 베인 1단계 전속(D04 §8.1 — '설명이 서툰 실험체'가 곧 세계관 정합적 튜토리얼 화자).
#
# **문면 유입 완료 (내러티브 1차 — 2026-08-19).** 단계 표(`tutorial_steps.csv`)의 `text_key` 5키가
# 실문안으로 채워졌다. 예고한 그대로 `strings.csv` 값만 바뀌고 코드·데이터는 손대지 않았다.
# 실측 폭 = 164~201px(본문 9px 기준 **18.22~22.33 전각**) — 패널 내폭 616px 대비 3배 여유라
# 크기 조정은 불요였고, 실문안 재점검에서 걸린 것은 세로 배치 하나다(IMPL-258).
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
# 콜아웃이 침범하면 안 되는 상시 표시 영역 (숙주가 노드로 넘긴다 — IMPL-258).
var _reserved: Array[Control] = []


# 컷아웃은 **딤 4분할**로 만든다 — 대상 사각형의 위·아래·왼·오른쪽만 덮으면 가운데가 빈다.
# 셰이더 없이 성립하고, 딤이 대상 위에 겹치지 않으므로 하이라이트 대상의 색이 왜곡되지 않는다.
@onready var _dims: Array[ColorRect] = [%DimTop, %DimBottom, %DimLeft, %DimRight]
@onready var _callout: Label = %CalloutText
@onready var _callout_panel: PanelContainer = %CalloutPanel
@onready var _step_label: Label = %StepLabel
@onready var _skip: Button = %SkipButton


# host = 하이라이트 대상 노드를 찾을 화면 루트 (RACE-01).
# reserved = 콜아웃이 덮으면 안 되는 상시 표시 노드 (RACE-01 은 Zone A 스트립을 넘긴다).
func setup(run_session: RunSession, host: Control, reserved: Array[Control] = []) -> void:
	_session = run_session
	_host = host
	_reserved = reserved
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
#
# **반대편이 화면 끝은 아니다 (IMPL-258).** 상단 배치를 화면 최상단에 붙이면 상시 표시
# 스트립(Zone A)을 덮는다 — 실측 5단계 전 단계에서 패널이 스트립 30px 중 **22px**을 가렸다
# (624×22 = 13,728px²). 순위·랩·게이지는 튜토리얼 중에도 읽어야 하는 상태라, 지목 요소를
# 가리지 않는 것만으로는 부족하다. 그래서 배치 구간을 **예약 영역 밖(`_safe_area`)으로 한정**한다.
# 예약 영역은 숙주가 노드로 넘기고 좌표는 실 rect 에서 읽는다 — 코드에 y 값을 적지 않는다.
func _place_callout(hole: Rect2, full: Rect2) -> void:
	# 앵커를 쓰지 않고 코드가 크기를 쥔다 — 앵커 스트레치와 코드 배치가 겹치면 패널이 늘어난다.
	var width := full.size.x - CALLOUT_MARGIN * 2.0
	# **자동 줄바꿈 라벨의 최소 높이는 자기 현재 폭이 정한다.** 패널이 아직 0폭인 첫 배치에서
	# 그 값을 물으면 문안이 한 글자씩 접혀 최소 높이가 **294px** 로 부푼다(실측) — 콜아웃이
	# 릴을 통째로 덮는 한 프레임이 생기고, 다음 프레임에 34px 로 접힌다. 그래서 높이를 묻기
	# 전에 **라벨의 줄바꿈 폭을 먼저 못박는다**(툴팁이 `custom_minimum_size` 로 쓰는 그 수법).
	# 여백은 스타일박스에서 읽는다 — 패딩 값을 코드에 적지 않는다.
	var box := _callout_panel.get_theme_stylebox("panel")
	var pad := 0.0
	if box != null:
		pad = box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT)
	_callout.custom_minimum_size.x = maxf(width - pad, 0.0)
	# 최소 폭만으로는 첫 배치가 안 잡힌다 — 컨테이너 정렬은 다음 프레임이고, 자동 줄바꿈은
	# 라벨의 **실 폭**을 본다. 그래서 실 폭도 같이 적어 준다(정렬이 뒤에 같은 값을 쓴다).
	_callout.size.x = _callout.custom_minimum_size.x
	# 최소 크기 캐시를 명시 무효화한다. `get_combined_minimum_size()` 는 무효 표식이 있으면
	# **그 자리에서 다시 계산**하므로, 0폭 시절의 값이 남아 세로로 부푸는 일이 없다.
	_callout.update_minimum_size()
	_callout_panel.size = Vector2(width, _callout_panel.get_combined_minimum_size().y)
	var height := _callout_panel.size.y
	var safe := _safe_area(full)
	var top_slot := safe.position.y + CALLOUT_MARGIN
	var bottom_slot := safe.end.y - height - CALLOUT_MARGIN
	# IMPL-138 규칙 유지 — 하이라이트가 상반부면 패널은 하단, 하반부면 상단.
	var prefer_bottom := hole.get_center().y < full.get_center().y
	var top := bottom_slot if prefer_bottom else top_slot
	# 그래도 지목 요소를 덮으면 남은 쪽으로 넘긴다 — 예약 영역이 좁혀 놓은 구간에서는
	# 반대편 배치가 하이라이트와 겹칠 수 있고, 그때 우선순위는 **지목 요소가 먼저**다.
	var alt := top_slot if prefer_bottom else bottom_slot
	if _band_overlap(top, height, hole) > _band_overlap(alt, height, hole):
		top = alt
	top = clampf(top, safe.position.y, maxf(safe.end.y - height, safe.position.y))
	_callout_panel.global_position = Vector2(full.position.x + CALLOUT_MARGIN, top)


# 콜아웃이 들어가면 안 되는 상시 표시 영역을 뺀 세로 구간. 예약 영역이 없으면 화면 전체다
# (숙주가 아무것도 넘기지 않는 화면에서도 종전 거동이 그대로 성립한다).
func _safe_area(full: Rect2) -> Rect2:
	var top := full.position.y
	var bottom := full.end.y
	for node in _reserved:
		if node == null or not node.is_visible_in_tree():
			continue
		var r := node.get_global_rect()
		if not r.intersects(full):
			continue
		# 화면 위쪽에 붙은 예약 영역은 위 경계를 내리고, 아래쪽은 아래 경계를 올린다.
		if r.get_center().y < full.get_center().y:
			top = maxf(top, r.end.y)
		else:
			bottom = minf(bottom, r.position.y)
	return Rect2(Vector2(full.position.x, top), Vector2(full.size.x, maxf(bottom - top, 0.0)))


# 패널 세로 구간과 하이라이트 사각형이 겹치는 길이. 패널은 화면 폭 전체를 쓰므로
# 세로 겹침이 곧 실제 겹침이다.
func _band_overlap(top: float, height: float, hole: Rect2) -> float:
	return maxf(0.0, minf(top + height, hole.end.y) - maxf(top, hole.position.y))


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
