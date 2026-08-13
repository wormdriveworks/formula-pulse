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
		(_tabs[tab_name]["button"] as Button).pressed.connect(_select_tab.bind(String(tab_name)))
	_fill_rivals()
	_fill_career()
	_fill_archive()
	_select_tab("rivals")
	(%TabRivals as Button).grab_focus()


func _select_tab(tab_name: String) -> void:
	for entry_name in _tabs:
		(_tabs[entry_name]["panel"] as Control).visible = String(entry_name) == tab_name


func _fill_rivals() -> void:
	var s := session.data.strings
	var list := %PanelRivals as VBoxContainer
	for rival_row in session.data.rivals:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_label := Label.new()
		name_label.custom_minimum_size = Vector2(110, 0)
		name_label.text = s.text(String(rival_row["name_key"]))
		row.add_child(name_label)
		# 관계 상태 — 축 대상 라이벌만. 상태 명칭만 표시하고 전이 조건·게이지는 절대 금지.
		var axis := _relation_axis_for(String(rival_row["id"]))
		if not axis.is_empty():
			var stage := session.outgame.relation_stage(axis)
			var stage_label := Label.new()
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
	icon.texture = load(ICON_DIR + "currency_data.png")
	icon.custom_minimum_size = Vector2(16, 16)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(icon)
	var total := Label.new()
	var total_text := s.text("ui.records.dpTotalFormat", {
		"amount": session.outgame.drive_data_earned_total,
	})
	total.text = total_text
	row.add_child(total)
	panel.add_child(row)


func _fill_archive() -> void:
	var s := session.data.strings
	var panel := %PanelArchive as VBoxContainer
	# 게이트 표시 요소 전무 — 발생 VN이 아직 없으므로 빈 목록 문면만 (스포일러 방지:
	# 미발생 이벤트는 목록 비표시가 규격이다)
	var empty := Label.new()
	empty.text = s.text("ui.records.archiveEmpty")
	empty.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	panel.add_child(empty)