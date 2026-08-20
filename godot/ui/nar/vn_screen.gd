# NAR-01 VN 이벤트 화면 — D09 §5.3 · 별첨A §A-19.
#
# 스탠딩(좌/우 최대 2인 — 아트 유입 대상, 자리만) + 하단 대사창(화자명 + 본문 최대 2줄·
# 전각 24자) + E05 선택지 오버레이(문안·데이터 유입 완료 — **씬 노드는 주력 몫**이라
# 노드가 설 때까지 지점을 생략한다. "골격 미사용"이 아니라 골격 부재였다 — 납품서 §7.4).
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

# ── E05 선택지 오버레이 (D09 별첨A §A-19 E05 · D04 §5.3) ──
#
# **씬 계약 (주력 몫 — 씬 소유권).** 이 화면 아래 어딘가에
#   · `ChoiceOverlay` : Control — 지점이 설 때만 보인다(초기 `visible = false`)
#   · `ChoiceList`    : Container — 선택지 버튼이 들어갈 자리(레이아웃은 컨테이너가 한다)
# 두 노드가 있으면 지점이 뜨고, **없으면 지점을 생략한다**(아래 `_open_choice`).
# 노드를 코드로 만들지 않는 것은 `.tscn` 무접촉 규약이고, 생략을 택한 것은 그 반대 —
# 없는 노드를 기다리면 화면이 그 자리에서 멈춘다.
const CHOICE_OVERLAY_NAME := "ChoiceOverlay"
const CHOICE_LIST_NAME := "ChoiceList"

# 라인 = `{"speaker_key": String, "text_key": String}` 로 정규화해 둔다.
# 문자열 항목도 그대로 받는다 — 골격·아카이브 재열람 등 기존 호출부가 문자열 배열을 넘긴다.
var _lines: Array = []
var _line_index := 0
var _default_speaker_key := VANE_SPEAKER_KEY
var _calendar_pending := false
var _next_route := ""
var _next_payload: Dictionary = {}
var _replay := false
var _vn_id := ""
# 이번 재생에서 이미 처리한 지점 — 같은 라인으로 되돌아와도 두 번 묻지 않는다.
var _choice_seen: Dictionary = {}
# **노드 부재로 생략한 지점 id.** 생략 자체는 규격이지만 조용한 생략은 금지다 —
# 사람에게는 `push_error`, 기계에는 이 배열이 관측 지점이다.
var choice_omissions: Array = []


func _on_bound(payload: Dictionary) -> void:
	var s := session.data.strings
	_replay = bool(payload.get("replay", false))
	_next_route = String(payload.get("next", "RACE-01"))
	_next_payload = payload.get("next_payload", {})
	_calendar_pending = bool(payload.get("calendar", false))
	var vn_id := String(payload.get("vn_id", ""))
	var slot_id := String(payload.get("slot_id", ""))
	_vn_id = vn_id

	# 발생 판정은 서사 층이 한다 — 재생 모드는 상태를 바꾸지 않는다 (재열람 멱등)
	if _replay:
		session.narrative.replay_from_archive(vn_id)
	elif not vn_id.is_empty():
		var outcome: Dictionary = session.narrative.trigger_vn(vn_id, slot_id, false)
		if bool(outcome.get("occurred", false)) and _is_reunion_chain_beat(vn_id, slot_id):
			# 재회 체인 비트 — 투어 브리핑 VN 축 (D08 §8.7-3). **발생 시점에 센다**:
			# 열람·스킵을 가르지 않는 것이 형식 A 의 계약이고(§10.3 R-D07-VN),
			# 재열람 경로(`_replay`)는 이 갈래에 들어오지 않으므로 불계수가 구조로 선다.
			session.record_reunion_beat("tour_brief")
		if not bool(outcome.get("occurred", false)):
			# 상한 도달 등으로 미발생 — 화면을 세우지 않고 다음으로 직행
			go(_next_route, _next_payload)
			return

	# VN 트랙 2종 (BGM-09 일상 / BGM-10 긴장) — D12 v1.4 §5.4 `tone` 결선분.
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


# 브리핑 슬롯의 VN 이 **재회 체인 비트인가** — 승인 문면은 "알타 리지 투어 내 **체인 비트** 발생"이고
# 막 전이 VN 은 그 체인의 비트가 아니다.
#
# **IMPL-252 의 자기 결함 교정이다.** 그때는 브리핑 슬롯에 production 산출이 하나도 없어
# "브리핑 슬롯 VN = 체인 비트"로 동일시해도 차이가 관측되지 않았다. 16차가 막 VN 을 이 슬롯으로
# 발행하자 동일시가 즉시 새는 것이 실측됐다 — 알타 리지 투어에서 막 VN 2건 사슬만으로
# `relation_reunion` 이 **0 → 2**(threshold1 = 대면)에 도달했다. 재회 서사가 하나도 없는데
# 재회 축이 대면까지 간다.
#
# 가름은 데이터가 한다 — `act_vn.json` 인스턴스면 막 전이다. 그래서 지금 이 축의 브리핑 다리는
# **다시 잠잠해진다**: 재회 체인 브리핑 VN 은 아직 문안이 없다(T7 납품분 = 막 VN). 나머지 두 다리
# (C3 관계 이벤트·카이 벽 조우)는 그대로 살아 있으므로 축 자체는 전진한다.
func _is_reunion_chain_beat(vn_id: String, slot_id: String) -> bool:
	if slot_id != TOUR_BRIEF_SLOT:
		return false
	return session.data.act_vn_entry(vn_id).is_empty()


# 정조 해석 — **D12 v1.4 §5.4 확정 문면의 이행**(총괄 판정 IMPL-253 ① · [가안] 해제).
# 정본 거처 = **VN 인스턴스 정의**(문안 판단이 실리는 단위)이고 슬롯 종류 표
# (`milestone_vn`·`vn_slots`)의 `tone` 열은 **종류 기본값 폴백**으로 존치한다.
# 그래서 우선순위가 **인스턴스 > `milestone_vn` > `vn_slots` > `calm`(미지정)** 이다 —
# 같은 슬롯 종류 안에서 인스턴스별 정조가 갈리므로(T7 6건: 1·2막·에필로그 calm /
# 3·4막·기원 공개 tense) 종류 행 하나로는 표현되지 않는다는 것이 정본의 근거다.
# 값 도메인은 표시 문면(일상/긴장)이 아니라 `sound_map` 의 event_id 조립 문자열이다
# (`vn_enter_calm`/`vn_enter_tense`).
func _resolve_tone(payload: Dictionary, slot_id: String, vn_id: String) -> String:
	var tone := String(payload.get("tone", ""))
	if tone.is_empty():
		tone = String(session.data.milestone_vn_row(vn_id).get("tone", ""))
	# **공란 슬롯은 묻지 않는다** — `vn_slot("")` 은 미상 슬롯으로 보고 `push_error` +
	# `_load_ok` 를 내린다. 슬롯 없이 세우는 경로(아카이브 재열람·막 VN 등)가 정상이므로
	# 여기서 데이터를 조회할 이유가 없다 (총괄 판정 IMPL-263 ⑤).
	if tone.is_empty() and not slot_id.is_empty():
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


# ── 선택 지점 (D04 §5.3 · 총괄 판정 IMPL-257) ──
#
# **분기가 없다.** 선택은 반응 라인 1개를 그 자리에 끼워 넣을 뿐이고 서사 상태·관계 카운터·
# 이후 라인 열에 영향이 0이다(D01 §8-5 폐기 목록 = 분기형 다중 스토리). 그래서 합류가
# 별도 장치 없이 성립한다 — 끼운 다음 라인부터는 아무 일도 없었던 것과 같다.
func _try_open_choice() -> bool:
	if _lines.is_empty() or _line_index >= _lines.size():
		return false
	var row := session.data.vn_choice_at(_vn_id, String(_lines[_line_index]["text_key"]))
	if row.is_empty():
		return false
	var choice_id := String(row["id"])
	if _choice_seen.has(choice_id):
		return false
	_choice_seen[choice_id] = true
	return _open_choice(choice_id)


# 오버레이 노드가 없으면 **지점을 생략한다** — 씬은 주력 소유라 여기서 만들 수 없고,
# 없는 노드를 기다리면 그 자리에서 화면이 멈춘다. 생략은 손실이 아니다(분기 0).
# 다만 조용히 넘기지는 않는다: 사람에게 `push_error`, 기계에 `choice_omissions` 를 남긴다.
#
# **`push_warning` 이 아닌 것은 규칙이다** — ARCH '코어 표준출력 금지'가 `godot/ui` 를 범위에
# 넣고 `push_warning` 을 금칙에 두면서 `push_error` 만 "값 누락 보고에 정당한 용도"로 뺐다.
# 노드 부재는 정확히 그 값 누락 보고다(돌연변이 M1 이 이 위반을 잡아냈다).
func _open_choice(choice_id: String) -> bool:
	var overlay := find_child(CHOICE_OVERLAY_NAME, true, false) as Control
	var list := find_child(CHOICE_LIST_NAME, true, false) as Container
	if overlay == null or list == null:
		choice_omissions.append(choice_id)
		push_error("VnScreen: choice overlay nodes absent — '%s' omitted" % choice_id)
		return false
	var options := session.data.vn_choice_options_for(choice_id)
	if options.is_empty():
		choice_omissions.append(choice_id)
		push_error("VnScreen: choice '%s' has no options — omitted" % choice_id)
		return false
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var s := session.data.strings
	for option in options:
		var button := Button.new()
		button.add_theme_font_size_override("font_size", _body_font_size)
		# 대괄호는 **데이터 값에 들어 있다** — 화면이 `"[%s]"` 로 조립하면 언어별 괄호 관례를
		# 데이터가 흡수하지 못하고 표시 문자열 조합이 코드로 샌다(D12 §8.1 · 납품서 §2 판단).
		button.text = s.text(String(option["text_key"]))
		button.pressed.connect(_on_choice_selected.bind(option))
		list.add_child(button)
	# 동적으로 만든 버튼은 진입 시점의 일괄 결속에 잡히지 않는다 — 여기서 다시 건다.
	audio_bind_controls(list)
	overlay.visible = true
	(list.get_child(0) as Button).grab_focus()
	return true


# 선택 = 반응 라인 1개를 앵커 **바로 뒤**에 끼운다. 그 다음 라인이 곧 합류 지점이다.
func _on_choice_selected(option: Dictionary) -> void:
	_close_choice()
	_lines.insert(_line_index + 1, {
		"speaker_key": String(option["reaction_speaker_key"]),
		"text_key": String(option["reaction_text_key"]),
	})
	_advance()


func _choice_visible() -> bool:
	var overlay := find_child(CHOICE_OVERLAY_NAME, true, false) as Control
	return overlay != null and overlay.visible


func _close_choice() -> void:
	var overlay := find_child(CHOICE_OVERLAY_NAME, true, false) as Control
	if overlay == null:
		return
	overlay.visible = false
	var list := find_child(CHOICE_LIST_NAME, true, false) as Container
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	# 선택지를 지웠으면 포커스도 돌려놓는다 — 안 그러면 진행 버튼이 키 입력을 못 받는다.
	(%AdvanceButton as Button).grab_focus()


func _advance() -> void:
	# 캘린더 오버레이가 떠 있으면 진행 입력으로 VN 복귀 → 종료 (§A-20)
	if (%CalendarPanel as Control).visible:
		_finish()
		return
	# 선택 대기 중에는 진행 입력을 소비하지 않는다 — **선택은 입력 요구**이므로
	# 진행이 임의로 고르거나 건너뛰면 반응 변주가 의사 없이 결정된다(납품서 §3.3 도출).
	# 이것이 막다른 길이 되지 않는 것은 **스킵이 상시 살아 있기 때문**이다(G2 조건 2) —
	# 지점을 필수 통과로 만들지 않는다는 규격은 그 탈출로로 성립한다.
	if _choice_visible():
		return
	# 지점은 **앵커 라인 뒤**에 선다 — 지금 보고 있는 라인이 앵커면 진행 대신 지점을 연다.
	if _try_open_choice():
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
	# 선택 대기 중 스킵 = **선택 없이 종료.** 반응 라인은 재생하지 않고 의사도 기록하지
	# 않는다 — 고르지 않은 것을 1번으로 적으면 "선택했다"는 상태가 거짓으로 생긴다.
	_close_choice()
	if not _replay and not vn_id.is_empty():
		session.narrative.vn_skipped[vn_id] = true
	if _calendar_pending and not (%CalendarPanel as Control).visible:
		# 스킵해도 캘린더 공개는 건너뛰지 않는다 — 시즌 구조 정보는 서사가 아니라 판단 재료다
		_show_calendar()
		return
	_finish()


func _finish() -> void:
	go(_next_route, _next_payload)
