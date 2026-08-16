# SYS-04 업적 화면 — D09 §5.5 · 별첨A §A-4.
#
# 5카테고리 탭 + 달성률 요약 헤더. 항목 행 = 상태 표기 · 명칭 · 조건 진척.
# **히든(발견형 4 + 관계 도달형 5 = 9종)은 달성 전 "???" 슬롯**으로만 존재한다 —
# 명칭·조건 전부 비노출이되 자리는 남겨 총수 가늠은 허용한다(§5.5 확정 규격).
# 무보상 명예형이므로 **보상 열 자체가 없다**(D07 §7.1 — Source 신설 금지).
#
# **발견형 4종은 라이벌 탭에 든다.** 데이터의 `category` 열은 'discovery' 지만 그것은
# 조건 유형이지 카테고리가 아니다(D07 §7.1 · 총괄 판정 IMPL-121 ②). 데이터 열을 고치지 않고
# 표시 층에서 묶는 이유는 TC-O 가 category 계수를 6종으로 못박고 있어(원격 데이터 계약)
# 열을 바꾸면 데이터 검사와 화면 규격이 서로를 무효화하기 때문이다.
#
# 두 진입 경로를 지원한다(SYS-03 전례): 라우터 경유(타이틀 — payload.return 으로 복귀) /
# 오버레이 인스턴스(일시정지 위 — `closed` 시그널로 호출자가 회수).
extends FlowScreen

signal closed

# 탭 = D07 §7.1 5카테고리. `categories` = 이 탭이 흡수하는 데이터 category 값.
const TABS := [
	{"key": "ui.achievement.tabCareer", "categories": ["career"]},
	{"key": "ui.achievement.tabRival", "categories": ["rival", "discovery"]},
	{"key": "ui.achievement.tabDriving", "categories": ["driving"]},
	{"key": "ui.achievement.tabGarage", "categories": ["garage"]},
	{"key": "ui.achievement.tabArchive", "categories": ["archive"]},
]

var _return_route := "SYS-01"
var _overlay_mode := false
var _tab_panels: Array = []
# 코드로 만든 Control 은 프로젝트 기본 폰트 크기를 상속하지 않고 **엔진 기본 테마의 16** 으로
# 해석된다(실측). 본문 계열 9 는 D10 §5.7 확정단이므로 데이터 창구에서 읽어 명시 적용한다
# (불변규칙 2 — 코드 기입 금지 · log_feed.gd 전례).
var _body_font_size := 9


func open_as_overlay(run_session: RunSession) -> void:
	_overlay_mode = true
	bind(run_session, {})


func _on_bound(payload: Dictionary) -> void:
	var s := session.data.strings
	_return_route = String(payload.get("return", "SYS-01"))
	_body_font_size = int(session.data.param("param_font_size_body"))
	var header_text := s.text("ui.achievement.header")
	(%HeaderLabel as Label).text = header_text
	var close := %CloseButton as Button
	close.text = s.text("ui.achievement.close")
	close.pressed.connect(_on_close)
	_refresh_summary()
	_build_tabs()
	_select_tab(0)


# 달성률 요약 헤더 (§A-4). 히든 미달성분도 분모에 든다 — 총수 가늠 허용이 §5.5 명문이다.
func _refresh_summary() -> void:
	var total := session.data.achievements.size()
	var done := 0
	for achievement_id in session.data.achievements:
		if session.outgame.achievements.has(achievement_id):
			done += 1
	var percent := 0
	if total > 0:
		percent = int(round(float(done) * 100.0 / float(total)))
	var summary_text := session.data.strings.text("ui.achievement.summaryFormat", {
		"done": done,
		"total": total,
		"percent": percent,
	})
	(%SummaryLabel as Label).text = summary_text


func _build_tabs() -> void:
	var s := session.data.strings
	var tab_row := %TabRow as HBoxContainer
	var body := %TabBody as Control
	for index in range(TABS.size()):
		var tab: Dictionary = TABS[index]
		var button := Button.new()
		button.name = "Tab%d" % index
		button.text = s.text(String(tab["key"]))
		button.add_theme_font_size_override("font_size", _body_font_size)
		button.pressed.connect(_select_tab.bind(index))
		tab_row.add_child(button)

		# 라이벌 탭은 18행 — 캔버스 세로 360 에 들어가지 않으므로 탭마다 스크롤을 둔다.
		var scroll := ScrollContainer.new()
		scroll.name = "Scroll%d" % index
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.visible = false
		body.add_child(scroll)

		var panel := VBoxContainer.new()
		panel.name = "Panel%d" % index
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_constant_override("separation", 2)
		scroll.add_child(panel)
		_tab_panels.append(scroll)

		for achievement_id in _ids_for(Array(tab["categories"])):
			panel.add_child(_build_row(String(achievement_id)))


# 탭에 드는 업적 id — 데이터 적재 순서를 따른다(D08 §8.11 열거 순 = CSV 행 순).
func _ids_for(categories: Array) -> Array:
	var ids: Array = []
	for achievement_id in session.data.achievements:
		var row: Dictionary = session.data.achievements[achievement_id]
		if categories.has(String(row["category"])):
			ids.append(String(achievement_id))
	return ids


func _build_row(achievement_id: String) -> Control:
	var s := session.data.strings
	var row_data: Dictionary = session.data.achievements[achievement_id]
	var progress: Dictionary = session.outgame.achievement_progress(achievement_id)
	var met := bool(progress["met"])
	var hidden := CsvTable.to_int(String(row_data["hidden"])) == 1

	var row := HBoxContainer.new()
	row.name = achievement_id.to_pascal_case() + "Row"
	row.add_theme_constant_override("separation", 6)

	# 히든 미달성 = "???" 슬롯 하나로 끝 (명칭·조건·아이콘 전부 비노출 — §5.5)
	if hidden and not met:
		var masked := Label.new()
		masked.name = "Masked"
		var masked_text := s.text("ui.achievement.hiddenSlot")
		masked.text = masked_text
		masked.add_theme_font_size_override("font_size", _body_font_size)
		masked.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		row.add_child(masked)
		return row

	var mark := Label.new()
	mark.name = "Mark"
	mark.custom_minimum_size = Vector2(44, 0)
	var mark_text := s.text("ui.achievement.markDone") if met else s.text("ui.achievement.markPending")
	mark.text = mark_text
	mark.add_theme_font_size_override("font_size", _body_font_size)
	mark.add_theme_color_override("font_color",
		UiPalette.TEXT_PRIMARY if met else UiPalette.TEXT_DIM)
	row.add_child(mark)

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.custom_minimum_size = Vector2(190, 0)
	var name_text := s.text(String(row_data["name_key"]))
	name_label.text = name_text
	name_label.add_theme_font_size_override("font_size", _body_font_size)
	if not met:
		name_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	row.add_child(name_label)

	# 조건 축 — **임계가 2 이상인 축적형에만 진척을 적는다** [가안].
	# 임계 1 인 도달형은 명칭 자체가 조건 문면이라("첫 포디움") "0 / 1" 이 정보를 더하지 않는다.
	# 조건 전용 문면은 정본에 없다 — 별도 문안이 서면 이 자리에 든다.
	var threshold := int(progress["threshold"])
	if threshold > 1:
		var progress_label := Label.new()
		progress_label.name = "Progress"
		var progress_text := s.text("ui.achievement.progressFormat", {
			"current": mini(int(progress["current"]), threshold),
			"threshold": threshold,
		})
		progress_label.text = progress_text
		progress_label.add_theme_font_size_override("font_size", _body_font_size)
		progress_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		row.add_child(progress_label)
	return row


func _select_tab(index: int) -> void:
	for panel_index in range(_tab_panels.size()):
		(_tab_panels[panel_index] as Control).visible = panel_index == index


func _on_close() -> void:
	if _overlay_mode:
		closed.emit()
		queue_free()
		return
	go(_return_route, {})
