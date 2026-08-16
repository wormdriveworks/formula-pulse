# HUB-08 시즌 오버홀 — D09 §4.6 · 별첨A §A-18.
#
# **시즌 결산 직후 1회 전용 진입** — 개러지 허브에서 재진입 불가 (D06 G-M2의 물리 분리 이행).
# 개러지 앵커는 상시 소등이고, 이 화면의 유일한 진입은 SET-02 → HUB-08 체인이다.
# ①등급 판정(시즌 성적 연동) ②후보 일람(전 후보 열람 자유) ③선택 → **비가역 COM-01**.
#
# SET-02가 아직 없어 현재 라우터에서 도달 불가다 — 화면·규격을 먼저 세우고 체인은 SET-02 결선 시.
extends HubScreen

var _selected := ""
var _rank := 8
var _season_chain := false


func _on_hub_ready(payload: Dictionary) -> void:
	var s := session.data.strings
	(%HeaderLabel as Label).text = s.text("ui.overhaulScreen.title")
	_rank = int(payload.get("championship_rank", 8))
	_season_chain = bool(payload.get("season_chain", false))
	# 1회 전용 진입 (G-M2) — 확정 전에 개러지로 새면 재진입이 불가하므로 뒤로를 막는다.
	# 취소·재검토의 자유는 화면 안(후보 재선택·COM-01 취소)에서 보장된다 (D07 실장 규칙).
	if _season_chain:
		(%BackButton as Button).visible = false
	var slots := session.outgame.overhaul_slots(_rank)
	var grade_text := s.text("ui.overhaulScreen.gradeFormat", {
		"rank": _rank,
		"slots": int(slots.get("slots", 0)),
		"candidates": int(slots.get("candidates", 0)),
	})
	(%GradeLabel as Label).text = grade_text
	_rebuild_candidates()
	var confirm := %ConfirmButton as Button
	confirm.text = s.text("ui.overhaulScreen.confirm")
	confirm.disabled = true
	confirm.pressed.connect(_on_confirm)


# 후보 일람 = 추첨 결과 (D06 §5.3 — 추첨은 세션 결산 층, 화면은 난수를 쓰지 않는다).
# 후보 미추첨 상태(구세이브·개발 진입)는 전 오버홀 폴백 — 코어 가드도 같은 조건으로 관용한다.
func _rebuild_candidates() -> void:
	var list := %CandidateList as VBoxContainer
	for child in list.get_children():
		child.queue_free()
	var shown: Array = session.outgame.overhaul_candidates
	if shown.is_empty():
		shown = session.data.overhauls.keys()
	for overhaul_id in shown:
		list.add_child(_candidate(String(overhaul_id)))


func _candidate(overhaul_id: String) -> Control:
	var s := session.data.strings
	var row := HBoxContainer.new()
	row.name = overhaul_id.to_pascal_case()
	row.add_theme_constant_override("separation", 8)
	var pick := Button.new()
	pick.name = "Pick"
	pick.toggle_mode = true
	pick.text = s.text(String(session.data.overhauls[overhaul_id]["name_key"]))
	pick.custom_minimum_size = Vector2(150, 0)
	pick.toggled.connect(_on_pick.bind(overhaul_id))
	row.add_child(pick)
	if session.outgame.overhauls.has(overhaul_id):
		pick.disabled = true
		var owned := Label.new()
		owned.text = s.text("ui.facilityPanel.owned")
		owned.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		row.add_child(owned)
	return row


func _on_pick(pressed: bool, overhaul_id: String) -> void:
	_selected = overhaul_id if pressed else ""
	# 단일 선택 — 다른 토글 해제
	for row in (%CandidateList as VBoxContainer).get_children():
		var pick := row.get_node("Pick") as Button
		if row.name != overhaul_id.to_pascal_case():
			pick.set_pressed_no_signal(false)
	(%ConfirmButton as Button).disabled = _selected.is_empty()


func _on_confirm() -> void:
	if _selected.is_empty():
		return
	var s := session.data.strings
	var overhaul_name := s.text(String(session.data.overhauls[_selected]["name_key"]))
	var summary := s.text("ui.overhaulScreen.installConfirm", {"overhaul": overhaul_name})
	# 확정 전 취소·재검토 자유, 확정은 비가역 (§A-18 ④)
	var dialog := ConfirmDialog.ask(self, s, summary, "", true)
	dialog.resolved.connect(func(accepted: bool):
		if not accepted:
			return
		if session.outgame.install_overhaul(_selected, _rank):
			# 상위권 = 슬롯 2 (D13 §7.1) — 잔여 슬롯과 고를 후보가 남으면 화면에 머문다.
			# [가안] 잔여 슬롯은 후보 잔존 시 선택 필수 (포기 동선은 씬 개편 사안 — 주력 몫)
			if _remaining_slots() > 0 and _has_selectable_candidate():
				_selected = ""
				(%ConfirmButton as Button).disabled = true
				_rebuild_candidates()
				return
			# 시즌 체인 경유(SET-02 → HUB-08)면 다음 시즌을 개막하고 개러지로.
			# (시즌 엔딩 VN은 NAR-01 결선 시 이 사이에 삽입된다 — D09 §2.3)
			if _season_chain:
				session.begin_next_season()
				session.save_progress()  # 시즌 경계 저장 지점 (D09 §2.4)
			go("HUB-01", {}))


func _remaining_slots() -> int:
	var slots := session.outgame.overhaul_slots(_rank)
	return int(slots.get("slots", 0)) - session.outgame.overhaul_installs_this_season


func _has_selectable_candidate() -> bool:
	for overhaul_id in session.outgame.overhaul_candidates:
		if not session.outgame.overhauls.has(String(overhaul_id)):
			return true
	return false
