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
	_enter_audio(retired, rank)

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

	# 지급은 세션 경로 전속 (러너·테스트가 같은 경로를 탄다) — 화면은 반환값을 표시만 한다
	var settled := session.settle_gp()
	var prize := int(settled["prize"])
	var bonus := int(settled["bonus"])
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


# 결산 진입 사운드 — **순서가 규칙이다** (D11 §4.3 전이 규칙표).
#   GP 종료 : 무대 트랙 아웃 → JG-01/02 → BGM-08
#   리타이어: BGM 즉시 정지 → JG-03 → 결산 진입
# 리타이어 징글(JG-03)은 리타이어 확정 시점(RACE-01)이 이미 울렸으므로 여기서 겹치지 않는다.
#
# **상위/중하위 경계 = 포디움 [가안].** D11 §4.2 는 JG-01 을 "상위 성적"이라고만 하고 수치를
# 두지 않는다. 게임이 이미 가진 유일한 상위 성적 경계인 포디움을 쓰되, 그 임계도 코드에
# 적지 않고 `milestone_first_podium` 행의 값을 읽는다 — 값 창구 밖에서 수치를 만들지 않는다.
func _enter_audio(retired: bool, rank: int) -> void:
	if session.audio != null:
		session.audio.stop_bgm()   # 무대 트랙 아웃 — 징글이 트랙 위에 겹치지 않게 먼저 끈다
	if not retired:
		var podium := CsvTable.to_int(String(
			session.data.milestones["milestone_first_podium"]["threshold"]))
		sfx("gp_result_high" if rank >= 1 and rank <= podium else "gp_result_low")
	sfx("gp_result_enter")
	sfx("rank_stamp")   # SE-U16 순위 확정 스탬프
	if not session.newly_achieved.is_empty():
		sfx("achievement_get")
	if not session.newly_opened_tiers.is_empty():
		sfx("growth_gate_open")   # SE-U13 — 스킬 티어 개방은 마일스톤 연동(D07 §4.3)


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
