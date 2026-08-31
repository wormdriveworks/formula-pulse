# RUN-01 간이 정산 화면 (D09 §4.2 · 별첨A §A-9).
#
# **기능 상한 3종 고정** — 필드 정비 / 소모품 보충 / 덱 교체 (D07 §1.2 확정 상한).
# 그 외 어떤 메뉴 진입도 두지 않는다. 3기능은 전부 **화면 내 인라인 완결**이며 하위 화면이 없다 —
# 1분 리듬(D09 §0)의 이행 조건이다. 아무 조작 없이 [다음 대회로] 1버튼 통과가 가능해야 한다.
#
# **필드 정비의 다음 회차 체증 비용 사전 표시는 필수다** (D07 §3.3 이관 해소 · §A-9 E02) —
# "지금 정비할 것인가"라는 의사결정이 성립하려면 다음 비용이 보여야 한다.
extends FlowScreen

@onready var _repair_button: Button = %RepairButton
@onready var _repair_cost: Label = %RepairCostValue
@onready var _chassis_value: Label = %ChassisValue
@onready var _chassis_gauge: GhostGauge = %ChassisGauge
@onready var _consumable_title: Label = %ConsumableTitle
@onready var _consumable_list: HBoxContainer = %ConsumableList
@onready var _deck_title: Label = %DeckTitle
@onready var _deck_list: HBoxContainer = %DeckList
@onready var _next_button: Button = %NextButton


func _on_bound(_payload: Dictionary) -> void:
	var s := session.data.strings
	var result := session.last_gp_result
	(%HeaderLabel as Label).text = s.text("ui.recap.header")
	(%SummaryRank as Label).text = s.text("ui.recap.summaryFormat", {
		"rank": int(result.get("player_rank", 0)),
		"points": int(result.get("tour_points", 0)),
	})
	(%CreditsValue as Label).text = s.text("ui.recap.creditsFormat", {
		"amount": session.outgame.credits,
	})

	_repair_button.text = s.text("ui.recap.fieldRepair")
	_next_button.text = s.text("ui.recap.next")

	_refresh_repair_cost()
	_refresh_chassis()
	_next_button.pressed.connect(func(): go("RACE-01", {}))
	# 필드 정비 — 섀시 이월 결선(IMPL-078 해소)으로 실행 개방. 회복량·복원선·비용은 코어 소관.
	_repair_button.pressed.connect(_on_repair_pressed)
	_refresh_repair_button()
	_refresh_consumables()
	_refresh_deck()
	_next_button.grab_focus()  # 초기 포커스 = 주 버튼 (§A-9 E05)


# ── E03 소모품 보충 (§A-9 — 인라인 구매·COM-01 불요 확정: 저액·가역) ──
# 반입 상한·지불 판정은 전부 코어(buy_consumable)가 갖는다. 화면은 활성 표시만 맞춘다.
func _refresh_consumables() -> void:
	var s := session.data.strings
	var outgame := session.outgame
	var cap := session.data.param_int("param_consumable_carry_cap")
	var held := 0
	for id in outgame.consumables:
		held += int(outgame.consumables[id])
	_consumable_title.text = s.text("ui.recap.consumableHeaderFormat", {"held": held, "cap": cap})
	for child in _consumable_list.get_children():
		_consumable_list.remove_child(child)
		child.queue_free()
	for id in session.data.consumables:
		var row: Dictionary = session.data.consumables[id]
		var cost := CsvTable.to_int(String(row["cost_cr"]))
		var button := Button.new()
		# 재생성 후 포커스 복원의 주소 — 목록이 다시 서도 같은 품목은 같은 이름이다
		button.name = "Buy_" + String(id)
		button.add_theme_font_size_override("font_size", _body_font_size)
		var owned := int(outgame.consumables.get(id, 0))
		var label_key := "ui.recap.consumableBuyOwnedFormat" if owned > 0 else "ui.recap.consumableBuyFormat"
		button.text = s.text(label_key, {
			"item": s.text(String(row["name_key"])), "amount": cost, "held": owned,
		})
		button.disabled = held >= cap or outgame.credits < cost
		button.focus_mode = Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
		button.pressed.connect(_on_buy_consumable.bind(String(id)))
		_consumable_list.add_child(button)


func _on_buy_consumable(consumable_id: String) -> void:
	if not session.outgame.buy_consumable(consumable_id):
		return  # 상한·잔액 거부는 코어 판정 — 화면은 상태를 바꾸지 않는다
	sfx("purchase")   # SE-U07 구매 성사
	var s := session.data.strings
	(%CreditsValue as Label).text = s.text("ui.recap.creditsFormat", {
		"amount": session.outgame.credits,
	})
	_flash_credits()
	_refresh_consumables()
	_refresh_repair_button()  # 잔액이 줄면 정비 지불 능력도 바뀐다
	# 재생성이 포커스를 가진 버튼을 free 하므로 여기서 되잡는다 — 없으면 패드가
	# 이 화면에서 갇힌다(ui_focus_next 가 패드에 없다). 같은 품목 → 첫 가용 → 주 버튼 순.
	_restore_list_focus(_consumable_list, "Buy_" + consumable_id)


# 목록 재생성 후 포커스 복귀 창구 — 소모품·덱이 같은 형태를 쓴다.
# 이름이 같은 버튼이 살아 있고 포커스 가능하면 그 자리, 아니면 목록의 첫 가용 버튼,
# 그것도 없으면 주 버튼(다음 대회로)로 물러선다. 무포커스로 끝내지 않는다.
func _restore_list_focus(list: Control, preferred_name: String) -> void:
	var preferred := list.get_node_or_null(NodePath(preferred_name)) as Control
	if preferred != null and preferred.focus_mode != Control.FOCUS_NONE:
		preferred.grab_focus()
		return
	for child in list.get_children():
		var control := child as Control
		if control != null and control.focus_mode != Control.FOCUS_NONE:
			control.grab_focus()
			return
	_next_button.grab_focus()


# 결제 피드백 — 잔액 라벨 1회 점멸 (색을 만들지 않는다: 알파만 움직여 폰트색 불변)
func _flash_credits() -> void:
	var label := %CreditsValue as Label
	label.modulate = Color(1.0, 1.0, 1.0)
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 0.2, 0.08)
	tween.tween_property(label, "modulate:a", 1.0, 0.24)


# ── E04 덱 교체 (§A-9 — 인라인 요약 + 슬롯 교체, HUB-04 비전환) ──
# 중복·슬롯 초과 거부는 코어(set_deck)가 한다 — HUB-04 전략실과 같은 경로를 쓴다.
# **프리셋 전환(시설 G3)은 미결선** — 코어에 프리셋 상태·API가 없다 (impl_log 보고).
func _refresh_deck() -> void:
	var s := session.data.strings
	var outgame := session.outgame
	_deck_title.text = s.text("ui.recap.deckHeaderFormat", {
		"used": outgame.deck.size(), "slots": outgame.deck_slots,
	})
	for child in _deck_list.get_children():
		_deck_list.remove_child(child)
		child.queue_free()
	if outgame.unlocked_skills.is_empty():
		var empty := Label.new()
		empty.add_theme_font_size_override("font_size", _body_font_size)
		empty.text = s.text("ui.recap.deckNoSkill")
		_deck_list.add_child(empty)
		return
	for skill_id in outgame.unlocked_skills:
		var equipped := outgame.deck.has(skill_id)
		var mark := s.text("ui.recap.deckEquipped" if equipped else "ui.recap.deckUnequipped")
		var button := Button.new()
		# 재생성 후 포커스 복원의 주소 — 소모품 목록과 같은 규약
		button.name = "Deck_" + String(skill_id)
		button.add_theme_font_size_override("font_size", _body_font_size)
		button.text = s.text("ui.recap.deckEntryFormat", {
			"mark": mark, "skill": s.text(String(session.data.skills[skill_id]["name_key"])),
		})
		button.pressed.connect(_on_toggle_deck.bind(String(skill_id)))
		_deck_list.add_child(button)


func _on_toggle_deck(skill_id: String) -> void:
	var next_deck: Array = session.outgame.deck.duplicate()
	if next_deck.has(skill_id):
		next_deck.erase(skill_id)
	else:
		next_deck.append(skill_id)
	if session.outgame.set_deck(next_deck):
		_refresh_deck()
		# 재생성이 포커스를 free 한다 — 소모품 구매와 같은 결함 계열이라 같은 창구로 되잡는다
		_restore_list_focus(_deck_list, "Deck_" + skill_id)


func _on_repair_pressed() -> void:
	var cap := session.data.param_int("param_repair_field_cap")
	session.outgame.field_repair(cap)
	sfx("repair_execute")   # SE-U10 — 필드 정비도 전면 정비와 같은 정비 실행 축이다
	var s := session.data.strings
	var credits_text := s.text("ui.recap.creditsFormat", {"amount": session.outgame.credits})
	(%CreditsValue as Label).text = credits_text
	_flash_credits()
	_refresh_repair_cost()
	_refresh_chassis()
	_refresh_repair_button()


# 회복 여지(복원선 미만)와 지불 능력이 함께 성립할 때만 활성 — 판정은 코어 값으로만 한다
func _refresh_repair_button() -> void:
	var outgame := session.outgame
	var line := float(outgame.free_restore_line())
	var recoverable := outgame.chassis < line
	var affordable := outgame.credits >= outgame.field_repair_cost()
	var had_focus := _repair_button.has_focus()
	_repair_button.disabled = not (recoverable and affordable)
	_repair_button.focus_mode = Control.FOCUS_NONE if _repair_button.disabled else Control.FOCUS_ALL
	# 포커스를 가진 채 FOCUS_NONE 이 되면 포커스가 허공에 떨어진다(구매 재생성과 같은 계열) —
	# 잃는 쪽이 스스로 주 버튼에 넘긴다
	if had_focus and _repair_button.focus_mode == Control.FOCUS_NONE:
		_next_button.grab_focus()


# 이번 비용 → 다음 회차 비용 병기 (D07 §3.3 필수 규격). 체증 계산은 코어가 한다.
func _refresh_repair_cost() -> void:
	var s := session.data.strings
	var cost_text := s.text("ui.recap.repairCostFormat", {
		"now": session.outgame.field_repair_cost(),
		"next": session.outgame.field_repair_cost_next(),
	})
	_repair_cost.text = cost_text


# §A-9 E02 회복 고스트 게이지 — 현재 → 실행 시 도달값. 도달 계산은 코어 프리뷰 전속이며
# 지불 능력과 무관하게 "하면 어디까지 가는가"를 보인다 (활성 여부는 버튼이 답한다).
# [가안] 백분율 분모 = 섀시 최대치 — D09 문면("62%")이 분모를 규정하지 않아 게이지 비율과 일치시켰다
func _refresh_chassis() -> void:
	var s := session.data.strings
	var outgame := session.outgame
	var maximum := session.data.param("param_chassis_max")
	var cap := session.data.param_int("param_repair_field_cap")
	var after := outgame.field_repair_preview(cap)
	var now_pct := int(round(outgame.chassis / maximum * 100.0))
	var after_pct := int(round(after / maximum * 100.0))
	var chassis_text := s.text("ui.recap.chassisNowFormat", {"now": now_pct})
	if after_pct > now_pct:
		chassis_text = s.text("ui.recap.chassisFormat", {"now": now_pct, "after": after_pct})
	_chassis_value.text = chassis_text
	_chassis_gauge.set_values(outgame.chassis, after, maximum)
