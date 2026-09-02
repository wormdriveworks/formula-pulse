# HUB 화면 공통 베이스 (D09 별첨A 공통 상속 조항).
#
# 전 HUB·SET 화면은 상단 공통 바를 상속한다 — 재화 2종(아이콘+수치) / 시즌·투어 진행 / 다음 일정.
# **B-1 (절대 규격):** UI 약칭 '데이터'는 반드시 재화 아이콘을 동반한다 (D09 §5.2) —
# 그래서 공통 바의 재화는 라벨이 아니라 아이콘+수치다.
#
# 개별 HUB 화면은 `_on_hub_ready()` 를 구현하고, 뒤로 가기는 공통으로 HUB-01로 돌린다.
class_name HubScreen
extends FlowScreen

const ICON_DIR := "res://assets/ui/icons/"


func _on_bound(payload: Dictionary) -> void:
	_fill_common_bar()
	_on_hub_ready(payload)


func _on_hub_ready(_payload: Dictionary) -> void:
	pass


# 정거장 진입음 (SE-U06). HUB-01 은 차고 자체라 진입음이 아니라 BGM·룸톤이므로 재정의한다.
func _audio_enter_events() -> Array:
	return ["station_enter"]


func _fill_common_bar() -> void:
	var bar := get_node_or_null("%CommonBar")
	if bar == null:
		return
	var s := session.data.strings
	(%CreditIcon as TextureRect).texture = load(ICON_DIR + "currency_credit_16.png")
	(%DataIcon as TextureRect).texture = load(ICON_DIR + "currency_data_16.png")
	# 재화 수치 = 대형·VN 계열 (D10 v1.1 §5.7 — 결정 #8). 아이콘 병기 상시 표기라
	# 아이콘 대비 판독 균형이 요구되는 지점이다. 씬의 리터럴을 런타임에 덮는다 —
	# 계열 값의 창구는 D13(param_font_size_head)이고 씬에 수치를 굳히지 않는다(불변규칙 2).
	# **편입 범위 = 재화 2종 수치 한정.** ProgressLabel(시즌·투어·다음 일정)은 본문 계열 유지.
	(%CreditValue as Label).add_theme_font_size_override("font_size", _head_font_size)
	(%DataValue as Label).add_theme_font_size_override("font_size", _head_font_size)
	var credit_text := s.text("ui.hub.amountFormat", {"amount": session.outgame.credits})
	var data_text := s.text("ui.hub.amountFormat", {"amount": session.outgame.drive_data})
	(%CreditValue as Label).text = credit_text
	(%DataValue as Label).text = data_text
	var progress_text := s.text("ui.hub.progressFormat", {
		"season": session.season.season,
		"tour": session.season.tour_slot,
		"race": session.season.race_slot,
	})
	# 시즌 마감 상태(SET-02 → HUB-08 체인)는 tour_slot 이 상한을 넘어 '투어 6 · 제5전' 으로 읽혔다
	# (개선 회차 4 H8-O1 실측). 마감 문면으로 갈음한다 — 다음 시즌 개시(`begin_next_season`) 뒤에는 종전 문면.
	if session.season.season_finished():
		progress_text = s.text("ui.hub.progressClosedFormat", {"season": session.season.season})
	(%ProgressLabel as Label).text = progress_text
	var back := get_node_or_null("%BackButton")
	if back != null:
		(back as Button).text = s.text("ui.hub.back")
		# 뒤로 가기는 결정음이 아니라 취소음이다 (SE-U03). 조작음 자동 결속이 이 메타를 읽는다.
		(back as Button).set_meta(AUDIO_EVENT_META, "ui_cancel")
		(back as Button).pressed.connect(func(): go("HUB-01", {}))


# 취소 / 뒤로 = Esc · 패드 B (D09 §1.3 공통 층 매핑 — 개선 2026-09-02 H7 결선).
# 실기: 허브 7화면 전부 Esc·B 가 무반응이었다 — 버튼 포커스 없이는 나갈 수 없었다.
# 뒤로 버튼이 없거나(개러지) 숨겨진 화면(시즌 체인의 오버홀 — 1회 전용 진입 보호)은 그대로 무동작.
# 모달(ConfirmDialog)이 떠 있으면 창이 먼저 소비한다(창 쪽 _unhandled_input) — 여기 오지 않는다.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	var back := get_node_or_null("%BackButton") as Button
	if back == null or not back.visible:
		return
	get_viewport().set_input_as_handled()
	sfx("ui_cancel")   # SE-U03 — 버튼 경로의 취소음 결속과 같은 축
	go("HUB-01", {})


# 재화 갱신 — 구매 후 호출 (증감 피드백 규격의 최소형. 플로트·펄스는 아트 유입 시)
func refresh_currency() -> void:
	var s := session.data.strings
	var credit_text := s.text("ui.hub.amountFormat", {"amount": session.outgame.credits})
	var data_text := s.text("ui.hub.amountFormat", {"amount": session.outgame.drive_data})
	(%CreditValue as Label).text = credit_text
	(%DataValue as Label).text = data_text
