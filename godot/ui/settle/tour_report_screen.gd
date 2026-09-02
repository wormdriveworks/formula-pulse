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
#
# 조판 (개선 2026-09-03): 좌측 = 블록 열(순위 값은 표제 계열·강조색 — 화면의 주역), 우측 = 투어
# 순위표(RACE-03 순위표와 같은 문법 — 결산이 P{n} 한 줄만 말하고 화면 절반이 비어 있던 자리).
# 상단 = 탈락 배지 · 시즌/투어 부제 · 저장 배지 (RACE-03 헤더 행과 동형).
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
	# 탈락 배지 — 사실 표기 한 단어. 소프트 실패 원칙상 실패·GAME OVER 계열 문면은 쓰지 않는다.
	(%DropoutBadge as Label).visible = dropped
	(%DropoutBadge as Label).text = s.text("ui.tourReport.dropout")
	# 어느 투어의 결산인가 — `SeasonState.close_tour()` 가 tour_slot 을 이미 다음 투어로 올렸으므로
	# 시즌 층의 현재값이 아니라 리포트가 쥔 마감 투어 번호를 읽는다.
	(%SubHeaderLabel as Label).text = s.text("ui.tourReport.subheaderFormat", {
		"season": session.season.season,
		"tour": int(report.get("tour_slot", 0)),
	})
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

	_mount_standings(report)

	_next_button.text = s.text("ui.tourReport.toGarage")
	_next_button.pressed.connect(_on_next)
	_next_button.grab_focus()
	var saved := session.save_progress()  # 투어 경계 저장 지점 (D09 §2.4)
	(%SaveBadge as Label).visible = bool(saved.get("ok", false))
	(%SaveBadge as Label).text = s.text("ui.tourReport.saved")
	# 진입 직후 오입력 방어 창 (개선 2026-09-03 — 회차 1 이월) — 마지막 GP 결산에서 연타한 확정
	# 입력이 이 화면을 지나치지 않게 한다. 값 창구 = D13 `param_settle_input_guard_sec`.
	InputGuard.arm(self, session.data.param("param_settle_input_guard_sec"))


# ── 투어 순위표 — 전 참가자 (개선 2026-09-03 조판) ──
#
# 소재 = report.standings(`close_tour()` 가 투어 포인트 내림차순으로 조립한 순서) +
# report.tour_points(마감 투어 누계 스냅숏 — 시즌 층은 결산 직후 다음 투어를 열며 누계를 비우므로
# 리포트가 함께 싣는다). 표기명은 `entrant_name()`(엔진 → 데이터 폴백). 신규 판정 0.
# 자리 = 우측 절반 — RACE-03 순위표와 같은 앵커 문법(성장 방향·오프셋을 짝으로 명시, ANCH 규약).
func _mount_standings(report: Dictionary) -> void:
	var standings: Array = report.get("standings", [])
	if standings.is_empty():
		return
	var s := session.data.strings
	var points: Dictionary = report.get("tour_points", {})
	var pad := get_node("Pad") as Control
	var pane := Control.new()
	pane.name = "StandingsPane"
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(pane)
	var table := VBoxContainer.new()
	table.name = "StandingsTable"
	table.anchor_left = 0.55
	table.anchor_right = 1.0
	table.anchor_top = 0.0
	table.anchor_bottom = 1.0
	table.offset_left = 0.0
	table.offset_right = 0.0
	table.offset_top = 40.0   # 표제 행(14px 폰트) + 부제 행 아래에서 시작
	table.offset_bottom = 0.0
	table.grow_horizontal = Control.GROW_DIRECTION_BOTH
	table.grow_vertical = Control.GROW_DIRECTION_BOTH
	table.add_theme_constant_override("separation", 1)
	pane.add_child(table)
	var header := Label.new()
	header.text = s.text("ui.tourReport.standingsHeader")
	header.add_theme_font_size_override("font_size", _body_font_size)
	header.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	table.add_child(header)
	for index in range(standings.size()):
		var entrant_id := String(standings[index])
		var row := Label.new()
		row.text = s.text("ui.tourReport.standingRowFormat", {
			"rank": index + 1,
			"name": entrant_name(entrant_id),
			"points": int(points.get(entrant_id, 0)),
		})
		row.add_theme_font_size_override("font_size", _body_font_size)
		row.add_theme_color_override("font_color",
			UiPalette.ACCENT_ACTIVE if entrant_id == SeasonState.PLAYER_ID else UiPalette.TEXT_PRIMARY)
		table.add_child(row)


func _on_next() -> void:
	# D09 §2.3: [시즌 내 잔여 투어 有] → HUB-01 / [시즌 최종 투어] → SET-02 체인
	var destination := "HUB-01"
	if session.season.season_finished():
		session.close_season()
		destination = "SET-02"
	# 투어 종료 마일스톤 VN — **여기가 그 슬롯이다** (D08 §8.4 `slot_kind = tour_close`).
	# 자격이 있으면 한 건이 서고, 같은 경계에 몰린 나머지는 다음 경계로 **저절로 이월된다**
	# (자격을 상태에서 도출하므로 대기열이 없다 — `run_session.pending_milestone_beat`).
	# 시즌 최종 투어에서도 같은 자리다: 결산 앞에 서는 것이 '투어 종료'의 문면 그대로다.
	var milestone := session.milestone_payload(destination)
	if not milestone.is_empty():
		go("NAR-01", milestone)
		return
	go(destination, {})
