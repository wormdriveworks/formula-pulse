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
@onready var _consumable_button: Button = %ConsumableButton
@onready var _deck_button: Button = %DeckButton
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
	_consumable_button.text = s.text("ui.recap.consumable")
	_deck_button.text = s.text("ui.recap.deck")
	_next_button.text = s.text("ui.recap.next")

	_refresh_repair_cost()
	_next_button.pressed.connect(func(): go("RACE-01", {}))
	# 필드 정비 — 섀시 이월 결선(IMPL-078 해소)으로 실행 개방. 회복량·복원선·비용은 코어 소관.
	_repair_button.pressed.connect(_on_repair_pressed)
	_refresh_repair_button()
	# 덱·소모품은 소비 경로 결선 전 잠금 유지 — 선택 UI(씬)가 필요해 주력 레인 몫이다.
	for locked in [_consumable_button, _deck_button]:
		locked.disabled = true
		locked.focus_mode = Control.FOCUS_NONE
	_next_button.grab_focus()  # 초기 포커스 = 주 버튼 (§A-9 E05)


func _on_repair_pressed() -> void:
	var cap := session.data.param_int("param_repair_field_cap")
	session.outgame.field_repair(cap)
	var s := session.data.strings
	var credits_text := s.text("ui.recap.creditsFormat", {"amount": session.outgame.credits})
	(%CreditsValue as Label).text = credits_text
	_refresh_repair_cost()
	_refresh_repair_button()


# 회복 여지(복원선 미만)와 지불 능력이 함께 성립할 때만 활성 — 판정은 코어 값으로만 한다
func _refresh_repair_button() -> void:
	var outgame := session.outgame
	var line := float(outgame.free_restore_line())
	var recoverable := outgame.chassis < line
	var affordable := outgame.credits >= outgame.field_repair_cost()
	_repair_button.disabled = not (recoverable and affordable)
	_repair_button.focus_mode = Control.FOCUS_NONE if _repair_button.disabled else Control.FOCUS_ALL


# 이번 비용 → 다음 회차 비용 병기 (D07 §3.3 필수 규격). 체증 계산은 코어가 한다.
func _refresh_repair_cost() -> void:
	var s := session.data.strings
	var cost_text := s.text("ui.recap.repairCostFormat", {
		"now": session.outgame.field_repair_cost(),
		"next": session.outgame.field_repair_cost_next(),
	})
	_repair_cost.text = cost_text
