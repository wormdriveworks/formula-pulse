# HUB-02 정비 베이 — D09 §4.3 · 별첨A §A-12.
#
# 전면 정비 카드: 비용 · 완전 회복 고스트 게이지 · 실행. 테오 스탠딩 상주(아트 유입 대상).
# 무상 복원선(투어 개시 70)은 자동 처리 고지행으로만 표기한다 (§A-12 확정).
# 실행은 섀시 이월 결선(IMPL-078 해소)으로 개방 — 비용·회복량 판정은 전부 코어 소관.
#
# **소모품 보충 서브 카드** (§A-12 규격 — 개선 회차 10 · 2026-09-08 결선). 종전에는 간이 정산 화면이 게임의
# 유일한 구매 지점이었고 이 화면에는 규격만 있었다. 플로우가 레이스 ↔ 개러지 반복으로 바뀌며 간이 정산 화면이
# 사라졌으므로(사용자 결정) 구매 지점을 여기로 옮긴다 — 인라인 구매(COM-01 불요 · 저액·가역, 결정 #8), 반입
# 상한·지불 판정은 전부 코어(`buy_consumable`). 필드 정비는 같은 결정으로 폐지됐다 — 이 화면의 정비는 전면 정비
# 한 경로다.
extends HubScreen

@onready var _consumable_title: Label = %ConsumableTitle
@onready var _consumable_list: HBoxContainer = %ConsumableList


func _on_hub_ready(_payload: Dictionary) -> void:
	var s := session.data.strings
	(%HeaderLabel as Label).text = s.text("ui.repairBay.title")
	(%CardLabel as Label).text = s.text("ui.repairBay.fullRepair")
	var per_ch := int(session.data.param("param_repair_full_cr_per_ch"))
	var cost_text := s.text("ui.repairBay.perChFormat", {"amount": per_ch})
	(%CostLabel as Label).text = cost_text
	var line := int(session.data.param("param_repair_free_restore_line"))
	var line_text := s.text("ui.repairBay.freeLineNote", {"line": line})
	(%FreeLineNote as Label).text = line_text
	var run := %RunButton as Button
	run.text = s.text("ui.repairBay.run")
	run.pressed.connect(_on_run_pressed)
	_refresh_repair_card()
	_refresh_run_button()
	_refresh_consumables()
	(%BackButton as Button).grab_focus()


func _on_run_pressed() -> void:
	session.outgame.full_repair()
	sfx("repair_execute")
	refresh_currency()
	_refresh_repair_card()
	_refresh_run_button()
	_refresh_consumables()   # 잔액이 줄면 소모품 지불 능력도 바뀐다


# §A-12 전면 정비 카드 — 총비용 + 완전 회복 고스트 게이지 (현재 → 최대치).
# 총비용·최대치는 코어 조회 전속 (full_repair_cost — IMPL-079 구조의 표시 전용 경로).
# [가안] 백분율 분모 = 섀시 최대치 (종전 간이 정산 E02 와 동일 판단)
func _refresh_repair_card() -> void:
	var s := session.data.strings
	var outgame := session.outgame
	var maximum := session.data.param("param_chassis_max")
	var total_text := s.text("ui.repairBay.totalCostFormat", {"amount": outgame.full_repair_cost()})
	(%TotalCostValue as Label).text = total_text
	var now_pct := int(round(outgame.chassis / maximum * 100.0))
	var chassis_text := s.text("ui.repairBay.chassisNowFormat", {"now": now_pct})
	if now_pct < 100:
		chassis_text = s.text("ui.repairBay.chassisFormat", {"now": now_pct, "after": 100})
	(%ChassisValue as Label).text = chassis_text
	(%ChassisGauge as GhostGauge).set_values(outgame.chassis, maximum, maximum)


# 손상(최대치 미만)과 지불 능력이 함께 성립할 때만 활성 — 이미 만충이면 소등
func _refresh_run_button() -> void:
	var outgame := session.outgame
	var damaged := outgame.chassis < session.data.param("param_chassis_max")
	var affordable := outgame.credits >= outgame.full_repair_cost()
	var run := %RunButton as Button
	var had_focus := run.has_focus()
	run.disabled = not (damaged and affordable)
	run.focus_mode = Control.FOCUS_NONE if run.disabled else Control.FOCUS_ALL
	# 포커스를 가진 채 FOCUS_NONE 이 되면 포커스가 허공에 떨어진다 (개선 2026-09-02 H1 —
	# 실기: 정비 실행 직후 방향키·Esc 전부 무반응, 패드는 복구 수단이 없다).
	# 잃는 쪽이 스스로 뒤로가기에 넘긴다.
	if had_focus and run.focus_mode == Control.FOCUS_NONE:
		(%BackButton as Button).grab_focus()


# ── 소모품 보충 서브 카드 (§A-12 — 종전 §A-9 E03 이식 · 인라인 구매) ──
# 반입 상한·지불 판정은 전부 코어(buy_consumable)가 갖는다. 화면은 활성 표시만 맞춘다.
# 코드 생성 버튼이라 폰트 크기를 명시한다(엔진 기본 16 함정 — IMPL-125 계열 · FONT 규약).
func _refresh_consumables() -> void:
	var s := session.data.strings
	var outgame := session.outgame
	var cap := session.data.param_int("param_consumable_carry_cap")
	var held := 0
	for id in outgame.consumables:
		held += int(outgame.consumables[id])
	_consumable_title.text = s.text("ui.repairBay.consumableHeaderFormat", {"held": held, "cap": cap})
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
		var label_key := "ui.repairBay.consumableBuyOwnedFormat" if owned > 0 \
			else "ui.repairBay.consumableBuyFormat"
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
	refresh_currency()
	_refresh_consumables()
	_refresh_run_button()  # 잔액이 줄면 전면 정비 지불 능력도 바뀐다
	# 재생성이 포커스를 가진 버튼을 free 하므로 여기서 되잡는다 — 없으면 패드가 이 화면에서
	# 갇힌다(ui_focus_next 가 패드에 없다). 같은 품목 → 첫 가용 품목 → 뒤로가기 순.
	_restore_list_focus("Buy_" + consumable_id)


# 목록 재생성 후 포커스 복귀 창구 — 이름이 같은 버튼이 살아 있고 포커스 가능하면 그 자리, 아니면
# 목록의 첫 가용 버튼, 그것도 없으면 뒤로가기로 물러선다. 무포커스로 끝내지 않는다.
func _restore_list_focus(preferred_name: String) -> void:
	var preferred := _consumable_list.get_node_or_null(NodePath(preferred_name)) as Control
	if preferred != null and preferred.focus_mode != Control.FOCUS_NONE:
		preferred.grab_focus()
		return
	for child in _consumable_list.get_children():
		var control := child as Control
		if control != null and control.focus_mode != Control.FOCUS_NONE:
			control.grab_focus()
			return
	(%BackButton as Button).grab_focus()
