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
var _active_tab := 0


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
	close.set_meta(AUDIO_EVENT_META, "ui_cancel")   # SE-U03 취소·닫기
	close.pressed.connect(_on_close)
	_build_tabs()
	_select_tab(0)
	_focus_initial()


# ── 패드 순회 폐쇄 (D09 §1.3 89행 · 총괄 판정 IMPL-176 ②) ──
#
# **초기 포커스 = 첫 탭 첫 항목** (§A-3 명시). 항목 행의 첫 조작 요소는 단계 감소 버튼이다 —
# 라벨은 포커스를 받지 않으므로 "첫 항목"의 실물은 그 버튼이다.
# 조작 탭처럼 항목이 없는 탭이 첫 탭이 되는 경우를 대비해 탭 버튼으로 물러선다.
func _focus_initial() -> void:
	if not _tab_panels.is_empty():
		var first_panel := _tab_panels[0] as Control
		if first_panel.get_child_count() > 0:
			var focusable := _first_focusable(first_panel.get_child(0) as Control)
			if focusable != null:
				focusable.grab_focus()
				return
	var tab_row := %TabRow as Control
	if tab_row.get_child_count() > 0:
		(tab_row.get_child(0) as Control).grab_focus()


func _first_focusable(node: Control) -> Control:
	if node.focus_mode != Control.FOCUS_NONE:
		return node
	for child in node.get_children():
		if child is Control:
			var found := _first_focusable(child as Control)
			if found != null:
				return found
	return null


# 취소 / 뒤로 = Esc · 우클릭 · **패드 B** (D09 §1.3 공통 층 매핑표 — 정본 명시).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("tab_prev"):
		get_viewport().set_input_as_handled()
		_cycle_tab(-1)
		return
	if event.is_action_pressed("tab_next"):
		get_viewport().set_input_as_handled()
		_cycle_tab(1)
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_on_close()

# ── 탭 순회 (D09 §1.3 '탭 전환 = Q·E | LB·RB' · 총괄 판정 IMPL-190 ②) ──
#
# 액션 청취를 **추가**한다 — 버튼 `pressed` 경로는 그대로다(마우스·포커스 조작 불변).
# 액션이 없으면 탭을 바꾸려고 탭 버튼까지 포커스를 옮겨야 하는데, 그러면 본문에서
# 나갔다 들어오는 왕복이 매번 생긴다.
#
# **[가안] 경계에서 감긴다(wrap)** — D09 는 순환 방향·경계에 침묵한다. 탭이 3~5개로 적고
# 끝에서 막히면 반대 방향 키를 다시 찾아야 하므로 감는 편이 조작 비용이 낮다고 봤다.
func _cycle_tab(step: int) -> void:
	if _tab_panels.is_empty():
		return
	_select_tab(wrapi(_active_tab + step, 0, _tab_panels.size()))


func _build_tabs() -> void:
	var s := session.data.strings
	var tab_row := %TabRow as HBoxContainer
	var body := %TabBody as Control
	for index in range(OptionsStore.TABS.size()):
		var tab: Dictionary = OptionsStore.TABS[index]
		var button := Button.new()
		button.name = "Tab%d" % index
		button.text = s.text(String(tab["key"]))
		button.add_theme_font_size_override("font_size", _body_font_size)
		button.set_meta(AUDIO_EVENT_META, "ui_tab")   # SE-U04 — 결정음이 아니라 탭 전환음
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
			note.add_theme_font_size_override("font_size", _body_font_size)
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
	label.add_theme_font_size_override("font_size", _body_font_size)
	row.add_child(label)

	var prev := Button.new()
	prev.name = "Prev"
	prev.text = s.text("ui.options.stepPrev")
	prev.add_theme_font_size_override("font_size", _body_font_size)
	row.add_child(prev)

	var value := Label.new()
	value.name = "Value"
	value.custom_minimum_size = Vector2(90, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", _body_font_size)
	row.add_child(value)

	var next := Button.new()
	next.name = "Next"
	next.text = s.text("ui.options.stepNext")
	next.add_theme_font_size_override("font_size", _body_font_size)
	row.add_child(next)

	# O5 고지행 — '비활성' 선택 시에만 표출·상시 병기 (D09 §6.2 확정 문면 규격)
	var notice: Label = null
	if option.has("notice"):
		notice = Label.new()
		notice.name = "Notice"
		notice.text = s.text(String(option["notice"]))
		notice.add_theme_font_size_override("font_size", _body_font_size)
		notice.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notice.visible = false
		column.add_child(notice)

	# 단계 이동은 결정이 아니다 — 빈 메타로 일반 결정음을 끄고 `_shift()` 가 토글음을 낸다.
	prev.set_meta(AUDIO_EVENT_META, "")
	next.set_meta(AUDIO_EVENT_META, "")
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
	# 팔레트는 세션을 쥘 수 없는 정적 클래스라 소비 시점에 스스로 읽지 못한다 —
	# 옵션이 바뀌는 두 지점(화면 진입 · 여기) 중 하나다. 빠뜨리면 O9 가 다음 화면부터 먹는다.
	UiPalette.apply_options(store)
	# 볼륨도 같은 성격이다 — 버스는 옵션을 스스로 읽지 못한다(O13~O15).
	session.apply_volume_options()
	session.apply_haptic_options()   # O3 진동 감쇠도 같은 자리다
	# O11 언어도 같은 성격이다 — 스트링 표는 옵션을 스스로 읽지 못한다.
	session.apply_language()
	sfx("ui_toggle")   # SE-U05 토글·슬라이더 — 단계 이동과 볼륨 이동이 같은 축이다
	# ── 언어 전환 = 이 화면 전체 재문면화 (14차 ③ · 13차 이월) ──
	#
	# 전환은 즉시 반영되지만 **이미 세워진 라벨은 스스로 갱신되지 않았다**: 표제·탭 5종·
	# 항목 라벨·◀▶·O5 고지행·닫기·초기화가 전부 진입 시점 언어로 굳어 있고 바뀌는 것은
	# 방금 만진 값 하나뿐이었다. **언어를 바꾼 화면이 바뀐 언어로 보이지 않으면 그 조작은
	# 확인되지 않는다** — 즉시 반영(§6.3 적용 버튼 없음)의 취지가 이 항목에서만 성립하지
	# 않고 있었다.
	#
	# **다시 세우고 자리를 되돌린다.** 라벨을 하나씩 찾아 고치는 방식은 만든 곳과 고치는
	# 곳이 갈려 새 라벨이 생길 때마다 한쪽을 빠뜨린다(문면 이중 관리). `_build_tabs()` 가
	# 문면의 유일한 산지이므로 그것을 다시 부르는 편이 갈라지지 않는다. 대가는 활성 탭과
	# 포커스 소실이라 **그 둘만 떠서 되돌린다** — 노드 이름이 결정적이라(`Panel%d` ·
	# `<Option>Row` · `Prev`/`Next`) 경로가 재생성 뒤에도 같은 자리를 가리킨다.
	if option.get("languages", false):
		_relabel_all()
		return
	_refresh_value(option_id, value, notice)


func _relabel_all() -> void:
	var tab := _active_tab
	var focused := get_viewport().gui_get_focus_owner()
	var focus_path := get_path_to(focused) if focused != null and is_ancestor_of(focused) else NodePath()
	var tab_row := %TabRow as HBoxContainer
	var body := %TabBody as Control
	for child in tab_row.get_children():
		tab_row.remove_child(child)
		child.queue_free()
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	_tab_panels.clear()
	var s := session.data.strings
	(%HeaderLabel as Label).text = s.text("ui.options.header")
	(%ResetButton as Button).text = s.text("ui.options.resetDefaults")
	(%CloseButton as Button).text = s.text("ui.options.close")
	_build_tabs()
	_select_tab(mini(tab, maxi(_tab_panels.size() - 1, 0)))
	# 포커스를 되돌린다. 되돌릴 자리가 사라졌으면(경로 부재) 초기 자리로 물러선다 —
	# 포커스가 없는 화면은 패드에서 조작 불가가 되므로 무포커스로 끝내지 않는다.
	var restored: Control = null
	if not focus_path.is_empty():
		restored = get_node_or_null(focus_path) as Control
	if restored != null:
		restored.grab_focus()
	else:
		_focus_initial()


func _refresh_value(option_id: String, value: Label, notice: Label) -> void:
	var s := session.data.strings
	var store := session.options
	var option: Dictionary = OptionsStore.OPTIONS[option_id]
	var index := store.index_of(option_id)
	if option.get("volume", false):
		var volume_text := s.text("ui.options.volumeFormat", {"value": index})
		value.text = volume_text
	else:
		# 단계 라벨은 **저장소 경유**다 — O11 은 목록이 표 헤더에서 오므로 화면이
		# `option["steps"]` 를 직접 읽으면 그 항목에서 키가 없어 죽는다.
		value.text = s.text(store.step_label(option_id, index))
	if notice != null:
		# O5 비활성 = 마지막 단 (타이머 부재 → 모멘텀 조건 불성립 — D05 무개정 성립)
		notice.visible = index == store.step_count(option_id) - 1


# 활성 탭 표시 — **[가안] 신설** (총괄 회신 §4-③ · 7차 §6-① 이월분).
#
# D09 는 활성 탭의 시각 표시에 침묵한다(§1.3 은 입력만, §A-3·§A-4 는 탭 구성만).
# 그런데 표시가 없으면 **LB/RB 가 먹지 않는 것처럼 보인다** — 마우스·키보드로는 눌린 탭에
# 포커스 링이 남아 우연히 활성 표시처럼 보이지만, 액션으로 돌리면 내용만 바뀌고
# 탭 줄에서는 아무것도 움직이지 않는다(7차 실측).
#
# **포커스와 활성은 다른 축이다** — 포커스는 "지금 어디를 조작하려는가", 활성은
# "지금 무엇을 보고 있는가"다. 그래서 포커스 링에 얹지 않고 색으로 따로 표시한다.
#
# 색은 **기확정 슬롯 2종**이다(신규 색 0): 활성 = `ACCENT_ACTIVE` C3(정본 증보 2 의
# '활성 강조' 역할) · 비활성 = `TEXT_PRIMARY` N16. **비활성을 감광하지 않는 이유** —
# 탭 5종은 전부 도달 가능하므로 흐리게 두면 잠긴 것으로 오독된다. 활성은 밝기가 아니라
# 색상으로 갈린다.
func _mark_active_tab() -> void:
	var tab_row := %TabRow as Control
	for index in range(tab_row.get_child_count()):
		var button := tab_row.get_child(index) as Button
		if button == null:
			continue
		button.add_theme_color_override("font_color",
			UiPalette.ACCENT_ACTIVE if index == _active_tab else UiPalette.TEXT_PRIMARY)
		# 포커스가 옮겨 가도 활성 표시는 유지돼야 한다 — 세 상태 전부 같은 색으로 고정한다.
		button.add_theme_color_override("font_hover_color",
			UiPalette.ACCENT_ACTIVE if index == _active_tab else UiPalette.TEXT_PRIMARY)
		button.add_theme_color_override("font_focus_color",
			UiPalette.ACCENT_ACTIVE if index == _active_tab else UiPalette.TEXT_PRIMARY)

func _select_tab(index: int) -> void:
	_active_tab = index
	for panel_index in range(_tab_panels.size()):
		(_tab_panels[panel_index] as Control).visible = panel_index == index
	_mark_active_tab()


func _on_reset() -> void:
	session.options.reset_defaults()
	session.apply_volume_options()   # 기본값 복귀도 버스에 닿아야 한다
	session.apply_haptic_options()
	session.options.reset_onboarding()  # 1회성 툴팁 재표시 초기화 (COM-02 — §A-24)
	# **초기화도 언어를 되돌린다** (O11 기본값 복귀) — 그러므로 재구축만으로는 부족하고
	# 표제·닫기·초기화 문면까지 다시 세워야 한다. `_relabel_all()` 이 그 전부를 진다.
	#
	# 종전 구현은 `queue_free()` 만 하고 `remove_child()` 를 하지 않은 채 곧바로
	# `_build_tabs()` 를 불렀다 — 죽기로 예약된 노드가 한 프레임 동안 트리에 남아
	# **이름이 충돌**하고(`Tab0` → `Tab0@2`) 그 프레임의 `get_child(0)` 는 사라질 노드를
	# 집는다. 재문면화 경로와 같은 절차로 합쳐 그 형태를 지운다.
	session.apply_language()
	_relabel_all()


func _on_close() -> void:
	if _overlay_mode:
		closed.emit()
		queue_free()
		return
	go(_return_route, {})
