# HUB-05 기록실 — D09 §4.5 · 별첨A §A-15. 3탭: 라이벌 파일 / 통산 기록 / 아카이브.
#
# 라이벌 파일: 카드 = 초상(아트 유입 대상)·현재 관계 상태 명칭.
# **다음 전이 조건 비노출 (필수)** — 조건 힌트·진행 게이지류 일절 금지 (D09 §4.5).
# 축 비대상 라이벌은 관계 상태란 자체가 없다.
#
# 아카이브: **무상·상시 (절대 규격)** — 재화·시설·해금 게이트 표시 자체가 존재하지 않는다
# (P-1 ④ · D01 G2 조건 2). VN 재생 결선은 NAR-01 구현 후.
extends HubScreen

var _tabs: Dictionary = {}
var _active_tab := ""


func _on_hub_ready(_payload: Dictionary) -> void:
	var s := session.data.strings
	(%HeaderLabel as Label).text = s.text("ui.records.title")
	_tabs = {
		"rivals": {"button": %TabRivals, "panel": %PanelRivals},
		"career": {"button": %TabCareer, "panel": %PanelCareer},
		"archive": {"button": %TabArchive, "panel": %PanelArchive},
	}
	(%TabRivals as Button).text = s.text("ui.records.tabRivals")
	(%TabCareer as Button).text = s.text("ui.records.tabCareer")
	(%TabArchive as Button).text = s.text("ui.records.tabArchive")
	for tab_name in _tabs:
		var tab_button := _tabs[tab_name]["button"] as Button
		# 탭 전환음(SE-U04)은 결정음(SE-U02)과 다른 축이다 — 조작음 자동 결속이 이 메타를 읽어
		# 기본 결정음 대신 탭음을 붙인다. `_select_tab()` 은 진입 초기화에서도 불리므로
		# 거기서 울리면 화면에 들어서기만 해도 탭음이 난다.
		tab_button.set_meta(AUDIO_EVENT_META, "ui_tab")
		tab_button.pressed.connect(_select_tab.bind(String(tab_name)))
	_fill_rivals()
	_fill_career()
	_fill_archive()
	_select_tab("rivals")
	(%TabRivals as Button).grab_focus()


func _select_tab(tab_name: String) -> void:
	_active_tab = tab_name
	for entry_name in _tabs:
		(_tabs[entry_name]["panel"] as Control).visible = String(entry_name) == tab_name


# ── 탭 순회 (D09 §1.3 '탭 전환 = Q·E | LB·RB' · 총괄 판정 IMPL-190 ②) ──
#
# 액션 청취를 **추가**한다 — 버튼 `pressed` 경로는 그대로다(마우스·포커스 조작 불변).
# **[가안] 경계에서 감긴다(wrap)** — D09 는 순환 방향·경계에 침묵한다.
# 탭 순서는 `_tabs` 의 삽입 순서 = 화면의 탭 배치 순서다(별도 순서 배열을 두지 않는다).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("tab_prev"):
		_cycle_tab(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("tab_next"):
		_cycle_tab(1)
		get_viewport().set_input_as_handled()


func _cycle_tab(step: int) -> void:
	var names := _tabs.keys()
	if names.is_empty():
		return
	var at := names.find(_active_tab)
	if at < 0:
		at = 0
	_select_tab(String(names[wrapi(at + step, 0, names.size())]))


func _fill_rivals() -> void:
	var s := session.data.strings
	var list := %PanelRivals as VBoxContainer
	for rival_row in session.data.rivals:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_label := Label.new()
		name_label.add_theme_font_size_override("font_size", _body_font_size)
		name_label.custom_minimum_size = Vector2(110, 0)
		name_label.text = s.text(String(rival_row["name_key"]))
		row.add_child(name_label)
		# 관계 상태 — 축 대상 라이벌만. 상태 명칭만 표시하고 전이 조건·게이지는 절대 금지.
		var axis := _relation_axis_for(String(rival_row["id"]))
		if not axis.is_empty():
			var stage := session.outgame.relation_stage(axis)
			var stage_label := Label.new()
			stage_label.add_theme_font_size_override("font_size", _body_font_size)
			var relation_text := s.text("ui.records.relationFormat", {
				"axis": s.text(String(session.data.relation_axes[axis]["name_key"])),
				"stage": stage,
			})
			stage_label.text = relation_text
			stage_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
			row.add_child(stage_label)
		list.add_child(row)


func _relation_axis_for(rival_id: String) -> String:
	for relation_id in session.data.relation_axes:
		if String(session.data.relation_axes[relation_id]["rival_id"]) == rival_id:
			return String(relation_id)
	return ""


func _fill_career() -> void:
	var s := session.data.strings
	var panel := %PanelCareer as VBoxContainer
	# 주행 데이터 생애 누적 획득 총량 상시 표시 (D06 R7) — 아이콘 동반 (B-1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var icon := TextureRect.new()
	icon.texture = load(ICON_DIR + "currency_data_16.png")
	icon.custom_minimum_size = Vector2(16, 16)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(icon)
	var total := Label.new()
	total.add_theme_font_size_override("font_size", _body_font_size)
	var total_text := s.text("ui.records.dpTotalFormat", {
		"amount": session.outgame.drive_data_earned_total,
	})
	total.text = total_text
	row.add_child(total)
	panel.add_child(row)


func _fill_archive() -> void:
	var s := session.data.strings
	var panel := %PanelArchive as VBoxContainer
	# 게이트 표시 요소 전무 (무상·상시 — D01 G2 조건 2). 발생분 전량 등재 — 스킵분 동일 취급.
	# 미발생 이벤트는 목록 비표시 (스포일러 방지).
	var entries := session.narrative.archive_entries()
	if entries.is_empty():
		var empty := Label.new()
		empty.add_theme_font_size_override("font_size", _body_font_size)
		empty.text = s.text("ui.records.archiveEmpty")
		empty.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		panel.add_child(empty)
		return
	for vn_id in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_label := Label.new()
		name_label.add_theme_font_size_override("font_size", _body_font_size)
		name_label.text = _vn_title(String(vn_id))
		name_label.custom_minimum_size = Vector2(140, 0)
		row.add_child(name_label)
		var replay := Button.new()
		replay.add_theme_font_size_override("font_size", _body_font_size)
		replay.text = s.text("ui.records.replay")
		# 재생 모드 — 동일 화면 + 종료 시 아카이브 복귀 (§A-19). 전이 재발화 없음(멱등).
		replay.pressed.connect(func(): go("NAR-01", {
			"vn_id": String(vn_id), "replay": true, "next": "HUB-05",
		}))
		row.add_child(replay)
		panel.add_child(row)


# [가안] VN 인스턴스 id → 표제: 실문안 대장(D04 트랙) 유입 전까지 슬롯 유형으로 표기
func _vn_title(vn_id: String) -> String:
	var s := session.data.strings
	if vn_id.begins_with("vn_season_open"):
		return s.text("ui.vnSlot.seasonOpen")
	if vn_id.begins_with("vn_season_close"):
		return s.text("ui.vnSlot.seasonClose")
	if vn_id.begins_with("vn_tour_brief"):
		return s.text("ui.vnSlot.tourBrief")
	return vn_id