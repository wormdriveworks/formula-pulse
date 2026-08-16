# HUB-06 스폰서 데스크 — D09 §4.6 · 별첨A §A-16.
#
# 나디아 합류로 개방된다(개러지 앵커가 막으므로 이 화면 도달 = 개방 상태).
# 계약 카드(조건·기간·수입) + 보유 슬롯 표기(기본 1 → G4로 2). 체결 = COM-01.
# 갱신 가능 시점(투어 결산 연동)은 스폰서 정산 층 결선 후 — 골격은 체결·열람까지.
extends HubScreen


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


func _card(sponsor_id: String) -> Control:
	var s := session.data.strings
	var sponsor_row: Dictionary = session.data.sponsors[sponsor_id]
	var row := HBoxContainer.new()
	row.name = sponsor_id.to_pascal_case()
	row.add_theme_constant_override("separation", 8)

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
	_refresh_sign(sponsor_id, sign)
	return row


func _refresh_sign(sponsor_id: String, sign: Button) -> void:
	var s := session.data.strings
	for connection in sign.pressed.get_connections():
		sign.pressed.disconnect(connection["callable"])
	if session.outgame.sponsor_contracts.has(sponsor_id):
		sign.text = s.text("ui.sponsorDesk.signed")
		sign.disabled = true
		return
	sign.text = s.text("ui.sponsorDesk.sign")
	sign.disabled = session.outgame.sponsor_contracts.size() >= session.outgame.sponsor_slots()
	sign.pressed.connect(_on_sign.bind(sponsor_id, sign))


func _on_sign(sponsor_id: String, sign: Button) -> void:
	var s := session.data.strings
	var sponsor_name := s.text(String(session.data.sponsors[sponsor_id]["name_key"]))
	var summary := s.text("ui.sponsorDesk.signConfirm", {"sponsor": sponsor_name})
	# 계약 체결 = 기간 구속이 걸리는 비가역 행동 → COM-01 (D09 §4.6 "체결·갱신 = COM-01")
	var dialog := ConfirmDialog.ask(self, s, summary, "", true, _body_font_size)
	dialog.resolved.connect(func(accepted: bool):
		if not accepted:
			return
		if session.outgame.sign_sponsor(sponsor_id):
			_refresh_sign(sponsor_id, sign)
			_refresh_slots())
