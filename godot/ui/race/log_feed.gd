# RACE-01 E10 — 로그 피드 존 (D09 §3.3).
#
# 슬롯 스택: 최신 하단 유입 · 최고 상단 소멸 · 동시 표시 상한은 D09 확정 기준값(4).
# **[데스크탑] 시각 줄 2 물리 고정** (D09 §7.3 §8-4 표시 층) — 작성 층 자수 규격(전각 22자)은
# V3가 스트링 단계에서 차단하므로 여기서는 시각 줄만 고정한다.
#
# 백로그(히스토리 열람)는 1차 미탑재 확정 (D09 §3.3 결정 #6) — 스크롤 요소를 두지 않는다.
#
# **R2 이행 (D09 §7.1):** 로그 피드에 릴 상태 아이콘·릴 참조 표식을 두지 않는다.
# 베인 발화는 이 존에 들어오지 않는다 — 릴 존 콜아웃 전속(D09 §3.1)이므로 호출 층이 갈라 넣는다.
extends VBoxContainer

const VISUAL_LINES := 2  # [데스크탑] 물리 고정 — D09 §7.3

# 화자 구분 (D09 §3.3) — 도상 위계: 크루 초상 > 네임드 카 넘버 배지 > 공용 헬멧.
# 아이콘 실물은 D10(A-UI아이콘) 유입 대상이라 지금은 자리만 잡고 라벨로 대체한다.
enum Speaker { RELAY, CREW, RIVAL, FILLER }

var slot_cap := 4
var _slots: Array[Control] = []
var _font_size := 8


func configure(cap: int, font_size: int) -> void:
	slot_cap = cap
	_font_size = font_size


func push_line(speaker_mark: String, body: String) -> void:
	var slot := _build_slot(speaker_mark, body)
	add_child(slot)
	_slots.append(slot)
	while _slots.size() > slot_cap:
		var oldest: Control = _slots.pop_front()
		remove_child(oldest)
		oldest.queue_free()


func clear_feed() -> void:
	for slot in _slots:
		remove_child(slot)
		slot.queue_free()
	_slots.clear()


func _build_slot(speaker_mark: String, body: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)

	# 화자 표지 자리 — 도상 유입 시 TextureRect로 교체된다(요소 폭 불변).
	var mark := Label.new()
	mark.text = speaker_mark
	mark.custom_minimum_size = Vector2(26, 0)
	mark.add_theme_font_size_override("font_size", _font_size)
	mark.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	row.add_child(mark)

	var text := Label.new()
	text.text = body
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.max_lines_visible = VISUAL_LINES
	text.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	text.add_theme_font_size_override("font_size", _font_size)
	text.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	row.add_child(text)
	return row
