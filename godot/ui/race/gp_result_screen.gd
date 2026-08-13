# RACE-03 그랑프리 결산 (D09 §5.1 · 별첨A §A-8).
#
# 단일 패널 수직 블록: ①최종 순위(+포지션 변동) ②투어 포인트 가산 ③수입 내역 ④이월 자원 ⑤주 버튼.
# **리타이어 분기:** ①에 리타이어 표기 + 투어 탈락 고지, ⑤ = SET-01 직행 (D05 §9.2·9.3).
#
# **저장 지점이다** (D09 §2.4 — RESULT 진입 시 자동 저장). 수동 저장은 없다.
# 수입은 코어가 계산한다 — 화면은 D06 Source 항목별로 나눠 보여주기만 한다
# (S1 상금과 S2 완주 보너스를 합치지 않는 이유는 IMPL-053 참조).
extends FlowScreen

@onready var _rank_label: Label = %RankValue
@onready var _retire_badge: Label = %RetireBadge
@onready var _points_label: Label = %PointsValue
@onready var _prize_label: Label = %PrizeValue
@onready var _bonus_label: Label = %BonusValue
@onready var _carry_label: Label = %CarryValue
@onready var _next_button: Button = %NextButton
@onready var _save_badge: Label = %SaveBadge


func _on_bound(_payload: Dictionary) -> void:
	var s := session.data.strings
	var result := session.last_gp_result
	var retired := bool(result.get("player_retired", false))
	var rank := int(result.get("player_rank", 0))
	var tour_points := int(result.get("tour_points", 0))

	(%HeaderLabel as Label).text = s.text("ui.gpResult.header")
	(%RankLabel as Label).text = s.text("ui.gpResult.finalRank")
	(%PointsLabel as Label).text = s.text("ui.gpResult.tourPoints")
	(%PrizeLabel as Label).text = s.text("ui.gpResult.prize")
	(%BonusLabel as Label).text = s.text("ui.gpResult.finishBonus")
	(%CarryLabel as Label).text = s.text("ui.gpResult.carryOver")

	var rank_text := s.text("ui.gpResult.rankFormat", {"rank": rank})
	_rank_label.text = rank_text
	_retire_badge.visible = retired
	_retire_badge.text = s.text("ui.gpResult.retired")
	var points_text := s.text("ui.gpResult.pointsFormat", {"points": tour_points})
	_points_label.text = points_text

	var prize := session.outgame.gp_prize(tour_points, not retired)
	var bonus := session.outgame.finish_bonus(not retired)
	session.outgame.gain_credits(prize + bonus)
	var prize_text := s.text("ui.gpResult.creditFormat", {"amount": prize})
	var bonus_text := s.text("ui.gpResult.creditFormat", {"amount": bonus})
	_prize_label.text = prize_text
	_bonus_label.text = bonus_text

	var carry_text := s.text("ui.gpResult.carryFormat", {
		"chassis": int(session.engine.chassis), "charge": session.engine.charge,
	})
	_carry_label.text = carry_text

	# 리타이어 = 런 오버 → 투어 탈락 (D05 §9.2·9.3). 투어 층에 먼저 알린다.
	if retired:
		session.season.mark_dropout()
	var to_tour_report := retired or not session.tour_has_remaining_gp()
	_next_button.text = s.text(
		"ui.gpResult.toTourReport" if to_tour_report else "ui.gpResult.next"
	)
	_next_button.pressed.connect(_on_next.bind(to_tour_report))
	_next_button.grab_focus()

	var saved := session.save_progress()
	_save_badge.visible = bool(saved.get("ok", false))
	_save_badge.text = s.text("ui.gpResult.saved")
	if not bool(saved.get("ok", false)):
		push_error("GpResultScreen: autosave failed - %s" % String(saved.get("reason", "")))


func _on_next(to_tour_report: bool) -> void:
	if to_tour_report:
		session.close_tour()
		go("SET-01", {})
		return
	# 이벤트 노드 삽입 지점 (D09 §2.3 — RACE-03 → RUN-01 사이, 발생 시에만).
	# 무발생이면 RUN-02 는 화면 자체가 비표출이다 (D09 §5.4).
	var occurrence := session.judge_event()
	if not occurrence.is_empty():
		go("RUN-02", {"occurrence": occurrence})
		return
	go("RUN-01", {})
