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
	# 3기능 전부 **실행은 잠금**이다 — 비용·규격 표시는 세우되 실제 적용 대상이 아직 없다.
	# 필드 정비가 회복할 섀시는 GP 간 이월분인데 `RaceEngine.start_gp()` 가 매 GP
	# `param_chassis_max` 로 리셋하므로 이월분이 존재하지 않는다(실측). 섀시 이월은 로직 층
	# 사안이라 여기서 만들지 않고 보고한다 — IMPL-078. 덱·소모품도 소비 경로 결선 전이다.
	for locked in [_repair_button, _consumable_button, _deck_button]:
		locked.disabled = true
		locked.focus_mode = Control.FOCUS_NONE
	_next_button.grab_focus()  # 초기 포커스 = 주 버튼 (§A-9 E05)


# 이번 비용 → 다음 회차 비용 병기 (D07 §3.3 필수 규격). 체증 계산은 코어가 한다.
func _refresh_repair_cost() -> void:
	var s := session.data.strings
	var cost_text := s.text("ui.recap.repairCostFormat", {
		"now": session.outgame.field_repair_cost(),
		"next": session.outgame.field_repair_cost_next(),
	})
	_repair_cost.text = cost_text
