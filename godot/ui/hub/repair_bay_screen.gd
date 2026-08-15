# HUB-02 정비 베이 — D09 §4.3 · 별첨A §A-12.
#
# 전면 정비 단일 카드: 비용 · 완전 회복 고스트 게이지 · 실행. 테오 스탠딩 상주(아트 유입 대상).
# 무상 복원선(투어 개시 70)은 자동 처리 고지행으로만 표기한다 (§A-12 확정).
# 실행은 섀시 이월 결선(IMPL-078 해소)으로 개방 — 비용·회복량 판정은 전부 코어 소관.
extends HubScreen


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
	_refresh_run_button()
	(%BackButton as Button).grab_focus()


func _on_run_pressed() -> void:
	session.outgame.full_repair()
	refresh_currency()
	_refresh_run_button()


# 손상(최대치 미만)과 지불 능력이 함께 성립할 때만 활성 — 이미 만충이면 소등
func _refresh_run_button() -> void:
	var outgame := session.outgame
	var damaged := outgame.chassis < session.data.param("param_chassis_max")
	var affordable := outgame.credits >= outgame.full_repair_cost()
	var run := %RunButton as Button
	run.disabled = not (damaged and affordable)
	run.focus_mode = Control.FOCUS_NONE if run.disabled else Control.FOCUS_ALL
