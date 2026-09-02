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

	# **이월 자원은 엔진에서 온다** — 그런데 이 화면은 엔진 없이도 세워질 수 있다(15차 ㉝ 축이
	# 마운트하면서 드러났다: `session.engine` 이 null 인 문맥에서 `.chassis` 두 줄이 널 접근으로
	# 붉었다). **거동은 바꾸지 않는다** — 널 접근의 결과도 0 이었으므로 표시는 그대로이고,
	# 없어지는 것은 에러 출력뿐이다. **도달성은 확인하지 않았다** — 실기 경로가 이 상태를
	# 만드는지는 별건이며, 여기서는 검사 하네스가 만든 문맥에서 나온 잡음을 지운다.
	var carry_chassis: int = int(session.engine.chassis) if session.engine != null else 0
	var carry_charge: int = session.engine.charge if session.engine != null else 0
	var carry_text := s.text("ui.gpResult.carryFormat", {
		"chassis": carry_chassis, "charge": carry_charge,
	})
	_carry_label.text = carry_text

	# 레이스 요약·순위표 (개선 2026-09-01) — 결산이 P{n} 한 줄만 말해 레이스의 경과가
	# 화면에 남지 않았다. 소재는 엔진 result 가 이미 세던 값 전용 — 새 판정 없음.
	_mount_race_digest(result)
	_mount_standings(result)

	# 리타이어 = 런 오버 → 투어 탈락 (D05 §9.2·9.3). 투어 층에 먼저 알린다.
	if retired:
		session.season.mark_dropout()
	var to_tour_report := retired or not session.tour_has_remaining_gp()
	_next_button.text = s.text(
		"ui.gpResult.toTourReport" if to_tour_report else "ui.gpResult.next"
	)
	_next_button.pressed.connect(_on_next.bind(to_tour_report))
	_next_button.grab_focus()
	# 진입 직후 오입력 방어 창 (개선 2026-09-03 — 회차 1 이월) — 레이스 끝까지 연타한 확정 입력이
	# 결산을 지나치지 않게 한다. 값 창구 = D13 `param_settle_input_guard_sec`.
	InputGuard.arm(self, session.data.param("param_settle_input_guard_sec"))

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


# ── 레이스 다이제스트 — 순위 변동·듀얼 전적·트러블 (개선 2026-09-01) ──
#
# 씬 무접촉: 기존 Column 의 행 문법(라벨 110px 감광 + 값)을 코드로 복제해 최종 순위 행
# 바로 아래에 끼운다. 코드 생성 Control 이므로 폰트 크기를 명시한다(엔진 기본 16 함정 —
# IMPL-125 계열). start_rank = 0 은 도입 전 스냅샷 재개 표식이라 그 행만 생략한다.
func _mount_race_digest(result: Dictionary) -> void:
	var s := session.data.strings
	var rank_row := _rank_label.get_parent() as Control
	var column := rank_row.get_parent() as Control
	var anchor_index := rank_row.get_index() + 1
	var start_rank := int(result.get("start_rank", 0))
	if start_rank > 0:
		var delta_text := s.text("ui.gpResult.gridDeltaFormat", {
			"start": start_rank, "finish": int(result.get("player_rank", 0)),
		})
		var delta_row := _digest_row("ui.gpResult.gridDelta", delta_text)
		column.add_child(delta_row)
		column.move_child(delta_row, anchor_index)
		anchor_index += 1
	var duels := int(result.get("duels", 0))
	var wins := int(result.get("duel_wins", 0))
	var duel_text := s.text("ui.gpResult.duelRecordNone")
	if duels > 0:
		duel_text = s.text("ui.gpResult.duelRecordFormat", {
			"count": duels, "wins": wins, "losses": duels - wins,
		})
	var duel_row := _digest_row("ui.gpResult.duelRecord", duel_text)
	column.add_child(duel_row)
	column.move_child(duel_row, anchor_index)
	anchor_index += 1
	var trouble_text := s.text("ui.gpResult.troubleTurnsFormat", {
		"count": int(result.get("trouble_turns", 0)),
	})
	var trouble_row := _digest_row("ui.gpResult.troubleTurns", trouble_text)
	column.add_child(trouble_row)
	column.move_child(trouble_row, anchor_index)


func _digest_row(label_key: String, value_text: String) -> Control:
	var s := session.data.strings
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.custom_minimum_size = Vector2(110, 0)
	label.text = s.text(label_key)
	label.add_theme_font_size_override("font_size", _body_font_size)
	label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	row.add_child(label)
	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", _body_font_size)
	value.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	row.add_child(value)
	return row


# ── 최종 순위표 — 전 참가자 (개선 2026-09-01) ──
#
# 소재 = result.standings(완주 순 + 리타이어 최하위 역순 — 엔진 `_finish_gp` 조립 그대로).
# 표기 참조(name_key·number·is_player·retired)는 엔진 entrants 에서 읽는다 — 이 화면은
# GP 직후에만 서므로 엔진이 살아 있고, 없으면(검사 하네스 단독 마운트) 표를 생략한다.
# 자리 = 우측: 좌측 요약 열은 종전대로 서고, 비어 있던 오른쪽 절반이 표를 진다.
# 필러 name_key 는 문면 자체가 `No.{number} 머신`이라 number 를 같은 params 로 넘긴다
# (엔진 `_entrant_params` 와 같은 짝 규약).
func _mount_standings(result: Dictionary) -> void:
	if session.engine == null:
		return
	var standings: Array = result.get("standings", [])
	if standings.is_empty():
		return
	var s := session.data.strings
	var pad := (_rank_label.get_parent().get_parent() as Control).get_parent() as Control
	var pane := Control.new()
	pane.name = "StandingsPane"
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(pane)
	var table := VBoxContainer.new()
	table.name = "StandingsTable"
	# 우측 절반 앵커 — 성장 방향·오프셋을 짝으로 명시한다 (ANCH 규약)
	table.anchor_left = 0.55
	table.anchor_right = 1.0
	table.anchor_top = 0.0
	table.anchor_bottom = 1.0
	table.offset_left = 0.0
	table.offset_right = 0.0
	table.offset_top = 26.0   # 표제(14px 폰트) 줄 아래에서 시작
	table.offset_bottom = 0.0
	table.grow_horizontal = Control.GROW_DIRECTION_BOTH
	table.grow_vertical = Control.GROW_DIRECTION_BOTH
	table.add_theme_constant_override("separation", 1)
	pane.add_child(table)
	var header := Label.new()
	header.text = s.text("ui.gpResult.standingsHeader")
	header.add_theme_font_size_override("font_size", _body_font_size)
	header.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	table.add_child(header)
	for index in range(standings.size()):
		var entrant_id := String(standings[index])
		var entrant: Dictionary = session.engine.entrants.get(entrant_id, {})
		if entrant.is_empty():
			continue
		var was_retired := bool(entrant.get("retired", false))
		var row_key := "ui.gpResult.standingRetired" if was_retired else "ui.gpResult.standingRowFormat"
		var display_name := s.text(String(entrant.get("name_key", "")), {
			"number": entrant.get("number", 0),
		})
		var row := Label.new()
		row.text = s.text(row_key, {"rank": index + 1, "name": display_name})
		row.add_theme_font_size_override("font_size", _body_font_size)
		if bool(entrant.get("is_player", false)):
			row.add_theme_color_override("font_color", UiPalette.ACCENT_ACTIVE)
		elif was_retired:
			row.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		else:
			row.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
		table.add_child(row)
