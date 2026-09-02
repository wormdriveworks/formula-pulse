# HUB-08 시즌 오버홀 — D09 §4.6 · 별첨A §A-18.
#
# **시즌 결산 직후 1회 전용 진입** — 개러지 허브에서 재진입 불가 (D06 G-M2의 물리 분리 이행).
# 개러지 앵커는 상시 소등이고, 이 화면의 유일한 진입은 SET-02 → HUB-08 체인이다.
# ①등급 판정(시즌 성적 연동) ②후보 일람(전 후보 열람 자유) ③선택 → **비가역 COM-01**.
#
# 진입 체인 = SET-02 시즌 결산 → HUB-08 (`season_result_screen._on_next()`). 결선 완료.
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
	# **후보 수는 규칙값이 아니라 실제로 그릴 목록에서 센다** (총괄 승인 — IMPL-128 §6).
	# 규칙값(`overhaul_slots(_rank).candidates`)은 진입 payload 의 rank 에서 나오고 목록은
	# 결산 층이 추첨한 결과라, 두 rank 가 어긋나면 헤더가 목록과 다른 수를 말한다
	# (실측 재현: 헤더 '후보 4' · 목록 5행). 같은 배열에서 세면 구조적으로 갈릴 수 없다 —
	# IMPL-100·124와 같은 "표시값은 판정값에서 파생시킨다" 처리다.
	var grade_text := s.text("ui.overhaulScreen.gradeFormat", {
		"rank": _rank,
		"slots": int(slots.get("slots", 0)),
		"candidates": _shown_candidates().size(),
	})
	(%GradeLabel as Label).text = grade_text
	_rebuild_candidates()
	var confirm := %ConfirmButton as Button
	confirm.text = s.text("ui.overhaulScreen.confirm")
	confirm.disabled = true
	confirm.pressed.connect(_on_confirm)
	# ── 무후보 출구 (개선 2026-09-03 H5) ──
	# 후기 시즌에 전 오버홀을 보유하면 추첨이 후보 0 을 돌려주고(`draw_overhaul_candidates` 풀
	# 고갈) 화면은 전 보유 목록을 비활성으로 그린다. 시즌 체인은 뒤로가 숨겨져 있으므로 **고를
	# 것도 나갈 곳도 없는 화면**이 된다 — 확정 버튼을 '통과'로 바꿔 같은 체인 출구를 연다.
	# 슬롯 0(등급표 밖 rank)도 같은 상태다: 어느 후보를 눌러도 설치가 거부되므로 함께 묶는다.
	if _selectable_count() == 0 or _remaining_slots() <= 0:
		_arm_pass_through()
	_focus_initial()


# 후보 일람 = 추첨 결과 (D06 §5.3 — 추첨은 세션 결산 층, 화면은 난수를 쓰지 않는다).
# 후보 미추첨 상태(구세이브·개발 진입)는 전 오버홀 폴백 — 코어 가드도 같은 조건으로 관용한다.
# **헤더의 후보 수도 이 배열을 센다** — 표시 두 곳이 같은 원천을 본다.
func _shown_candidates() -> Array:
	var shown: Array = session.outgame.overhaul_candidates
	if shown.is_empty():
		return session.data.overhauls.keys()
	return shown


func _rebuild_candidates() -> void:
	var list := %CandidateList as VBoxContainer
	for child in list.get_children():
		child.queue_free()
	for overhaul_id in _shown_candidates():
		list.add_child(_candidate(String(overhaul_id)))


func _candidate(overhaul_id: String) -> Control:
	var s := session.data.strings
	var row := HBoxContainer.new()
	row.name = overhaul_id.to_pascal_case()
	row.add_theme_constant_override("separation", 8)
	var pick := Button.new()
	pick.add_theme_font_size_override("font_size", _body_font_size)
	pick.name = "Pick"
	pick.toggle_mode = true
	pick.text = s.text(String(session.data.overhauls[overhaul_id]["name_key"]))
	pick.custom_minimum_size = Vector2(150, 0)
	pick.toggled.connect(_on_pick.bind(overhaul_id))
	row.add_child(pick)
	if session.outgame.overhauls.has(overhaul_id):
		pick.disabled = true
		var owned := Label.new()
		owned.add_theme_font_size_override("font_size", _body_font_size)
		owned.text = s.text("ui.facilityPanel.owned")
		owned.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		row.add_child(owned)
	return row


func _on_pick(pressed: bool, overhaul_id: String) -> void:
	_selected = overhaul_id if pressed else ""
	# 단일 선택 — 다른 토글 해제 (목록에는 후보 행 외의 안내 라벨도 설 수 있다 — 행만 만진다)
	for row in (%CandidateList as VBoxContainer).get_children():
		var pick := row.get_node_or_null("Pick") as Button
		if pick != null and row.name != overhaul_id.to_pascal_case():
			pick.set_pressed_no_signal(false)
	(%ConfirmButton as Button).disabled = _selected.is_empty()


func _on_confirm() -> void:
	if _selected.is_empty():
		return
	var s := session.data.strings
	var overhaul_name := s.text(String(session.data.overhauls[_selected]["name_key"]))
	var summary := s.text("ui.overhaulScreen.installConfirm", {"overhaul": overhaul_name})
	# 확정 전 취소·재검토 자유, 확정은 비가역 (§A-18 ④)
	var dialog := ConfirmDialog.ask(self, s, summary, "", true, _body_font_size)
	dialog.resolved.connect(func(accepted: bool):
		if not accepted:
			return
		if session.outgame.install_overhaul(_selected, _rank):
			sfx("overhaul_install")   # SE-U14 시즌 오버홀 적용
			# 상위권 = 슬롯 2 (D13 §7.1) — 잔여 슬롯과 고를 후보가 남으면 화면에 머문다.
			# [가안] 잔여 슬롯은 후보 잔존 시 선택 필수 (포기 동선은 씬 개편 사안 — 주력 몫)
			if _remaining_slots() > 0 and _selectable_count() > 0:
				_selected = ""
				(%ConfirmButton as Button).disabled = true
				_rebuild_candidates()
				_focus_initial()
				return
			_leave())


# 무후보 통과 — 확정 버튼을 출구로 바꾼다. 사유 안내 한 줄을 목록 머리에 세운다(비활성 목록만
# 서 있으면 "왜 못 고르는가"가 보이지 않는다). 설치 확정과 같은 `_leave()` 를 탄다.
func _arm_pass_through() -> void:
	var s := session.data.strings
	var confirm := %ConfirmButton as Button
	if confirm.pressed.is_connected(_on_confirm):
		confirm.pressed.disconnect(_on_confirm)
	confirm.pressed.connect(_leave)
	confirm.text = s.text("ui.overhaulScreen.passThrough")
	confirm.disabled = false
	var note := Label.new()
	note.name = "NoCandidateNote"
	note.add_theme_font_size_override("font_size", _body_font_size)
	note.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	note.text = s.text("ui.overhaulScreen.noCandidates")
	var list := %CandidateList as VBoxContainer
	list.add_child(note)
	list.move_child(note, 0)


# 체인 출구 — 설치 완료와 무후보 통과가 같은 길을 쓴다.
#
# 시즌 체인 경유(SET-02 → HUB-08) = D09 §2.3 플로우맵의
# `HUB-08 → 시즌 엔딩 VN → HUB-01 → 다음 시즌 오프닝 VN` 구간이다.
#
# **엔딩은 `begin_next_season()` 앞에서 발화한다** — 슬롯 `trigger` 가 `season_end`
# 이므로 엔딩은 **떠나는 시즌의 것**이고, `trigger_vn` 이 시즌 계수를 올리므로
# 전환 뒤에 두면 새 시즌의 상한을 잡아먹는다(D08 §8.4 시즌당 계수).
#
# **개막 VN 은 여기서 발화하지 않는다** — 정본이 HUB-01 **뒤**에 둔다(24차 판정 A안).
# 23차까지는 여기서 개막을 띄웠고, 엔딩이 붙으면 두 경계 비트가 개러지 완충 없이
# 연속 6라인으로 읽혀 닫힘과 열림이 같은 호흡에 들어간다(내러티브 6차 §4.2).
# 개막은 개러지 이탈 지점(`garage_screen._on_depart`)이 맡는다.
func _leave() -> void:
	if _season_chain:
		var closing := session.season_close_payload("HUB-01")
		session.begin_next_season()
		session.save_progress()  # 시즌 경계 저장 지점 (D09 §2.4)
		if not closing.is_empty():
			go("NAR-01", closing)
			return
	go("HUB-01", {})


# 초기 포커스 — 첫 선택 가능 후보, 없으면 확정(통과) 버튼, 그것도 없으면 뒤로.
# 종전에는 아무 데도 포커스가 없어 시즌 체인(뒤로 숨김)에서 패드·키보드로는 어느 버튼에도
# 닿을 수 없었다 (회차 1·2 포커스 계열과 같은 잠금).
func _focus_initial() -> void:
	for row in (%CandidateList as VBoxContainer).get_children():
		var pick := row.get_node_or_null("Pick") as Button
		if pick != null and not pick.disabled:
			pick.grab_focus()
			return
	var confirm := %ConfirmButton as Button
	if not confirm.disabled:
		confirm.grab_focus()
		return
	var back := get_node_or_null("%BackButton") as Button
	if back != null and back.visible:
		back.grab_focus()


func _remaining_slots() -> int:
	var slots := session.outgame.overhaul_slots(_rank)
	return int(slots.get("slots", 0)) - session.outgame.overhaul_installs_this_season


# 그릴 목록 기준의 선택 가능 후보 수 — 헤더·목록과 같은 원천(`_shown_candidates`)을 센다.
# 종전 `_has_selectable_candidate()` 는 추첨 배열만 봐서 폴백 목록(구세이브)에서는 늘 0 이었다.
func _selectable_count() -> int:
	var count := 0
	for overhaul_id in _shown_candidates():
		if not session.outgame.overhauls.has(String(overhaul_id)):
			count += 1
	return count
