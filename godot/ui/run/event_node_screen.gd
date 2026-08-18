# RUN-02 이벤트 노드 화면 — D09 §5.4 · 별첨A §A-10.
#
# 경량 중앙 단일 패널: 이벤트 텍스트 + 선택지 0~2(대괄호·14자) + 결과 피드백 행.
# 연출 L0~L1 한정 (D08 §7.1) — 셰이크·플래시 채널을 쓰지 않는다.
# **무발생 시 이 화면 자체가 비표출**이다 — 발생 판정은 RACE-03 이탈 시점에 세션이 하고,
# 미발생이면 라우터가 RUN-01 로 직행하므로 여기 도달 = 발생 확정.
#
# 선택지 실문안·분기 데이터는 D04 텍스트 풀 트랙 소관 — 골격은 단일 [계속] 경로다.
# 이벤트 변형(4축)·보상은 코어가 판정을 끝냈고 화면은 결과만 번역한다.
extends FlowScreen

const ICON_DIR := "res://assets/ui/icons/"


func _on_bound(payload: Dictionary) -> void:
	var s := session.data.strings
	var occurrence: Dictionary = payload.get("occurrence", {})
	if occurrence.is_empty():
		# 방어 — 무발생인데 도달했다면 판정·라우팅 어느 쪽이 깨진 것이다
		push_error("EventNodeScreen: reached without an occurrence")
		go("RUN-01", {})
		return

	var title_key := String(occurrence.get("name_key", ""))
	var title_text := s.text(title_key)
	(%TitleLabel as Label).text = title_text
	# 변형 문면 — 변형이 있으면 변형 키, 없으면 본문 없음 (실문안 D04 트랙)
	var variant: Dictionary = occurrence.get("variant", {})
	var body := %BodyLabel as Label
	if variant.has("name_key"):
		body.text = s.text(String(variant["name_key"]))
		body.visible = true
	else:
		body.visible = false

	_show_reward(occurrence.get("reward", {}))
	var proceed := %ProceedButton as Button
	proceed.text = s.text("ui.eventNode.proceed")
	proceed.pressed.connect(_on_proceed.bind(occurrence))
	proceed.grab_focus()  # 무선택지 시 초기 포커스 = [계속] (§A-10)


# 결과 피드백 행 — 재화 증감 문법 (D09 §5.2: 아이콘 + 증감)
func _show_reward(reward: Dictionary) -> void:
	var s := session.data.strings
	var row := %RewardRow as Control
	var reward_type := String(reward.get("type", "none"))
	var amount := int(reward.get("amount", 0))
	if reward_type == "none" or amount == 0:
		row.visible = false
		return
	row.visible = true
	var icon := %RewardIcon as TextureRect
	match reward_type:
		"credit":
			icon.texture = load(ICON_DIR + "currency_credit_16.png")
		"dp":
			icon.texture = load(ICON_DIR + "currency_data_16.png")
		_:
			icon.texture = null
	var reward_key := "ui.eventNode.rewardChassisFormat" if reward_type == "chassis" \
		else "ui.eventNode.rewardFormat"
	var reward_text := s.text(reward_key, {"amount": amount})
	(%RewardValue as Label).text = reward_text
	(%RareBadge as Label).visible = bool(reward.get("rare", false))
	(%RareBadge as Label).text = s.text("ui.eventNode.rare")


func _on_proceed(occurrence: Dictionary) -> void:
	session.apply_event_reward(occurrence.get("reward", {}))
	go("RUN-01", {})
