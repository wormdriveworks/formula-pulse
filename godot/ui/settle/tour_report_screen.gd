# SET-01 투어 결산 리포트 (D09 §5.1 · 별첨A §A-21).
#
# D06 §4.2 시퀀스 ①~⑧을 **표시 블록으로 1:1 번역**한다 (D09 §5.1 확정):
#   1 투어 종합 순위 / 2 챔피언십 포인트 / 3 수입(Cr) / 4 펄스 차지 환전 / 5 차지 소멸 고지
#   6 획득 주행 데이터 / 7 마일스톤(해당 시) / 8 [개러지로]
#
# **탈락 분기 (확정):** 블록 1 = 탈락 시점 성적 마감 · 블록 3 = S4 축소·S3 미지급 명시 ·
# **블록 4 = 비표출** · 블록 5~8 동일. 톤은 소프트 실패 원칙(D05 §9.5) — "실패/GAME OVER" 계열 금지.
#
# 블록 5(소멸 고지)를 블록 4(환전)와 분리하는 이유는 D09 §5.1 명문이다 —
# 환전 후 잔여 0이라는 문맥으로 제시해야 소멸이 손실로 오독되지 않는다.
extends FlowScreen

@onready var _block4: Control = %Block4
@onready var _next_button: Button = %NextButton


# SE-U15 결산 포인트 롤업 — 블록별 수치가 채워지는 동안의 루프음이다. 롤업 연출(수치
# 카운트업)은 아직 없어 진입 1회로 둔다. 연출이 붙으면 시작·종료를 이 지점이 감싼다.
func _audio_enter_events() -> Array:
	return ["settle_rollup"]


func _on_bound(_payload: Dictionary) -> void:
	var s := session.data.strings
	var report := session.last_tour_report
	var dropped := bool(report.get("dropped_out", false))
	var position := int(report.get("player_position", 0))

	(%HeaderLabel as Label).text = s.text("ui.tourReport.header")
	(%Block1Label as Label).text = s.text("ui.tourReport.block1")
	(%Block2Label as Label).text = s.text("ui.tourReport.block2")
	(%Block3Label as Label).text = s.text("ui.tourReport.block3")
	(%Block4Label as Label).text = s.text("ui.tourReport.block4")
	(%Block5Label as Label).text = s.text("ui.tourReport.block5")
	(%Block6Label as Label).text = s.text("ui.tourReport.block6")

	var rank_text := s.text("ui.tourReport.rankFormat", {"rank": position})
	(%Block1Value as Label).text = rank_text
	var championship := int(session.season.championship_points.get(SeasonState.PLAYER_ID, 0))
	var championship_text := s.text("ui.tourReport.pointsFormat", {"points": championship})
	(%Block2Value as Label).text = championship_text

	# 블록 3 — 탈락 시 S3 미지급·S4 축소를 문면으로 명시한다 (D06 §4.2)
	# 지급·환전은 세션 경로 전속 (규칙이 화면에 갇히지 않는다) — 화면은 반환값을 표시만 한다
	var settled := session.settle_tour(session.engine.charge if session.engine != null else 0)
	var credits := int(settled["credits"])
	var dp := int(settled["dp"])
	var credit_text := s.text("ui.tourReport.creditFormat", {"amount": credits})
	var data_text := s.text("ui.tourReport.dataFormat", {"amount": dp})
	(%Block3Value as Label).text = credit_text
	(%Block6Value as Label).text = data_text
	(%Block3Note as Label).visible = dropped
	(%Block3Note as Label).text = s.text("ui.tourReport.dropoutNote")

	# 블록 4 — 완주 시에만 표출 (탈락 시 환전 자체가 성립하지 않는다)
	_block4.visible = not dropped
	if not dropped:
		var exchanged := int(settled["exchanged"])
		var exchanged_text := s.text("ui.tourReport.creditFormat", {"amount": exchanged})
		(%Block4Value as Label).text = exchanged_text
	(%Block5Value as Label).text = s.text("ui.tourReport.chargeExpired")

	_next_button.text = s.text("ui.tourReport.toGarage")
	_next_button.pressed.connect(_on_next)
	_next_button.grab_focus()
	session.save_progress()  # 투어 경계 저장 지점 (D09 §2.4)


func _on_next() -> void:
	# D09 §2.3: [시즌 내 잔여 투어 有] → HUB-01 / [시즌 최종 투어] → SET-02 체인
	if session.season.season_finished():
		session.close_season()
		go("SET-02", {})
		return
	go("HUB-01", {})
