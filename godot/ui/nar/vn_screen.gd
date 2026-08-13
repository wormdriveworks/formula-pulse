# NAR-01 VN 이벤트 화면 — D09 §5.3 · 별첨A §A-19.
#
# 스탠딩(좌/우 최대 2인 — 아트 유입 대상, 자리만) + 하단 대사창(화자명 + 본문 최대 2줄·
# 전각 24자) + 선택지 오버레이(골격 미사용 — 실문안 D04 트랙).
#
# **스킵 (절대 규격):** 스킵 버튼 상시 노출(우상단 고정) — 이벤트 단위 즉시 스킵.
# **형식 A 무관성:** 관계 전이는 VN '발생(도달)' 기준·열람/스킵 무관 — **화면은 전이 관련
# 어떤 표시도 하지 않는다** (스킵이 페널티로 오독될 여지 원천 차단 — D09 §5.3).
#
# 대사 실문안은 D04 텍스트 풀 트랙 소관이다. 골격은 슬롯당 자리 문면 키를 재생하며
# 실문안 유입 시 라인 목록만 교체된다 — [가안] IMPL-086.
#
# NAR-02 캘린더 공개 비트는 이 화면 **내부 오버레이**다 (신규 슬롯 불신설 — D08 §2.1).
extends FlowScreen

var _lines: Array = []
var _line_index := 0
var _calendar_pending := false
var _next_route := ""
var _next_payload: Dictionary = {}
var _replay := false


func _on_bound(payload: Dictionary) -> void:
	var s := session.data.strings
	_replay = bool(payload.get("replay", false))
	_next_route = String(payload.get("next", "RACE-01"))
	_next_payload = payload.get("next_payload", {})
	_calendar_pending = bool(payload.get("calendar", false))
	var vn_id := String(payload.get("vn_id", ""))
	var slot_id := String(payload.get("slot_id", ""))

	# 발생 판정은 서사 층이 한다 — 재생 모드는 상태를 바꾸지 않는다 (재열람 멱등)
	if _replay:
		session.narrative.replay_from_archive(vn_id)
	elif not vn_id.is_empty():
		var outcome: Dictionary = session.narrative.trigger_vn(vn_id, slot_id, false)
		if not bool(outcome.get("occurred", false)):
			# 상한 도달 등으로 미발생 — 화면을 세우지 않고 다음으로 직행
			go(_next_route, _next_payload)
			return

	(%SkipButton as Button).text = s.text("ui.vn.skip")
	(%SkipButton as Button).pressed.connect(_on_skip.bind(vn_id, slot_id))
	var speaker_key := String(payload.get("speaker_key", "ui.vn.speakerVane"))
	var speaker_text := s.text(speaker_key)
	(%SpeakerLabel as Label).text = speaker_text
	_lines = payload.get("line_keys", ["ui.vn.placeholderLine01"])
	_line_index = 0
	_show_line()
	(%AdvanceButton as Button).grab_focus()
	(%AdvanceButton as Button).pressed.connect(_advance)
	(%CalendarPanel as Control).visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_SPACE or key.keycode == KEY_ENTER:
		_advance()
		get_viewport().set_input_as_handled()


func _show_line() -> void:
	var s := session.data.strings
	(%BodyLabel as Label).text = s.text(String(_lines[_line_index]))


func _advance() -> void:
	# 캘린더 오버레이가 떠 있으면 진행 입력으로 VN 복귀 → 종료 (§A-20)
	if (%CalendarPanel as Control).visible:
		_finish()
		return
	_line_index += 1
	if _line_index < _lines.size():
		_show_line()
		return
	if _calendar_pending:
		_show_calendar()
		return
	_finish()


# NAR-02 — 투어 1~5 무대 열거(수직 타임라인) + 개막전·최종전 앵커 강조.
# 셔플 시스템 설명 텍스트 없음 — 다이제틱("리그 발표") 프레임 (D08 §2.2)
func _show_calendar() -> void:
	var s := session.data.strings
	var panel := %CalendarPanel as Control
	var list := %CalendarList as VBoxContainer
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	(%CalendarTitle as Label).text = s.text("ui.vn.calendarTitle")
	var calendar: Array = session.season.calendar
	for index in range(calendar.size()):
		var stage_id := String(calendar[index])
		var stage: Dictionary = session.data.stages.get(stage_id, {})
		var row := Label.new()
		var anchor := index == 0 or index == calendar.size() - 1
		var row_key := "ui.vn.calendarAnchorFormat" if anchor else "ui.vn.calendarRowFormat"
		var row_text := s.text(row_key, {
			"tour": index + 1,
			"stage": s.text(String(stage.get("name_key", ""))),
		})
		row.text = row_text
		if anchor:
			row.add_theme_color_override("font_color", UiPalette.TIMER_LEEWAY)
		list.add_child(row)
	panel.visible = true


# 이벤트 단위 즉시 스킵 — 발생 등재는 trigger_vn 이 이미 했고(발생 = 도달),
# 스킵 기록만 남긴다. 아카이브 자동 등재 안내 툴팁은 COM-02 결선 시.
func _on_skip(vn_id: String, _slot_id: String) -> void:
	if not _replay and not vn_id.is_empty():
		session.narrative.vn_skipped[vn_id] = true
	if _calendar_pending and not (%CalendarPanel as Control).visible:
		# 스킵해도 캘린더 공개는 건너뛰지 않는다 — 시즌 구조 정보는 서사가 아니라 판단 재료다
		_show_calendar()
		return
	_finish()


func _finish() -> void:
	go(_next_route, _next_payload)
