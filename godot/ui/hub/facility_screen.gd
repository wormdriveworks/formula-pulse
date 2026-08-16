# HUB-07 시설 확장 패널 — D09 §4.6 · 별첨A §A-17.
#
# G1~G4 카드: 효과 · 비용(주행 데이터 — **아이콘 동반**, B-1) · 구매 상태.
# 구매 = **비가역 COM-01**. G4는 나디아 합류 전 잠금.
extends HubScreen


func _on_hub_ready(_payload: Dictionary) -> void:
	var s := session.data.strings
	(%HeaderLabel as Label).text = s.text("ui.facilityPanel.title")
	var list := %CardList as VBoxContainer
	for facility_id in session.data.facilities:
		list.add_child(_card(String(facility_id)))
	(%BackButton as Button).grab_focus()


func _card(facility_id: String) -> Control:
	var s := session.data.strings
	var facility_row: Dictionary = session.data.facilities[facility_id]
	var row := HBoxContainer.new()
	row.name = facility_id.to_pascal_case()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", _body_font_size)
	name_label.custom_minimum_size = Vector2(130, 0)
	name_label.text = s.text(String(facility_row["name_key"]))
	row.add_child(name_label)

	# 비용 — 주행 데이터 아이콘 동반 (B-1 절대 규격)
	var icon := TextureRect.new()
	icon.texture = load(ICON_DIR + "currency_data.png")
	icon.custom_minimum_size = Vector2(14, 14)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(icon)
	var cost_label := Label.new()
	cost_label.add_theme_font_size_override("font_size", _body_font_size)
	var cost_text := s.text("ui.hub.amountFormat", {
		"amount": CsvTable.to_int(String(facility_row["cost_dp"])),
	})
	cost_label.text = cost_text
	cost_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	row.add_child(cost_label)

	var buy := Button.new()
	buy.add_theme_font_size_override("font_size", _body_font_size)
	buy.name = "Buy"
	row.add_child(buy)
	_refresh_buy(facility_id, buy)
	return row


func _refresh_buy(facility_id: String, buy: Button) -> void:
	var s := session.data.strings
	var facility_row: Dictionary = session.data.facilities[facility_id]
	for connection in buy.pressed.get_connections():
		buy.pressed.disconnect(connection["callable"])
	if session.outgame.facilities.has(facility_id):
		buy.text = s.text("ui.facilityPanel.owned")
		buy.disabled = true
		return
	var required_crew := String(facility_row.get("requires_crew", ""))
	if not required_crew.is_empty() and not session.outgame.crew.has(required_crew):
		var crew_name := s.text(String(session.data.crew[required_crew]["name_key"]))
		var locked_text := s.text("ui.hub.lockedByCrew", {"crew": crew_name})
		buy.text = locked_text
		buy.disabled = true
		buy.focus_mode = Control.FOCUS_NONE
		return
	buy.text = s.text("ui.facilityPanel.buy")
	buy.disabled = session.outgame.drive_data < CsvTable.to_int(String(facility_row["cost_dp"]))
	buy.pressed.connect(_on_buy.bind(facility_id, buy))


func _on_buy(facility_id: String, buy: Button) -> void:
	var s := session.data.strings
	var facility_name := s.text(String(session.data.facilities[facility_id]["name_key"]))
	var summary := s.text("ui.facilityPanel.buyConfirm", {"facility": facility_name})
	var cost_text := s.text("ui.hub.amountFormat", {
		"amount": CsvTable.to_int(String(session.data.facilities[facility_id]["cost_dp"])),
	})
	var dialog := ConfirmDialog.ask(self, s, summary, cost_text, true, _body_font_size)
	dialog.resolved.connect(func(accepted: bool):
		if not accepted:
			return
		if session.outgame.unlock_facility(facility_id):
			_refresh_buy(facility_id, buy)
			refresh_currency())
