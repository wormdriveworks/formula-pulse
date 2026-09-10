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
			# 진입 직전에 자리를 적는다 — 돌아온 개러지가 이 앵커에 포커스를 둔다 (개선 회차 16).
			button.pressed.connect(func() -> void:
				session.last_hub_station = route
				go(route, {}))
		# HUB-08 시즌 오버홀은 시즌 결산 직후 전용 진입 (G-M2 물리 분리 — D09 §4.6).
		# 허브에서 재진입 불가가 규격이므로 앵커는 상시 소등이다.
		if String(entry[0]) == "StOverhaul":
			button.disabled = true
			button.focus_mode = Control.FOCUS_NONE

	var depart := %DepartButton as Button
	depart.text = s.text("ui.hub.depart")
	depart.pressed.connect(_on_depart)
	# 초기 포커스 = 첫 스테이션 (개선 2026-09-02 H6 — §A-11 "초기 포커스 = E09" 를 사용자
	# 지시로 뒤집음). 출발은 **비가역 전이**다(저장 + 브리핑 소비 + 허브 복귀 불가) — 직전
	# VN 을 확정 연타로 넘기던 관성 입력 1회가 그대로 출발을 눌러 허브 전체가 건너뛰어졌다
	# (실기 검증 중 4회 연속 재현). 출발 자체는 한 칸 아래 이웃이라 의도 도달 비용은 낮다.
	# **하위 스테이션에서 돌아온 개러지는 직전에 진입했던 앵커다** (개선 회차 16 · 2026-09-11 사용자
	# 요청). 종전에는 복귀마다 첫 스테이션으로 튀어 정비→튜닝→전략을 차례로 도는 동선이 매번 처음부터
	# 였다. 기억은 세션(`last_hub_station`)이 쥐고 출발이 비우므로 레이스 뒤의 개러지는 위 기본값이다.
	_initial_station().grab_focus()
	_show_currency_onboarding()


# 초기 포커스 앵커 — 기억된 스테이션이 있고 그 앵커가 살아 있으면 그 자리, 아니면 첫 스테이션.
# 소등 앵커(미개방 스폰서 · 상시 소등 오버홀)와 모르는 라우트는 첫 스테이션으로 접는다 —
# 포커스를 받을 수 없는 버튼에 `grab_focus()` 를 걸면 포커스가 어디에도 없는 화면이 된다.
func _initial_station() -> Button:
	var first := %StRepair as Button
	var remembered := session.last_hub_station
	if remembered.is_empty():
		return first
	for entry in STATIONS:
		if String(entry[2]) != remembered:
			continue
		var button := get_node("%%%s" % String(entry[0])) as Button
		if button.disabled or button.focus_mode == Control.FOCUS_NONE:
			return first
		return button
	return first


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
	# 개러지를 떠난다 — 복귀 포커스 기억을 비운다. 레이스에서 돌아온 개러지는 첫 스테이션(정비)이
	# 자연스럽고, 기억이 남아 있으면 지난 GP 의 마지막 방문지가 다음 GP 첫 화면의 포커스가 된다 (개선 회차 16).
	session.last_hub_station = ""
	# 출발 전 저장 (D09 §2.4 "개러지 귀환 후 출발 전 최신화") — 개러지가 GP 마다 서므로 이 저장도 GP 마다다
	# (개선 회차 10 · 2026-09-08 사용자 결정 — 간이 정산 화면 소거 · 레이스 ↔ 개러지 반복).
	session.save_progress()
	# 브리핑 VN — 플로우맵의 "개러지 → 투어 시작 VN → 다음 투어" 지점이다(D09 §2.3).
	# 종전에는 HUB-01 이 투어 경계에만 서서 이 자리가 곧 브리핑 슬롯이었다. 지금은 매 GP 지나는 자리라
	# **투어 첫 GP 앞의 출발에만** 발행하는 게이트를 세션 창구가 쥔다(`take_brief_payload` · race_slot == 1) —
	# 화면은 조건을 모르고 빈 사전이면 그대로 레이스로 간다.
	var act_vn := session.take_brief_payload("RACE-01")
	# 시즌 오프닝 VN 은 정본이 **HUB-01 뒤**에 둔다(D09 §2.3 `HUB-01 → 다음 시즌 오프닝 VN`).
	# 그래서 개막이 브리핑 **앞**에 붙는다 — 시즌의 머리이고, 그 뒤가 그 시즌 첫 투어의 브리핑이다.
	# 시즌당 1회 가드는 세션이 쥐고 있다(발생 대장 — 이 자리는 투어마다 지나간다).
	var opening := session.season_open_payload(
		"NAR-01" if not act_vn.is_empty() else "RACE-01", act_vn)
	if not opening.is_empty():
		go("NAR-01", opening)
		return
	if not act_vn.is_empty():
		go("NAR-01", act_vn)
		return
	go("RACE-01", {})
