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


func _on_hub_ready(payload: Dictionary) -> void:
	var s := session.data.strings
	(%HeaderLabel as Label).text = s.text("ui.overhaulScreen.title")
	_rank = int(payload.get("championship_rank", 8))
	var slots := session.outgame.overhaul_slots(_rank)
	var grade_text := s.text("ui.overhaulScreen.gradeFormat", {
		"rank": _rank,
		"slots": int(slots.get("slots", 0)),
		"candidates": int(slots.get("candidates", 0)),
	})
	(%GradeLabel as Label).text = grade_text
	var list := %CandidateList as VBoxContainer
	# 후보 일람 — 전 후보 효과 열람 자유 (§A-18 ②). 골격: 전 오버홀 나열, 후보 추첨은
	# 시즌 결산 층 결선 시 (추첨 스트림 소관 — 화면이 난수를 쓰지 않는다).
	for overhaul_id in session.data.overhauls:
		list.add_child(_candidate(String(overhaul_id)))
	var confirm := %ConfirmButton as Button
	confirm.text = s.text("ui.overhaulScreen.confirm")
	confirm.disabled = true
	confirm.pressed.connect(_on_confirm)


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
			go("HUB-01", {}))
