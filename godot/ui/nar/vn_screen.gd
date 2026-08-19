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

# 베인 화자 판별용 — 큐음이 갈린다 (SE-V01 베인 3단계 / SE-V02 그 외 공용, D11 §2.10).
const VANE_SPEAKER_KEY := "ui.vn.speakerVane"
# 투어 브리핑 슬롯 — 재회 체인 비트 3축 중 하나의 발생 지점 (`vn_slots.csv`)
const TOUR_BRIEF_SLOT := "vnslot_tour_brief"

# 라인 = `{"speaker_key": String, "text_key": String}` 로 정규화해 둔다.
# 문자열 항목도 그대로 받는다 — 골격·아카이브 재열람 등 기존 호출부가 문자열 배열을 넘긴다.
var _lines: Array = []
var _line_index := 0
var _default_speaker_key := VANE_SPEAKER_KEY
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
		if bool(outcome.get("occurred", false)) and slot_id == TOUR_BRIEF_SLOT:
			# 재회 체인 비트 — 투어 브리핑 VN 축 (D08 §8.7-3). **발생 시점에 센다**:
			# 열람·스킵을 가르지 않는 것이 형식 A 의 계약이고(§10.3 R-D07-VN),
			# 재열람 경로(`_replay`)는 이 갈래에 들어오지 않으므로 불계수가 구조로 선다.
			session.record_reunion_beat("tour_brief")
		if not bool(outcome.get("occurred", false)):
			# 상한 도달 등으로 미발생 — 화면을 세우지 않고 다음으로 직행
			go(_next_route, _next_payload)
			return

	# VN 트랙 2종 (BGM-09 일상 / BGM-10 긴장) — D12 v1.3 §5.4 `tone` 열 결선분.
	sfx("vn_enter_%s" % _resolve_tone(payload, slot_id, vn_id))
	(%SkipButton as Button).text = s.text("ui.vn.skip")
	(%SkipButton as Button).set_meta(AUDIO_EVENT_META, "ui_cancel")   # 스킵 = 닫기 축
	(%SkipButton as Button).pressed.connect(_on_skip.bind(vn_id, slot_id))
	# 화자는 **라인 단위**다 (총괄 판정 IMPL-249 ② — 신설안 C 승인).
	# 페이로드의 `speaker_key` 는 라인이 화자를 지정하지 않았을 때의 기본값으로만 남는다.
	_default_speaker_key = String(payload.get("speaker_key", VANE_SPEAKER_KEY))
	_lines = _normalize_lines(payload.get("line_keys", ["ui.vn.placeholderLine01"]))
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


# 정조 해석 (D12 v1.3 §5.4) — **미지정 = `calm`.** 값 도메인은 표시 문면(일상/긴장)이 아니라
# `sound_map` 의 event_id 조립 문자열이다(`vn_enter_calm`/`vn_enter_tense`).
#
# 우선순위 = **인스턴스 > `milestone_vn` > `vn_slots` > `calm`.**
# D12 는 정조 열을 **VN 발생 단위 표** 2종에 두었는데 그 두 표는 *슬롯 종류* 축이다
# (막 전이/크루 합류/기원 단서/일반 성취). T7 납품 6건은 같은 '막 전이' 종류 안에서
# 정조가 갈리므로(1·2막·에필로그 = calm / 3·4막·기원 공개 = tense) 종류 행 하나로는
# 표현되지 않는다 — 그래서 인스턴스가 정조를 들고 오면 그것이 이긴다. **[가안]**:
# 표 열이 인스턴스별 정조를 담을 자리를 얻으면 이 우선순위 한 줄이 사라진다.
func _resolve_tone(payload: Dictionary, slot_id: String, vn_id: String) -> String:
	var tone := String(payload.get("tone", ""))
	if tone.is_empty():
		tone = String(session.data.milestone_vn_row(vn_id).get("tone", ""))
	if tone.is_empty():
		tone = String(session.data.vn_slot(slot_id).get("tone", ""))
	return tone if tone == "calm" or tone == "tense" else "calm"


# 페이로드 라인 목록 정규화 — 문자열 항목과 사전 항목을 함께 받는다(하위 호환).
#
# **왜 사전이 필요한가.** 정본 3개소가 한 VN 안의 복수 화자를 전제한다: D04 §5.2 지문·
# D09 별첨A §A-19 좌/우 2인·D11 §2.10 베인 전용 큐음. 이벤트 단위 화자로는 그 셋을
# 동시에 만족하는 표현이 없다 — 실제로 T7 납품 6건이 **전건** 화자 교대를 쓴다.
func _normalize_lines(raw: Variant) -> Array:
	var normalized: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return normalized
	for item in raw:
		if typeof(item) == TYPE_DICTIONARY:
			var entry: Dictionary = item
			normalized.append({
				"speaker_key": String(entry.get("speaker_key", _default_speaker_key)),
				"text_key": String(entry.get("text_key", "")),
			})
		else:
			# 구 계약 — 문자열 1개 = 텍스트 키. 화자는 페이로드 기본값을 승계한다.
			normalized.append({"speaker_key": _default_speaker_key, "text_key": String(item)})
	return normalized


func _show_line() -> void:
	var s := session.data.strings
	var line: Dictionary = _lines[_line_index]
	var speaker_key := String(line["speaker_key"])
	(%BodyLabel as Label).text = s.text(String(line["text_key"]))
	# 화자 라벨도 라인마다 바뀐다. 지문 화자(`ui.vn.speakerNarration`)는 값이 공란이라
	# 라벨이 비는 것이 곧 지문 표기다 — 별도 분기를 두지 않는다.
	(%SpeakerLabel as Label).text = s.text(speaker_key)
	# 대사창 갱신 1회당 큐음 1발 (D11 §2.10). 베인만 인격 3단계로 음색이 갈리고
	# 나머지 화자는 공용음이다 — 캐릭터별 개별음은 불채택 확정.
	# **판정을 라인 단위로 옮겼다** — 이벤트 단위로 두면 마르타 대사에 베인 3단계 큐음이
	# 실린다(D11 §2.10 위반). 총괄 판정 IMPL-249 ② 교정분.
	if speaker_key == VANE_SPEAKER_KEY:
		sfx("vane_cue_stage%d" % session.outgame.vane_stage())
	else:
		sfx("speaker_cue")


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
		row.add_theme_font_size_override("font_size", _body_font_size)
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
