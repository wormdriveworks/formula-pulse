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
	var count := int(session.data.param("param_save_profile_count"))
	for profile in range(1, count + 1):
		var card := _card_for(profile)
		row.add_child(card)
		_slot_buttons.append(card)
	if not _slot_buttons.is_empty():
		_slot_buttons[0].grab_focus()
	# 슬롯이 데이터 값보다 적게 서면 조용히 넘어가지 않는다
	if _slot_buttons.size() != count:
		push_error("SaveSlotScreen: built %d slots but data says %d" % [_slot_buttons.size(), count])
	(%HintLabel as Label).text = s.text(
		"ui.save.hintNew" if _mode == "new" else "ui.save.hintContinue"
	)


func _card_for(profile: int) -> Button:
	var s := session.data.strings
	var button := Button.new()
	button.add_theme_font_size_override("font_size", _body_font_size)
	button.name = "Slot%d" % profile
	button.custom_minimum_size = Vector2(170, 90)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var label := s.text("ui.save.slotFormat", {"index": profile})
	var loaded := SaveManager.load_progress(profile)
	var body := ""
	if bool(loaded.get("ok", false)):
		var payload: Dictionary = loaded.get("payload", {})
		var season_payload: Dictionary = payload.get("season", {})
		body = s.text("ui.save.progressFormat", {
			"season": int(season_payload.get("season", 1)),
			"tour": int(season_payload.get("tour_slot", 1)),
			"race": int(season_payload.get("race_slot", 1)),
		})
	else:
		body = s.text("ui.save.empty")
	var card_text := s.text("ui.save.cardFormat", {"label": label, "body": body})
	button.text = card_text
	button.pressed.connect(_on_slot_pressed.bind(profile, bool(loaded.get("ok", false))))
	return button


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
		var after_open := session.take_act_vn_payload("RACE-01")
		go("NAR-01", {
			"vn_id": "vn_season_open_s%d" % session.season.season,
			"slot_id": "vnslot_season_open",
			"calendar": true,
			"next": "NAR-01" if not after_open.is_empty() else "RACE-01",
			"next_payload": after_open,
		})
		return
	go("RACE-01", {})
