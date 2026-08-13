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


func _on_depart() -> void:
	# 투어 경계 저장 지점 (D09 §2.4 — SET-01 ⑧ 개러지 귀환 후 출발 전 최신화)
	session.save_progress()
	go("RACE-01", {})
