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


func _fill_common_bar() -> void:
	var bar := get_node_or_null("%CommonBar")
	if bar == null:
		return
	var s := session.data.strings
	(%CreditIcon as TextureRect).texture = load(ICON_DIR + "currency_credit.png")
	(%DataIcon as TextureRect).texture = load(ICON_DIR + "currency_data.png")
	# 재화 수치 = 대형·VN 계열 (D10 v1.1 §5.7 — 결정 #8). 아이콘 병기 상시 표기라
	# 아이콘 대비 판독 균형이 요구되는 지점이다. 씬의 리터럴을 런타임에 덮는다 —
	# 계열 값의 창구는 D13(param_font_size_head)이고 씬에 수치를 굳히지 않는다(불변규칙 2).
	# **편입 범위 = 재화 2종 수치 한정.** ProgressLabel(시즌·투어·다음 일정)은 본문 계열 유지.
	var head_size := int(session.data.param("param_font_size_head"))
	(%CreditValue as Label).add_theme_font_size_override("font_size", head_size)
	(%DataValue as Label).add_theme_font_size_override("font_size", head_size)
	var credit_text := s.text("ui.hub.amountFormat", {"amount": session.outgame.credits})
	var data_text := s.text("ui.hub.amountFormat", {"amount": session.outgame.drive_data})
	(%CreditValue as Label).text = credit_text
	(%DataValue as Label).text = data_text
	var progress_text := s.text("ui.hub.progressFormat", {
		"season": session.season.season,
		"tour": session.season.tour_slot,
		"race": session.season.race_slot,
	})
	(%ProgressLabel as Label).text = progress_text
	var back := get_node_or_null("%BackButton")
	if back != null:
		(back as Button).text = s.text("ui.hub.back")
		(back as Button).pressed.connect(func(): go("HUB-01", {}))


# 재화 갱신 — 구매 후 호출 (증감 피드백 규격의 최소형. 플로트·펄스는 아트 유입 시)
func refresh_currency() -> void:
	var s := session.data.strings
	var credit_text := s.text("ui.hub.amountFormat", {"amount": session.outgame.credits})
	var data_text := s.text("ui.hub.amountFormat", {"amount": session.outgame.drive_data})
	(%CreditValue as Label).text = credit_text
	(%DataValue as Label).text = data_text
