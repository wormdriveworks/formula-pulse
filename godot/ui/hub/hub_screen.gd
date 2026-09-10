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
		(back as Button).pressed.connect(_return_to_garage)


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
	_return_to_garage()


# ── 개러지 복귀 자동 저장 (개선 회차 17 · 2026-09-11 사용자 요청) ──
#
# 하위 스테이션(HUB-02~07)에서 한 작업 — 정비·소모품·튜닝·덱 편성·스폰서 체결·시설 확장 — 은
# 종전에 **"다음 대회 출발"(개러지 E09)까지 디스크에 닿지 않았다.** 개러지 도착은 저장 지점이
# 아니고(D09 §2.4 대장 = RACE-03·투어 경계·시즌 경계·출발 전), 스테이션에서 돌아온 자리는
# 게임을 끄기 자연스러운 정지점이다 — 그 회차의 아웃게임 작업이 통째로 사라진다.
# 회차 15 의 시즌 엔딩 소실과 같은 형태의 창이다(그때는 VN 발생 기록·여기는 아웃게임 상태).
#
# **저장 시점은 나가는 쪽이다.** 개러지 도착(`_on_hub_ready`)에 두면 레이스·이벤트·시즌 체인에서
# 들어온 도착까지 함께 저장하는데, 그 경로들은 이미 자기 저장 지점을 지나온 뒤라 같은 상태를 두 번
# 쓴다. 스테이션을 떠나는 자리는 "작업이 끝난 지점"과 정확히 겹친다 — 뒤로 버튼과 Esc·패드 B 가
# 여기 모인다.
func _return_to_garage() -> void:
	if _saves_on_return() and session != null:
		var saved := session.save_progress()
		if not bool(saved.get("ok", false)):
			# 조용한 실패는 "작업이 남았다"는 오인을 낳는다 — 저장 표시(app_root)도 실패에는 뜨지 않는다.
			push_error("HubScreen: return autosave failed - %s" % String(saved.get("error", "")))
	go("HUB-01", {})


# 복귀 저장 대상인가 — 개러지 자신은 돌아올 자리가 아니므로 재정의로 끈다.
func _saves_on_return() -> bool:
	return true


# 재화 갱신 — 구매 후 호출 (증감 피드백 규격의 최소형. 플로트·펄스는 아트 유입 시)
func refresh_currency() -> void:
	var s := session.data.strings
	var credit_text := s.text("ui.hub.amountFormat", {"amount": session.outgame.credits})
	var data_text := s.text("ui.hub.amountFormat", {"amount": session.outgame.drive_data})
	(%CreditValue as Label).text = credit_text
	(%DataValue as Label).text = data_text
