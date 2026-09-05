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
class_name LogFeed
extends VBoxContainer

const VISUAL_LINES := 2  # [데스크탑] 물리 고정 — D09 §7.3

# 화자 구분 (D09 §3.3) — 도상 위계: 크루 초상 > 네임드 카 넘버 배지 > 필러 카 넘버(텍스트).
# 필러의 공용 헬멧 도상은 **배지 없는 라이벌 id** 의 되돌림으로만 남는다 (개선 회차 7 — 2026-09-05 · 사용자
# 선택: 헬멧만으로는 로그 이력에서 상대가 누구였는지 남지 않아, 네임드 배지와 같은 '번호' 축으로 필러도
# 카 넘버를 표지로 쓴다 — 호출부가 `speaker_mark` 에 넘버를 싣는다).
enum Speaker { RELAY, CREW, RIVAL, FILLER }

const ICON_DIR := "res://assets/ui/icons/"

# 화자 → 도상. 크루 초상(`speaker_crew_16`)과 네임드 배지(`speaker_rival_<id>_16` 8종)는 에셋 유입으로
# 실물이 섰다(개선 회차 6 결선). 라이벌은 개인 배지라 표가 아니라 `_speaker_asset()` 이 id 로 고른다.
# 표에 없는 화자(필러 = 카 넘버 · 미지정)는 텍스트 표지로 간다.
const ICON_BY_SPEAKER := {
	Speaker.RELAY: "speaker_relay_16",
	Speaker.CREW: "speaker_crew_16",
}

# 배지 없는 라이벌 id 의 되돌림 도상 — 빈 표지보다 공용 도상이 열 정렬을 지킨다.
const FALLBACK_BADGE := "speaker_filler_16"

# 도상 미지정 — 텍스트 표지 경로. 기본값을 특정 화자로 두면 새 호출부가 조용히
# 남의 도상을 달고 나온다(RELAY 를 기본으로 두면 전 화자가 마이크가 된다).
const SPEAKER_NONE := -1

# **16px 원도 세트 등배** (대장 §4.1.1). 32px 는 9px 2줄 슬롯보다 커서 피드 행간이
# 벌어졌다(7차 §6-③) — 16px 원도 유입으로 해소한다. 축소가 아니라 원도 교체다.
# 표지 칸은 도상·텍스트 공통 폭이다 — 갈라 두면 본문 시작 x 가 어긋나 피드가 들쭉날쭉해진다.
const MARK_SLOT := 16

# 폰트 크기는 **구성 전에는 값이 없다** (총괄 판정 IMPL-176 ④ — FONT-B 와 같은 축).
# 리터럴 초기값(구 8)을 두면 `configure()` 미호출 경로가 생겼을 때 D13 창구 밖의 수치가
# **조용히 실렌더된다** — 화면은 뜨고 글자만 미묘하게 다르므로 눈으로는 잡히지 않는다.
# 미구성은 기본값이 아니라 오류 상태로 다룬다: 센티넬을 두고 소비 지점에서 보고 후 중단한다.
const UNCONFIGURED := -1

var slot_cap := 4
var _slots: Array[Control] = []
var _font_size := UNCONFIGURED


func configure(cap: int, font_size: int) -> void:
	slot_cap = cap
	_font_size = font_size


func push_line(speaker_mark: String, body: String, speaker: int = SPEAKER_NONE,
		speaker_id: String = "") -> void:
	var slot := _build_slot(speaker_mark, body, speaker, speaker_id)
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


func _build_slot(speaker_mark: String, body: String, speaker: int = SPEAKER_NONE,
		speaker_id: String = "") -> Control:
	if _font_size == UNCONFIGURED:
		# 값 누락은 "중단·보고" 사안이다 (불변규칙 2) — 임의 대체값으로 그리지 않는다.
		push_error("LogFeed: configure() not called — font size must come from D13 (param_font_size_body)")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.add_child(_build_mark(speaker_mark, speaker, speaker_id))

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


# 화자 표지 1칸 — 도상이 있으면 도상, 없으면 텍스트.
#
# **텍스트 경로는 되돌림이 아니라 정규 경로다:** 필러 화자의 표지가 카 넘버 텍스트다(개선 회차 7).
# 도상 적재가 실패한 화자도 같은 자리로 떨어진다 — 빈 칸으로 조용히 나가지 않게.
# 화자 → 도상 id. 라이벌은 **개인 배지**이고, 배지가 없는 라이벌 id 는 공용 헬멧으로 되돌아간다.
func _speaker_asset(speaker: int, speaker_id: String) -> String:
	if speaker == Speaker.RIVAL:
		if not speaker_id.is_empty():
			var badge := "speaker_rival_%s_16" % speaker_id
			if ResourceLoader.exists("%s%s.png" % [ICON_DIR, badge]):
				return badge
		return FALLBACK_BADGE
	return String(ICON_BY_SPEAKER.get(speaker, ""))


func _build_mark(speaker_mark: String, speaker: int, speaker_id: String = "") -> Control:
	var asset_id := _speaker_asset(speaker, speaker_id)
	if not asset_id.is_empty():
		var path := "%s%s.png" % [ICON_DIR, asset_id]
		if ResourceLoader.exists(path):
			var icon := TextureRect.new()
			icon.name = "Mark"
			icon.custom_minimum_size = Vector2(MARK_SLOT, MARK_SLOT)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			icon.texture = load(path) as Texture2D
			return icon
		# 진단 문자열은 영문 — V4 는 한글 리터럴을 경로 불문 차단한다
		push_error("LogFeed: speaker icon missing - %s" % path)
	var mark := Label.new()
	mark.name = "Mark"
	mark.text = speaker_mark
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER   # 카 넘버(1~2자리)가 도상 칸 가운데에 선다
	mark.custom_minimum_size = Vector2(MARK_SLOT, 0)
	mark.add_theme_font_size_override("font_size", _font_size)
	mark.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	return mark
