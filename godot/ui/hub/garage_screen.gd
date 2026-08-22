# HUB-01 개러지 (허브) — D09 §4.1 · 별첨A §A-11.
#
# 다이제틱 배경 1장 + 8스테이션 앵커. 배경 아트는 D10 유입 대상이라 지금은 앵커 그리드만 선다 —
# **기능 층 독립 조항 (D09 §4.1 확정):** 스테이션의 기능·개방 조건·내비게이션은 배경 유무와
# 독립으로 성립한다(카드 그리드로 대체 가능). 이 화면이 바로 그 카드 그리드 형태다.
#
# 개방의 시각 번역: 미개방 = 소등 + 개방 조건 라벨(크루명). 크루 합류 시 점등 (D07 §2.1).
# E09 출발 버튼은 허브 상시 고정 — 필수 동선 2단(정비→덱)과 함께 3입력 내 출발 성립.
extends HubScreen

# 스테이션 정의: [노드명, 라벨 키, 라우트, 개방 조건 크루 id ("" = 상시)]
const STATIONS := [
	["StRepair", "ui.hub.stRepair", "HUB-02", ""],
	["StTuning", "ui.hub.stTuning", "HUB-03", ""],
	["StStrategy", "ui.hub.stStrategy", "HUB-04", ""],
	["StRecords", "ui.hub.stRecords", "HUB-05", ""],
	["StSponsor", "ui.hub.stSponsor", "HUB-06", "crew_nadia"],
	["StFacility", "ui.hub.stFacility", "HUB-07", ""],
	["StOverhaul", "ui.hub.stOverhaul", "HUB-08", ""],
	["StRecruit", "ui.hub.stRecruit", "", ""],
]


# 허브 BGM(BGM-02) + 개러지 룸톤(AMB-04). 정거장 진입음이 아니라 **차고 자체**에 붙는다 —
# 하위 스테이션(HUB-02~08)에서 돌아올 때 BGM 은 같은 트랙이라 재시작하지 않는다(디스패처 판정).
func _audio_enter_events() -> Array:
	return ["hub_enter"]


func _on_hub_ready(_payload: Dictionary) -> void:
	var s := session.data.strings
	(%HeaderLabel as Label).text = s.text("ui.hub.garageTitle")
	(%BackButton as Button).visible = false  # 허브 자신 — 뒤로 갈 곳이 없다
	for entry in STATIONS:
		var button := get_node("%%%s" % String(entry[0])) as Button
		button.text = s.text(String(entry[1]))
		var route := String(entry[2])
		var required_crew := String(entry[3])
		var open := required_crew.is_empty() or session.outgame.crew.has(required_crew)
		if not open:
			# 미개방 = 소등 + 개방 조건 라벨 (크루명 — 관계 전이 조건류가 아니므로 노출 가능)
			button.disabled = true
			button.focus_mode = Control.FOCUS_NONE
			var crew_name := s.text(String(session.data.crew[required_crew]["name_key"]))
			var locked_text := s.text("ui.hub.stationLockedFormat", {
				"station": s.text(String(entry[1])), "crew": crew_name,
			})
			button.text = locked_text
		elif route.is_empty():
			# 크루 영입은 이벤트 발생 시 점등 (별첨A E08) — 영입 이벤트 층 결선 전이라 소등
			button.disabled = true
			button.focus_mode = Control.FOCUS_NONE
		else:
			button.pressed.connect(func(): go(route, {}))
		# HUB-08 시즌 오버홀은 시즌 결산 직후 전용 진입 (G-M2 물리 분리 — D09 §4.6).
		# 허브에서 재진입 불가가 규격이므로 앵커는 상시 소등이다.
		if String(entry[0]) == "StOverhaul":
			button.disabled = true
			button.focus_mode = Control.FOCUS_NONE

	var depart := %DepartButton as Button
	depart.text = s.text("ui.hub.depart")
	depart.pressed.connect(_on_depart)
	depart.grab_focus()  # 초기 포커스 = E09 (재방문 시 — §A-11)
	_show_currency_onboarding()


# COM-02 1회성 온보딩 툴팁 — 재화 2종 최초 노출 시 기능 명시 (D09 §5.2 · 별첨A §A-24).
# 자동 표출 + 확인으로 소멸 + 옵션에서 초기화 가능. 기록은 기기별 옵션 파일에 남는다.
func _show_currency_onboarding() -> void:
	if session.options.onboarding_seen.has("currency"):
		return
	var s := session.data.strings
	var panel := PanelContainer.new()
	panel.name = "OnboardingTip"
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position.y = 40
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.BG_PANEL
	style.border_color = UiPalette.TIMER_LEEWAY
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", _head_font_size)
	title.text = s.text("ui.tip.currencyTitle")
	column.add_child(title)
	var body := Label.new()
	body.add_theme_font_size_override("font_size", _body_font_size)
	body.text = s.text("ui.tip.currencyBody")
	body.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(260, 0)
	column.add_child(body)
	var confirm := Button.new()
	confirm.add_theme_font_size_override("font_size", _body_font_size)
	confirm.text = s.text("ui.tip.dismiss")
	confirm.pressed.connect(func():
		session.options.mark_onboarding("currency")
		panel.queue_free())
	column.add_child(confirm)


func _on_depart() -> void:
	# 투어 경계 저장 지점 (D09 §2.4 — SET-01 ⑧ 개러지 귀환 후 출발 전 최신화)
	session.save_progress()
	# 투어 시작 VN — 플로우맵의 "개러지 → 투어 시작 VN → 다음 투어" 지점이다(D09 §2.3).
	# HUB-01 은 **투어 경계에만** 서므로(대회 사이는 RUN-01/02 경유) 이 자리가 곧 브리핑 슬롯이다.
	var act_vn := session.take_brief_payload("RACE-01")
	if not act_vn.is_empty():
		go("NAR-01", act_vn)
		return
	go("RACE-01", {})
