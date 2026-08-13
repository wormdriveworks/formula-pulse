# SYS-03 옵션 화면 — D09 §6 · 별첨A §A-3.
#
# 탭 5종(§6.4) · 항목 행 = 라벨 ◀ 값 ▶ · **즉시 반영 — 적용 버튼 없음**.
# O5 '비활성' 선택 시 고지 문면 상시 병기(§6.2 — 모멘텀 미발생의 사실 서술, 페널티 어조 금지).
#
# 두 진입 경로를 지원한다: 라우터 경유(타이틀 — payload.return 으로 복귀) /
# 오버레이 인스턴스(일시정지 위 — `closed` 시그널로 호출자가 회수).
extends FlowScreen

signal closed

var _return_route := "SYS-01"
var _overlay_mode := false
var _tab_panels: Array = []


func open_as_overlay(run_session: RunSession) -> void:
	_overlay_mode = true
	bind(run_session, {})


func _on_bound(payload: Dictionary) -> void:
	var s := session.data.strings
	_return_route = String(payload.get("return", "SYS-01"))
	(%HeaderLabel as Label).text = s.text("ui.options.header")
	var reset := %ResetButton as Button
	reset.text = s.text("ui.options.resetDefaults")
	reset.pressed.connect(_on_reset)
	var close := %CloseButton as Button
	close.text = s.text("ui.options.close")
	close.pressed.connect(_on_close)
	_build_tabs()
	_select_tab(0)


func _build_tabs() -> void:
	var s := session.data.strings
	var tab_row := %TabRow as HBoxContainer
	var body := %TabBody as Control
	for index in range(OptionsStore.TABS.size()):
		var tab: Dictionary = OptionsStore.TABS[index]
		var button := Button.new()
		button.name = "Tab%d" % index
		button.text = s.text(String(tab["key"]))
		button.pressed.connect(_select_tab.bind(index))
		tab_row.add_child(button)

		var panel := VBoxContainer.new()
		panel.name = "Panel%d" % index
		panel.add_theme_constant_override("separation", 4)
		panel.visible = false
		body.add_child(panel)
		_tab_panels.append(panel)
		var option_ids: Array = tab["options"]
		if option_ids.is_empty():
			# 조작 탭 — 리매핑은 주요 키 한정(결정 #6)이며 골격은 매핑 안내만 (§1.3 데스크탑)
			var note := Label.new()
			note.text = s.text("ui.options.controlsNote")
			note.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			panel.add_child(note)
			continue
		for option_id in option_ids:
			panel.add_child(_build_row(String(option_id)))


func _build_row(option_id: String) -> Control:
	var s := session.data.strings
	var option: Dictionary = OptionsStore.OPTIONS[option_id]
	var column := VBoxContainer.new()
	column.name = option_id.to_pascal_case() + "Row"
	var row := HBoxContainer.new()
	row.name = "Controls"
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)

	var label := Label.new()
	label.custom_minimum_size = Vector2(150, 0)
	label.text = s.text(String(option["label"]))
	row.add_child(label)

	var prev := Button.new()
	prev.name = "Prev"
	prev.text = s.text("ui.options.stepPrev")
	row.add_child(prev)

	var value := Label.new()
	value.name = "Value"
	value.custom_minimum_size = Vector2(90, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value)

	var next := Button.new()
	next.name = "Next"
	next.text = s.text("ui.options.stepNext")
	row.add_child(next)

	# O5 고지행 — '비활성' 선택 시에만 표출·상시 병기 (D09 §6.2 확정 문면 규격)
	var notice: Label = null
	if option.has("notice"):
		notice = Label.new()
		notice.name = "Notice"
		notice.text = s.text(String(option["notice"]))
		notice.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notice.visible = false
		column.add_child(notice)

	prev.pressed.connect(_shift.bind(option_id, -1, value, notice))
	next.pressed.connect(_shift.bind(option_id, 1, value, notice))
	_refresh_value(option_id, value, notice)
	return column


func _shift(option_id: String, direction: int, value: Label, notice: Label) -> void:
	var store := session.options
	var option: Dictionary = OptionsStore.OPTIONS[option_id]
	var current := store.index_of(option_id)
	if option.get("volume", false):
		current = clampi(current + direction * store.volume_step(), 0, 100)
	else:
		var count := store.step_count(option_id)
		current = wrapi(current + direction, 0, count)
	store.set_index(option_id, current)  # 즉시 반영 — 소비부가 사용 시점마다 읽는다
	_refresh_value(option_id, value, notice)


func _refresh_value(option_id: String, value: Label, notice: Label) -> void:
	var s := session.data.strings
	var store := session.options
	var option: Dictionary = OptionsStore.OPTIONS[option_id]
	var index := store.index_of(option_id)
	if option.get("volume", false):
		var volume_text := s.text("ui.options.volumeFormat", {"value": index})
		value.text = volume_text
	else:
		var steps: Array = option["steps"]
		value.text = s.text(String(steps[index]))
	if notice != null:
		# O5 비활성 = 마지막 단 (타이머 부재 → 모멘텀 조건 불성립 — D05 무개정 성립)
		notice.visible = index == store.step_count(option_id) - 1


func _select_tab(index: int) -> void:
	for panel_index in range(_tab_panels.size()):
		(_tab_panels[panel_index] as Control).visible = panel_index == index


func _on_reset() -> void:
	session.options.reset_defaults()
	session.options.reset_onboarding()  # 1회성 툴팁 재표시 초기화 (COM-02 — §A-24)
	# 전 행 값 갱신 — 재구축이 단순하다
	for panel in _tab_panels:
		for row in (panel as Control).get_children():
			row.queue_free()
	_tab_panels.clear()
	for child in (%TabRow as Control).get_children():
		child.queue_free()
	for child in (%TabBody as Control).get_children():
		child.queue_free()
	_build_tabs()
	_select_tab(0)


func _on_close() -> void:
	if _overlay_mode:
		closed.emit()
		queue_free()
		return
	go(_return_route, {})
