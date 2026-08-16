# SET-02 시즌 결산 화면 — D09 §5.1 · 별첨A §A-22.
#
# ①챔피언십 최종 스탠딩 ②시즌 지표 요약 ③판정 표시 ④[시즌 오버홀로 ▶].
#
# **소프트 실패 문면 원칙 (확정):** 챔피언 미달 시즌의 결산에 "실패/GAME OVER" 계열 표기를
# 금지한다 — 시즌 성과 요약 + 다음 시즌 이행으로만 구성한다 (D05 §9.5 · D06 §6.3).
# 에필로그(2연속 챔피언) 관련 표기는 **달성 시에만** — 사전 예고 없음 (D08 히든 정합).
extends FlowScreen

const STANDINGS_SHOWN := 10

@onready var _next_button: Button = %NextButton


func _on_bound(_payload: Dictionary) -> void:
	var s := session.data.strings
	var report := session.last_season_report
	var standings: Array = report.get("standings", [])
	var player_position := int(report.get("player_position", 0))
	var champion := String(report.get("champion", ""))

	(%HeaderLabel as Label).text = s.text("ui.seasonResult.headerFormat", {
		"season": int(report.get("season", 1)),
	})
	# S6 시즌 결산 지급 (D06 §2.1) — 지급은 세션 경로 전속. 표시 항목은 §A-22 개편 시 배치.
	session.settle_season()

	# ① 최종 스탠딩 — 상위 N + 플레이어 행 (전 순위 열람은 기록실 층 소관)
	var list := %StandingsList as VBoxContainer
	for index in range(mini(STANDINGS_SHOWN, standings.size())):
		var entrant_id := String(standings[index])
		var row := Label.new()
		var row_text := s.text("ui.seasonResult.rowFormat", {
			"rank": index + 1,
			"name": _entrant_name(entrant_id),
			"points": int(session.season.championship_points.get(entrant_id, 0)),
		})
		row.text = row_text
		if entrant_id == SeasonState.PLAYER_ID:
			row.add_theme_color_override("font_color", UiPalette.TIMER_LEEWAY)
		list.add_child(row)

	# ② 지표 요약
	var summary_text := s.text("ui.seasonResult.summaryFormat", {
		"rank": player_position,
		"points": int(session.season.championship_points.get(SeasonState.PLAYER_ID, 0)),
	})
	(%SummaryLabel as Label).text = summary_text

	# ③ 판정 — 달성 시 칭호 문면(획득 구문 — 이전(移轉) 함의 금지, D09 §5.5) /
	#    미달 시 소프트 실패 문면 (다음 시즌 이행의 사실 서술)
	var verdict := %VerdictLabel as Label
	if champion == SeasonState.PLAYER_ID:
		verdict.text = s.text("ui.seasonResult.champion")
		verdict.add_theme_color_override("font_color", UiPalette.SYMBOL_CHANCE)
		if bool(report.get("epilogue", false)):
			(%EpilogueLabel as Label).text = s.text("ui.seasonResult.epilogue")
			(%EpilogueLabel as Label).visible = true
	else:
		verdict.text = s.text("ui.seasonResult.carryOn")
		verdict.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)

	_next_button.text = s.text("ui.seasonResult.toOverhaul")
	_next_button.pressed.connect(_on_next.bind(player_position))
	_next_button.grab_focus()


func _entrant_name(entrant_id: String) -> String:
	var s := session.data.strings
	if session.engine != null and session.engine.entrants.has(entrant_id):
		var entrant: Dictionary = session.engine.entrants[entrant_id]
		if bool(entrant["is_filler"]):
			return s.text(String(entrant["name_key"]), {"number": int(entrant["number"])})
		return s.text(String(entrant["name_key"]))
	# 엔진 부재 폴백 — 네임드·플레이어는 데이터에서 이름을 얻는다 (필러 번호만 엔진 소관)
	if entrant_id == SeasonState.PLAYER_ID:
		return s.text("ui.race.playerName")
	for rival_row in session.data.rivals:
		if String(rival_row["id"]) == entrant_id:
			return s.text(String(rival_row["name_key"]))
	return entrant_id


func _on_next(player_position: int) -> void:
	# 시즌 결산 직후 1회 전용 진입 (G-M2 물리 분리 — HUB-08의 유일한 진입 경로)
	go("HUB-08", {"championship_rank": maxi(player_position, 1), "season_chain": true})
