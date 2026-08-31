# SYS-02 세이브 슬롯 (D09 별첨A §A-2).
#
# **수동 저장은 없다** (D09 §2.4 확정 — 로그라이트 관행·세이브 스커밍 차단). 슬롯은 저장 행위가
# 아니라 **프로필 개념**(복수 커리어)으로만 운용하므로 이 화면에 저장 버튼류를 두지 않는다.
# 슬롯 수는 데이터 경유다 (`param_save_profile_count` — D12 §7.1이 '확정 기준값'으로 지정).
#
# 로드는 `SaveManager` 전속이다 (IMPL-037 · ARCH 정적 규칙).
extends FlowScreen

const SLOT_CONTAINER := "%SlotRow"

var _mode := "new"
var _slot_buttons: Array[Button] = []
# 슬롯 삭제 2단 확인 상태 — 모달을 세우지 않는 것이 의도다 (2026-09-01): 이 리포의 실기
# 결함 계열이 전부 오버레이 포커스 관리에서 나왔고, 같은 버튼의 재확인은 포커스가
# 이동할 일 자체가 없다. 포커스가 떠나면 무장 해제 — 오조작이 이월되지 않는다.
var _delete_armed: Dictionary = {}


func _on_bound(payload: Dictionary) -> void:
	_mode = String(payload.get("mode", "new"))
	var s := session.data.strings
	(%HeaderLabel as Label).text = s.text("ui.save.header")
	var back_button := %BackButton as Button
	back_button.text = s.text("ui.save.back")
	back_button.pressed.connect(func(): go("SYS-01", {}))
	_build_slots()


func _build_slots() -> void:
	var s := session.data.strings
	var row := get_node(SLOT_CONTAINER)
	# 삭제 후 재구축 경로 — 첫 진입에서는 빈 순회다
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	_slot_buttons.clear()
	_delete_armed.clear()
	var count := int(session.data.param("param_save_profile_count"))
	for profile in range(1, count + 1):
		var loaded := SaveManager.load_progress(profile)
		var has_save := bool(loaded.get("ok", false))
		var column := VBoxContainer.new()
		column.name = "SlotColumn%d" % profile
		column.add_theme_constant_override("separation", 3)
		var card := _card_for(profile, loaded, has_save)
		column.add_child(card)
		_slot_buttons.append(card)
		if has_save:
			column.add_child(_delete_button_for(profile))
		row.add_child(column)
	if not _slot_buttons.is_empty():
		_slot_buttons[0].grab_focus()
	# 슬롯이 데이터 값보다 적게 서면 조용히 넘어가지 않는다
	if _slot_buttons.size() != count:
		push_error("SaveSlotScreen: built %d slots but data says %d" % [_slot_buttons.size(), count])
	(%HintLabel as Label).text = s.text(
		"ui.save.hintNew" if _mode == "new" else "ui.save.hintContinue"
	)


func _card_for(profile: int, loaded: Dictionary, has_save: bool) -> Button:
	var s := session.data.strings
	var button := Button.new()
	button.add_theme_font_size_override("font_size", _body_font_size)
	button.name = "Slot%d" % profile
	button.custom_minimum_size = Vector2(170, 90)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var label := s.text("ui.save.slotFormat", {"index": profile})
	var body := ""
	if has_save:
		var payload: Dictionary = loaded.get("payload", {})
		var season_payload: Dictionary = payload.get("season", {})
		body = s.text("ui.save.progressFormat", {
			"season": int(season_payload.get("season", 1)),
			"tour": int(season_payload.get("tour_slot", 1)),
			"race": int(season_payload.get("race_slot", 1)),
		})
		# 카드 상세 (개선 2026-09-01) — 시즌·투어·전만으로는 두 커리어가 갈리지 않았다.
		# 크레딧(진행의 경제 단면)과 저장 시각(어느 쪽이 최근인가)을 한 줄 보탠다.
		# 소재는 세이브 봉투가 이미 가진 값(outgame.credits · saved_at 스탬프) — 새 기록 없음.
		var saved_at := int(payload.get("saved_at", 0))
		if saved_at > 0:
			var outgame_payload: Dictionary = payload.get("outgame", {})
			var stamp := Time.get_datetime_dict_from_unix_time(
				saved_at + Time.get_time_zone_from_system().get("bias", 0) * 60
			)
			var saved_text := s.text("ui.save.savedAtFormat", {
				"month": int(stamp.get("month", 0)),
				"day": int(stamp.get("day", 0)),
				"hour": "%02d" % int(stamp.get("hour", 0)),
				"minute": "%02d" % int(stamp.get("minute", 0)),
			})
			var detail := s.text("ui.save.detailFormat", {
				"credits": int(outgame_payload.get("credits", 0)),
				"saved": saved_text,
			})
			body = s.text("ui.save.cardBodyFormat", {"progress": body, "detail": detail})
	else:
		body = s.text("ui.save.empty")
	var card_text := s.text("ui.save.cardFormat", {"label": label, "body": body})
	button.text = card_text
	button.pressed.connect(_on_slot_pressed.bind(profile, has_save))
	return button


# 슬롯 삭제 — 같은 버튼 2회 누름 확인 (모달 불신설 근거는 `_delete_armed` 주석).
# 실행은 SaveManager 전속(ARCH 규약) — 진행·백업·스냅샷·격리 4파일을 걷는다.
func _delete_button_for(profile: int) -> Button:
	var s := session.data.strings
	var button := Button.new()
	button.name = "Delete%d" % profile
	button.add_theme_font_size_override("font_size", _body_font_size)
	button.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	button.text = s.text("ui.save.delete")
	button.set_meta(AUDIO_EVENT_META, "ui_cancel")   # 파괴 조작 — 결정음이 아니라 취소·닫기 축
	button.pressed.connect(_on_delete_pressed.bind(profile, button))
	button.focus_exited.connect(_on_delete_disarmed.bind(profile, button))
	button.mouse_exited.connect(_on_delete_disarmed.bind(profile, button))
	return button


func _on_delete_pressed(profile: int, button: Button) -> void:
	var s := session.data.strings
	if not bool(_delete_armed.get(profile, false)):
		_delete_armed[profile] = true
		button.text = s.text("ui.save.deleteConfirm")
		return
	_delete_armed.erase(profile)
	if not SaveManager.delete_progress(profile):
		return
	# 카드·삭제 버튼 전부 새 상태로 다시 세운다 — 포커스는 재구축이 첫 슬롯에 되잡는다
	# (버튼이 free 되므로 되잡지 않으면 포커스 소실 계열 결함이 재현된다)
	_build_slots()


func _on_delete_disarmed(profile: int, button: Button) -> void:
	if not bool(_delete_armed.get(profile, false)):
		return
	_delete_armed.erase(profile)
	if is_instance_valid(button):
		button.text = session.data.strings.text("ui.save.delete")


func _on_slot_pressed(profile: int, has_save: bool) -> void:
	if _mode == "continue" and has_save:
		var loaded := SaveManager.load_progress(profile)
		session.profile_index = profile
		if not session.restore(loaded.get("payload", {})):
			push_error("SaveSlotScreen: restore failed for profile %d" % profile)
			return
	else:
		# 신규 — 기존 세이브가 있어도 여기서 지우지 않는다. 덮어쓰기는 첫 저장 지점에서
		# 일어나며, 그 경로에는 백업 회전이 걸려 있다(IMPL-028).
		session.begin_career(profile)
		# 시즌 오프닝 VN + 캘린더 공개 비트 (D09 §2.3 — 신규 진입 경로).
		# [가안] vn 인스턴스 id 는 시즌 단위 발급 — 실문안 트랙 유입 시 대장으로 교체
		#
		# **그 뒤에 개시형 막 VN(1막)이 붙는다** — 플로우맵이 시즌 오프닝 VN 과 투어 시작 VN 을
		# 연속 슬롯으로 두고(D09 §2.3), D08 §8.1 의 공표 위치가 브리핑 슬롯이다.
		# 대기분이 없으면 사슬이 그대로 `RACE-01` 로 접힌다 — 분기를 두지 않는다.
		var after_open := session.take_brief_payload("RACE-01")
		# 페이로드는 세션 창구가 조립한다 — 라인·톤이 비트 표에서 오므로 화면이 표를 읽지 않는다.
		# 화면이 직접 조립하던 시절에는 `line_keys` 가 빠져 폴백 1줄이 떴다(주력 12차 관측 3).
		go("NAR-01", session.season_open_payload(
			"NAR-01" if not after_open.is_empty() else "RACE-01", after_open))
		return
	go("RACE-01", {})
