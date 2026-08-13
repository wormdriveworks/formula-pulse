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
