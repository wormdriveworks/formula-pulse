# HUB-06 스폰서 데스크 — D09 §4.6 · 별첨A §A-16.
#
# 나디아 합류로 개방된다(개러지 앵커가 막으므로 이 화면 도달 = 개방 상태).
# 계약 카드(수입 · 조건 · 이번 투어 진행) + 보유 슬롯 표기(기본 1 → G4로 2). 체결·해지 = COM-01.
#
# **결선 (개선 회차 13 · 2026-09-09 사용자 결정):** 정산은 투어 결산(SET-01)에서 세션이 한다 — 정기 수입 + 조건
# 보너스(`RunSession.settle_tour` → `OutgameState.settle_sponsors_for_tour`). 체결·해지(교체)는 **투어 첫 출발 전
# 개러지 방문**에만 열린다(`session.sponsor_renewal_open()` — D07 §5.4 "투어 단위 계약 · 결산 시 갱신·교체 · 중도
# 파기 없음" · §A-16 "갱신 시점 외 열람 전용"). 개러지가 GP 마다 서므로(회차 10) 투어 중 방문은 열람 전용이고
# 카드가 이번 투어의 조건 진행을 보인다 — 조건이 유리해진 뒤 갈아타는 리틀 사고를 시점으로 봉쇄한다.
# 해지하지 않은 계약은 다음 투어로 이어진다(자동 갱신). 후보 3/4종 제시(D07 §5.4)는 두지 않는다 — 데스크는 나디아
# 합류로만 열리고 그때 후보는 4종 전부다(나디아 패시브 = 4종).
extends HubScreen

# 조건 id(sponsors.csv `condition`) → 조건 문면 키. 표의 id 는 규칙 식별자이고 문면은 스트링 표에 있다(D12 §8.1).
const CONDITION_KEYS := {
	"tour_all_finish": "ui.sponsorCondition.tourAllFinish",
	"race_top3": "ui.sponsorCondition.raceTop3",
	"beat_named_rival": "ui.sponsorCondition.beatNamedRival",
	"tour_top5": "ui.sponsorCondition.tourTop5",
}

# 체결/해지 버튼 대장 — 상태 변화 시 **전 카드**를 갱신하기 위한 참조 (개선 2026-09-02 H4)
var _signs: Dictionary = {}
# 조건 진행 라벨 대장 — 카드 재구축 없이 문면만 갱신
var _conditions: Dictionary = {}


func _on_hub_ready(_payload: Dictionary) -> void:
	var s := session.data.strings
	(%HeaderLabel as Label).text = s.text("ui.sponsorDesk.title")
	_refresh_slots()
	var list := %CardList as VBoxContainer
	for sponsor_id in session.data.sponsors:
		list.add_child(_card(String(sponsor_id)))
	(%BackButton as Button).grab_focus()


func _refresh_slots() -> void:
	var s := session.data.strings
	var slots_text := s.text("ui.sponsorDesk.slotFormat", {
		"used": session.outgame.sponsor_contracts.size(),
		"slots": session.outgame.sponsor_slots(),
	})
	(%SlotLabel as Label).text = slots_text
	(%WindowNote as Label).text = s.text(
		"ui.sponsorDesk.windowOpen" if session.sponsor_renewal_open() else "ui.sponsorDesk.windowClosed")


func _card(sponsor_id: String) -> Control:
	var s := session.data.strings
	var sponsor_row: Dictionary = session.data.sponsors[sponsor_id]
	var card := VBoxContainer.new()
	card.name = sponsor_id.to_pascal_case()
	card.add_theme_constant_override("separation", 1)
	var row := HBoxContainer.new()
	row.name = "Head"
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", _body_font_size)
	name_label.custom_minimum_size = Vector2(110, 0)
	name_label.text = s.text(String(sponsor_row["name_key"]))
	row.add_child(name_label)

	var income := Label.new()
	income.add_theme_font_size_override("font_size", _body_font_size)
	var income_text := s.text("ui.sponsorDesk.incomeFormat", {
		"regular": CsvTable.to_int(String(sponsor_row["regular_cr"])),
		"bonus": CsvTable.to_int(String(sponsor_row["bonus_cr"])),
	})
	income.text = income_text
	income.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	row.add_child(income)

	var sign := Button.new()
	sign.add_theme_font_size_override("font_size", _body_font_size)
	sign.name = "Sign"
	row.add_child(sign)
	_signs[sponsor_id] = sign
	_refresh_sign(sponsor_id, sign)

	# 조건 + 이번 투어 진행 — 종전 카드에는 조건 문면이 없어 무엇을 하면 보너스가 붙는지 알 길이 없었다.
	var condition := Label.new()
	condition.name = "Condition"
	condition.add_theme_font_size_override("font_size", _body_font_size)
	condition.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	card.add_child(condition)
	_conditions[sponsor_id] = condition
	_refresh_condition(sponsor_id, condition)
	return card


# 조건 문면 + 진행: 횟수형(SP2)은 이번 투어 P3 이내 횟수, 사건형(SP3)은 달성/미달성, 결산형(SP1·SP4)은 결산 시 판정.
func _refresh_condition(sponsor_id: String, label: Label) -> void:
	var s := session.data.strings
	var condition := String(session.data.sponsors[sponsor_id]["condition"])
	# 값의 형이 곧 조건의 종류다 — int(횟수형) · bool(사건형) · null(결산형) — 코어 `sponsor_condition_value` 와 같은 소재.
	var value: Variant = session.outgame.sponsor_condition_value(sponsor_id)
	var progress: String
	match typeof(value):
		TYPE_INT:
			progress = s.text("ui.sponsorDesk.progressCountFormat", {"count": int(value)})
		TYPE_BOOL:
			progress = s.text("ui.sponsorDesk.progressDone" if bool(value) else "ui.sponsorDesk.progressPending")
		_:
			progress = s.text("ui.sponsorDesk.progressAtSettle")
	var condition_text := s.text("ui.sponsorDesk.conditionFormat", {
		"condition": s.text(String(CONDITION_KEYS.get(condition, ""))), "progress": progress,
	})
	label.text = condition_text


# 버튼 상태 = (계약 중인가) × (창이 열렸는가). 열린 창: 계약 중 → [해지] · 미계약 → [체결](슬롯 여유 시).
# 닫힌 창: 계약 중 → [계약 중] 소등 · 미계약 → [체결] 소등. 소등된 버튼은 포커스를 받지 않는다(패드 갇힘 방지).
func _refresh_sign(sponsor_id: String, sign: Button) -> void:
	var s := session.data.strings
	for connection in sign.pressed.get_connections():
		sign.pressed.disconnect(connection["callable"])
	var had_focus := sign.has_focus()
	var open := session.sponsor_renewal_open()
	var outgame := session.outgame
	if outgame.sponsor_contracts.has(sponsor_id):
		if open:
			sign.text = s.text("ui.sponsorDesk.release")
			sign.disabled = false
			sign.pressed.connect(_on_release.bind(sponsor_id))
		else:
			sign.text = s.text("ui.sponsorDesk.signed")
			sign.disabled = true
	else:
		sign.text = s.text("ui.sponsorDesk.sign")
		sign.disabled = (not open) or outgame.sponsor_contracts.size() >= outgame.sponsor_slots()
		if not sign.disabled:
			sign.pressed.connect(_on_sign.bind(sponsor_id))
	sign.focus_mode = Control.FOCUS_NONE if sign.disabled else Control.FOCUS_ALL
	if had_focus and sign.disabled:
		(%BackButton as Button).grab_focus()


func _refresh_all() -> void:
	for other_id in _signs:
		_refresh_sign(String(other_id), _signs[other_id] as Button)
	for other_id in _conditions:
		_refresh_condition(String(other_id), _conditions[other_id] as Label)
	_refresh_slots()


func _on_sign(sponsor_id: String) -> void:
	var s := session.data.strings
	var sponsor_name := s.text(String(session.data.sponsors[sponsor_id]["name_key"]))
	var summary := s.text("ui.sponsorDesk.signConfirm", {"sponsor": sponsor_name})
	# 계약 체결 = 기간 구속이 걸리는 비가역 행동 → COM-01 (D09 §4.6 "체결·갱신 = COM-01")
	var dialog := ConfirmDialog.ask(self, s, summary, "", true, _body_font_size)
	dialog.resolved.connect(func(accepted: bool):
		if not accepted:
			return
		# 스폰서 체결에 대응하는 행이 `sound_map` 에 없다 — 확정 다이얼로그의 일반 결정음이
		# 전부다. 표에 없는 행동은 울리지 않는 것이 정상이며, 임의로 다른 SFX 를 빌려 쓰지 않는다.
		if session.outgame.sign_sponsor(sponsor_id):
			# **전 카드 갱신** (개선 2026-09-02 H4) — 자기 카드만 갱신하면 슬롯이 소진된 뒤에도
			# 타 카드 체결 버튼이 산 채로 남아, 확인 창까지 띄우고 확정해도 무반응이 된다.
			_refresh_all())


# 해지 = 교체의 전반. 창이 열린 때에만 버튼이 살아 있으므로 여기 도달 = 창 열림. 되돌릴 수 있는 결정
# (같은 방문에서 다시 체결 가능)이라 경고행 없는 COM-01 이다.
func _on_release(sponsor_id: String) -> void:
	var s := session.data.strings
	var sponsor_name := s.text(String(session.data.sponsors[sponsor_id]["name_key"]))
	var summary := s.text("ui.sponsorDesk.releaseConfirm", {"sponsor": sponsor_name})
	var dialog := ConfirmDialog.ask(self, s, summary, "", false, _body_font_size)
	dialog.resolved.connect(func(accepted: bool):
		if not accepted:
			return
		if session.outgame.release_sponsor(sponsor_id):
			_refresh_all())
