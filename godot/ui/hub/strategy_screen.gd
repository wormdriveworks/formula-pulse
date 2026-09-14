# HUB-04 전략실 — D09 §4.4 · 별첨A §A-14.
#
# 좌 = 보유 스킬 목록(**스킬 티어**별 그룹) / 우 = 덱 슬롯 열(2→5, 미확장 잠금+확장 비용).
# **T-1 (부대조건):** 전 라벨 '스킬 티어' 완칭 고정 — '티어' 단독 표기 절대 금지.
#
# 스킬 카드 = 명칭 · ◆비용 · 횟수 제한 — D07 §4.2 데이터의 직접 표시, 신규 정보 창작 없음.
# 해금 구매 = **COM-01 비가역** (D09 §1.4). 장착 = 선택→슬롯 (골격: 클릭 토글).
extends HubScreen

var _tier_boxes: Dictionary = {}
# 스킬 행 대장 — DP 소비(해금·확장) 시 **전 행**의 지불 가능성을 갱신하기 위한 참조
# (개선 2026-09-02 — 튜닝 H3 와 같은 스테일 계열)
var _skill_rows: Dictionary = {}


# G3 세컨드 워크벤치 — 전략실 **상단의 프리셋 A/B 전환** (개선 회차 20 · D07 §2.2·§4.1,
# D09 §4.4 / 별첨A §A-14 "상단: 프리셋 A/B 전환(시설 G3 개방 시)").
# 전환은 화면을 갈아타지 않고 그 자리에서 목록을 다시 그린다(§A-14 "HUB-04 비전환").
func _build_preset_row() -> void:
	if not session.outgame.facility_effect_open("deck_preset_slot"):
		return
	var s := session.data.strings
	var row := HBoxContainer.new()
	row.name = "PresetRow"
	row.add_theme_constant_override("separation", 8)
	for index in range(session.outgame.deck_preset_count()):
		var button := Button.new()
		button.name = "Preset%d" % index
		button.add_theme_font_size_override("font_size", _body_font_size)
		button.text = s.text("ui.strategy.presetA" if index == 0 else "ui.strategy.presetB")
		button.set_meta(AUDIO_EVENT_META, "ui_tab")
		# 활성 칸은 **색으로** 표시한다 — 소등하면 선택이 아니라 잠긴 것으로 읽힌다.
		# 기록실 탭과 같은 방식이고, 같은 칸을 다시 눌러도 코어가 조용히 거부한다.
		if index == session.outgame.active_deck_preset:
			button.add_theme_color_override("font_color", UiPalette.TIMER_LEEWAY)
		button.pressed.connect(_on_preset.bind(index))
		row.add_child(button)
	var header := %HeaderLabel as Control
	header.get_parent().add_child(row)
	header.get_parent().move_child(row, header.get_index() + 1)


func _on_preset(index: int) -> void:
	if not session.outgame.switch_deck_preset(index):
		return
	# 목록·덱 표기가 통째로 갈리므로 화면을 다시 세운다 — 행마다 갱신하면 상태가 둘로 갈린다.
	_rebuild()
	sfx("ui_tab")


# 전환 후 재구성 — **즉시 떼어내고** 다시 짓는다. `queue_free()` 만으로는 이번 프레임에 남아 있어
# 같은 행이 두 벌 서는 자리가 생긴다.
func _rebuild() -> void:
	for container in [get_node_or_null("%SkillList"), _preset_row_parent()]:
		if container == null:
			continue
		for child in container.get_children():
			if child.name == "PresetRow" or container.name == "SkillList":
				container.remove_child(child)
				child.queue_free()
	_build_preset_row()
	_build_skill_list()
	_refresh_deck()
	var focus_target := get_node_or_null("%DeckExpandButton")
	if focus_target == null or not (focus_target as Button).visible:
		focus_target = %BackButton
	(focus_target as Control).grab_focus()


func _preset_row_parent() -> Node:
	return (%HeaderLabel as Control).get_parent()


func _on_hub_ready(_payload: Dictionary) -> void:
	var s := session.data.strings
	(%HeaderLabel as Label).text = s.text("ui.strategy.title")
	_build_preset_row()
	_build_skill_list()
	_refresh_deck()
	(%BackButton as Button).grab_focus()


func _build_skill_list() -> void:
	var s := session.data.strings
	var list := %SkillList as VBoxContainer
	# 스킬 티어별 그룹 (1~3) — 티어 개방 상태 표기 (마일스톤 연동)
	for tier in range(1, 4):
		var header := Label.new()
		header.add_theme_font_size_override("font_size", _head_font_size)
		header.name = "TierHeader%d" % tier
		# '스킬 티어' 완칭 (T-1) — 부분 문자열 치환 금지 대상이므로 키 단위로 발행돼 있다
		var tier_text := s.text("ui.strategy.tierFormat", {"tier": tier})
		if not session.outgame.skill_tier_open(tier):
			# 개방 조건 병기 (§A-14) — 조건 문면 정본 = D07 §4.3 (티어 2 '첫 포디움' ·
			# 티어 3 '첫 그랑프리 우승'). 판정 자체는 코어 skill_tier_open 전속이며 여기는 표기만.
			var condition_key := "ui.strategy.openFirstPodium" if tier == 2 \
				else "ui.strategy.openFirstGpWin"
			var condition_text := s.text(condition_key)
			tier_text = s.text("ui.strategy.tierLockedFormat", {
				"tier": tier, "condition": condition_text})
		header.text = tier_text
		header.add_theme_color_override("font_color", UiPalette.TIMER_LEEWAY)
		list.add_child(header)
		var box := VBoxContainer.new()
		box.name = "TierBox%d" % tier
		box.add_theme_constant_override("separation", 2)
		list.add_child(box)
		_tier_boxes[tier] = box
	for skill_id in session.data.skills:
		var row := _skill_row(String(skill_id))
		_skill_rows[String(skill_id)] = row
		var tier := CsvTable.to_int(String(session.data.skills[skill_id]["skill_tier"]))
		(_tier_boxes.get(tier, _tier_boxes[1]) as VBoxContainer).add_child(row)


func _skill_row(skill_id: String) -> Control:
	var s := session.data.strings
	var row := HBoxContainer.new()
	row.name = skill_id.to_pascal_case()
	row.add_theme_constant_override("separation", 6)
	var skill_row: Dictionary = session.data.skills[skill_id]

	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", _body_font_size)
	name_label.custom_minimum_size = Vector2(110, 0)
	name_label.text = s.text(String(skill_row["name_key"]))
	row.add_child(name_label)

	var cost := Label.new()
	cost.add_theme_font_size_override("font_size", _body_font_size)
	var cost_text := s.text("ui.race.costFormat", {"cost": CsvTable.to_int(String(skill_row["charge_cost"]))})
	cost.text = cost_text
	cost.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	row.add_child(cost)

	var action := Button.new()
	action.add_theme_font_size_override("font_size", _body_font_size)
	action.name = "Action"
	row.add_child(action)
	_refresh_skill_row(skill_id, row)
	return row


func _refresh_skill_row(skill_id: String, row: Control) -> void:
	var s := session.data.strings
	var action := row.get_node("Action") as Button
	var skill_row: Dictionary = session.data.skills[skill_id]
	var tier := CsvTable.to_int(String(skill_row["skill_tier"]))
	for connection in action.pressed.get_connections():
		action.pressed.disconnect(connection["callable"])
	if session.outgame.unlocked_skills.has(skill_id):
		var equipped: bool = session.outgame.deck.has(skill_id)
		action.text = s.text("ui.strategy.unequip" if equipped else "ui.strategy.equip")
		action.disabled = false
		action.pressed.connect(_on_toggle_equip.bind(skill_id, row))
	elif not session.outgame.skill_tier_open(tier):
		action.text = s.text("ui.race.locked")
		action.disabled = true
		action.focus_mode = Control.FOCUS_NONE
	else:
		var unlock_dp := session.outgame.unlock_cost(CsvTable.to_int(String(skill_row["unlock_dp"])))
		var unlock_text := s.text("ui.strategy.unlockFormat", {"amount": unlock_dp})
		action.text = unlock_text
		action.disabled = session.outgame.drive_data < unlock_dp
		action.pressed.connect(_on_unlock.bind(skill_id, row))


func _on_unlock(skill_id: String, row: Control) -> void:
	var s := session.data.strings
	var skill_name := s.text(String(session.data.skills[skill_id]["name_key"]))
	var unlock_dp := session.outgame.unlock_cost(CsvTable.to_int(String(session.data.skills[skill_id]["unlock_dp"])))
	var summary := s.text("ui.strategy.unlockConfirm", {"skill": skill_name})
	var cost_text := s.text("ui.strategy.unlockFormat", {"amount": unlock_dp})
	# 스킬 해금 = 비가역 (D09 §1.4 명시 예) → COM-01
	var dialog := ConfirmDialog.ask(self, s, summary, cost_text, true, _body_font_size)
	dialog.resolved.connect(func(accepted: bool):
		if not accepted:
			return
		if session.outgame.unlock_skill(skill_id):
			sfx("skill_unlock")   # SE-U12 스킬 해금
			_refresh_all_rows()   # DP 소비 — 타 행 해금 버튼의 지불 가능성이 함께 낡는다 (H3 계열)
			refresh_currency())


func _on_toggle_equip(skill_id: String, row: Control) -> void:
	var next_deck: Array = session.outgame.deck.duplicate()
	if next_deck.has(skill_id):
		next_deck.erase(skill_id)
	else:
		next_deck.append(skill_id)
	# 중복·슬롯 초과는 코어가 거부한다 — 화면은 결과만 반영 (즉시 피드백)
	if session.outgame.set_deck(next_deck):
		_refresh_skill_row(skill_id, row)
		_refresh_deck()


func _refresh_deck() -> void:
	var s := session.data.strings
	var deck_box := %DeckList as VBoxContainer
	for child in deck_box.get_children():
		deck_box.remove_child(child)
		child.queue_free()
	(%DeckHeader as Label).text = s.text("ui.strategy.deckHeaderFormat", {
		"used": session.outgame.deck.size(), "slots": session.outgame.deck_slots,
	})
	for skill_id in session.outgame.deck:
		var entry := Label.new()
		entry.add_theme_font_size_override("font_size", _body_font_size)
		entry.text = s.text(String(session.data.skills[skill_id]["name_key"]))
		deck_box.add_child(entry)
	var expand := %ExpandButton as Button
	var max_slots := int(session.data.param("param_deck_slots_max"))
	if session.outgame.deck_slots >= max_slots:
		expand.visible = false
		return
	# 확장 비용 인덱스 산식은 코어(expand_deck)와 동일하게 둔다
	var expand_index := session.outgame.deck_slots - int(session.data.param("param_deck_slots_start")) + 1
	var expand_cost := session.outgame.unlock_cost(int(session.data.param("param_deck_expand_dp%d" % expand_index)))
	var expand_text := s.text("ui.strategy.expandFormat", {"amount": expand_cost})
	expand.text = expand_text
	expand.disabled = session.outgame.drive_data < expand_cost
	if not expand.pressed.is_connected(_on_expand):
		expand.pressed.connect(_on_expand)


func _on_expand() -> void:
	if session.outgame.expand_deck():
		_refresh_deck()
		_refresh_all_rows()   # DP 소비 — 해금 버튼 지불 가능성 갱신 (H3 계열)
		refresh_currency()


func _refresh_all_rows() -> void:
	for skill_id in _skill_rows:
		_refresh_skill_row(String(skill_id), _skill_rows[skill_id] as Control)
