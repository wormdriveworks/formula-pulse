# SET-02 시즌 결산 화면 — D09 §5.1 · 별첨A §A-22.
#
# ①챔피언십 최종 스탠딩 ②시즌 지표 요약 ③판정 표시 ④[시즌 오버홀로 ▶].
#
# **소프트 실패 문면 원칙 (확정):** 챔피언 미달 시즌의 결산에 "실패/GAME OVER" 계열 표기를
# 금지한다 — 시즌 성과 요약 + 다음 시즌 이행으로만 구성한다 (D05 §9.5 · D06 §6.3).
# 에필로그(2연속 챔피언) 관련 표기는 **달성 시에만** — 사전 예고 없음 (D08 히든 정합).
#
# 조판 (개선 회차 4 S2-O1 — SET-01 문법 이식): 표제 → 판정 부제(9px · 챔피언 = 찬스색 / 이행 = 감광) →
# 좌열 시즌 지표(챔피언십 순위 값은 표제 계열·강조색 — 화면의 주역 · 포인트 · 투어 우승 · 다음 시즌 그리드 레벨)
# → 우측 절반 = 최종 스탠딩 **전 참가자**(종전 상위 10행 좌열 나열을 대체 · 플레이어 행 강조).
extends FlowScreen

@onready var _next_button: Button = %NextButton


func _on_bound(_payload: Dictionary) -> void:
	var s := session.data.strings
	var report := session.last_season_report
	# 트랙 아웃 → 징글 → 결산 트랙 (D11 §4.3 전이 규칙의 GP 전례를 시즌 경계에 그대로 적용).
	# 징글은 아래 판정 분기가 내고, 여기서는 앞뒤 순서만 잡는다.
	if session.audio != null:
		session.audio.stop_bgm()
	var standings: Array = report.get("standings", [])
	var player_position := int(report.get("player_position", 0))
	var champion := String(report.get("champion", ""))

	(%HeaderLabel as Label).text = s.text("ui.seasonResult.headerFormat", {
		"season": int(report.get("season", 1)),
	})
	# S6 시즌 결산 지급 (D06 §2.1) — 지급은 세션 경로 전속. 표시 항목은 §A-22 개편 시 배치.
	session.settle_season()

	# ③ 판정 — 달성 시 칭호 문면(획득 구문 — 이전(移轉) 함의 금지, D09 §5.5) /
	#    미달 시 소프트 실패 문면 (다음 시즌 이행의 사실 서술)
	var verdict := %VerdictLabel as Label
	if champion == SeasonState.PLAYER_ID:
		verdict.text = s.text("ui.seasonResult.champion")
		verdict.add_theme_color_override("font_color", UiPalette.SYMBOL_CHANCE)
		# JG-04 시즌 챔피언 / JG-05 칭호·특별 달성 — 챔피언 칭호는 두 축을 동시에 만족한다.
		sfx("season_champion")
		sfx("title_award")
		if bool(report.get("epilogue", false)):
			(%EpilogueLabel as Label).text = s.text("ui.seasonResult.epilogue")
			(%EpilogueLabel as Label).visible = true
	else:
		verdict.text = s.text("ui.seasonResult.carryOn")
		verdict.add_theme_color_override("font_color", UiPalette.TEXT_DIM)

	# ② 시즌 지표 — 리포트가 쥔 값만 옮긴다 (판정은 `close_season()` 원천 전속 · IMPL-142)
	(%RankLabel as Label).text = s.text("ui.seasonResult.rankLabel")
	(%PointsLabel as Label).text = s.text("ui.seasonResult.pointsLabel")
	(%TourWinsLabel as Label).text = s.text("ui.seasonResult.tourWinsLabel")
	(%GridLabel as Label).text = s.text("ui.seasonResult.gridLabel")
	var rank_text := s.text("ui.seasonResult.rankFormat", {"rank": player_position})
	(%RankValue as Label).text = rank_text
	var points_text := s.text("ui.seasonResult.pointsFormat", {
		"points": int(session.season.championship_points.get(SeasonState.PLAYER_ID, 0)),
	})
	(%PointsValue as Label).text = points_text
	var tour_wins_text := s.text("ui.seasonResult.countFormat", {"value": int(report.get("tour_wins", 0))})
	(%TourWinsValue as Label).text = tour_wins_text
	var grid_text := s.text("ui.seasonResult.gridFormat", {
		"level": int(report.get("grid_level_next", session.season.grid_level)),
	})
	(%GridValue as Label).text = grid_text

	# ① 최종 스탠딩 — 전 참가자 (우측 절반)
	_mount_standings(standings)

	sfx("season_result_enter")   # BGM-11 — 징글 뒤에 트랙이 든다 (§4.3 순서)
	_next_button.text = s.text("ui.seasonResult.toOverhaul")
	_next_button.pressed.connect(_on_next.bind(player_position))
	_next_button.grab_focus()
	# 진입 직후 오입력 방어 창 (개선 2026-09-03 — 회차 1 이월) — 투어 결산에서 이어 누른 확정
	# 입력이 시즌 결산을 지나쳐 오버홀 화면까지 밀고 가지 않게 한다 (결산 3화면 공통).
	InputGuard.arm(self, session.data.param("param_settle_input_guard_sec"))


# ── 최종 스탠딩 — 전 참가자 (개선 회차 4 조판) ──
#
# 소재 = report.standings(`close_season()` 이 챔피언십 포인트 내림차순으로 조립한 순서) +
# `season.championship_points`(다음 시즌 개시 전이라 아직 살아 있다). 표기명 = `entrant_name()`.
# 자리 = 우측 절반 — RACE-03·SET-01 순위표와 같은 앵커 문법(성장 방향·오프셋 짝 명시, ANCH 규약).
func _mount_standings(standings: Array) -> void:
	if standings.is_empty():
		return
	var s := session.data.strings
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
	table.offset_top = 40.0   # 표제(14px 폰트) + 판정 부제 행 아래에서 시작
	table.offset_bottom = 0.0
	table.grow_horizontal = Control.GROW_DIRECTION_BOTH
	table.grow_vertical = Control.GROW_DIRECTION_BOTH
	table.add_theme_constant_override("separation", 1)
	pane.add_child(table)
	var header := Label.new()
	header.text = s.text("ui.seasonResult.standingsHeader")
	header.add_theme_font_size_override("font_size", _body_font_size)
	header.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	table.add_child(header)
	for index in range(standings.size()):
		var entrant_id := String(standings[index])
		var row := Label.new()
		row.text = s.text("ui.seasonResult.rowFormat", {
			"rank": index + 1,
			"name": entrant_name(entrant_id),
			"points": int(session.season.championship_points.get(entrant_id, 0)),
		})
		row.add_theme_font_size_override("font_size", _body_font_size)
		row.add_theme_color_override("font_color",
			UiPalette.ACCENT_ACTIVE if entrant_id == SeasonState.PLAYER_ID else UiPalette.TEXT_PRIMARY)
		table.add_child(row)


func _on_next(player_position: int) -> void:
	# 시즌 결산 직후 1회 전용 진입 (G-M2 물리 분리 — HUB-08의 유일한 진입 경로)
	# 절상은 close_season() 원천 전속 (IMPL-142) — 화면은 받은 값을 그대로 전달한다.
	go("HUB-08", {"championship_rank": player_position, "season_chain": true})
