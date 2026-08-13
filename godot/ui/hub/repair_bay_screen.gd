# HUB-02 정비 베이 — D09 §4.3 · 별첨A §A-12.
#
# 전면 정비 단일 카드: 비용 · 완전 회복 고스트 게이지 · 실행. 테오 스탠딩 상주(아트 유입 대상).
# 무상 복원선(투어 개시 70)은 자동 처리 고지행으로만 표기한다 (§A-12 확정).
#
# **실행은 잠금** — 섀시가 GP 간 이월되지 않아(IMPL-078) 회복할 손상이 존재하지 않는다.
# 비용 규격·고지행은 규격대로 세워 두고, 이월이 결선되면 실행만 푼다.
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
	run.disabled = true  # IMPL-078 — 이월 결선 전
	run.focus_mode = Control.FOCUS_NONE
	(%BackButton as Button).grab_focus()
