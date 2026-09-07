# RACE-02 듀얼 표시 — D09 §3.5 · 별첨A §A-7 (개선 회차 9 · 2026-09-08 재배치).
#
# **화면 전환이 아니다**: 레이스 화면 위에 얹히는 표시 층이다. D05 §3 상태 머신의 DUEL 삽입·복귀와
# 1:1이며 라우터 경로에 넣지 않는다 — RACE-01이 직접 띄우고 내린다.
#
# **회차 9 재배치 (사용자 결정).** 종전 '전면 감광 + 중앙 프레임(전용 릴 3기)' 모달은 조작 버튼(홀드·리스핀·
# 스킬·차지 개입·확정)을 전부 감광판 뒤에 남겨 마우스로는 아무것도 할 수 없었고(감광판 mouse_filter STOP),
# 프레임도 앵커 0.5·오프셋 0 결함으로 좌상단 모서리가 화면 중심에 걸려 우하단에 흘러 있었다. 지금은
#   ⓐ 감광판 없음 · 루트와 띠는 mouse_filter IGNORE — 포인터를 받는 것은 부스트 버튼 하나다
#   ⓑ 듀얼 스핀은 **기본 릴 프레임 그 자리**에서 돈다 — 전용 릴을 두지 않으므로 표시 배열 스왑도 없다.
#      RACE-01 이 프레임 테두리를 듀얼색으로 바꾸고(`_refresh_reel_frames`), 홀드 1~3 은 그대로 살아 있다
#   ⓒ 대치 표기(No.13 ↔ 상대)·부스트·판정 결과는 **씬 패널 하단 캡션 띠** 하나에 든다 — 씬 패널은
#      비인터랙티브라 무엇을 덮어도 조작을 막지 않고, 릴 존의 세로 예산(O6 타이머 수치·SH3 스냅숏 행이
#      스페이서를 먹는다)과 무관하게 자리가 늘 있다. 띠의 자리는 호출 층이 씬 패널의 **실 rect** 를 넘겨
#      정한다(`place_over`) — 앵커가 아니라 정렬이 끝난 rect 라 배치가 레이아웃 비율에 묶이지 않는다.
#
# 확률·기대치·예측 표기는 어떤 형태로도 두지 않는다 (R1 — D09 §7.1).
extends Control

var _strings: StringTable
var _host: Control = null   # 캡션 띠를 얹을 영역의 실물 — 씬 패널 호스트 (호출 층이 넘긴다)

@onready var _bar: PanelContainer = %DuelBar
@onready var _player_label: Label = %PlayerLabel
@onready var _kind_label: Label = %KindLabel
@onready var _opponent_label: Label = %OpponentLabel
@onready var _boost_stack: Label = %BoostStack
@onready var _boost_button: Button = %BoostButton
@onready var _result_label: Label = %ResultLabel


func _ready() -> void:
	# 내용이 바뀌면(대치 ↔ 결과 · 문면 길이) 띠의 높이·폭 요구가 바뀐다 — 그때마다 다시 앉힌다.
	_bar.minimum_size_changed.connect(_place_bar)


# 캡션 띠의 자리 — 호스트 영역의 **하단에 폭 전체**로 붙는다 (릴 바로 위: 대치 → 릴 → 홀드 → 액션이 한 덩이로
# 읽힌다). rect 스냅숏이 아니라 **노드를 따라간다**: 호스트의 rect 가 바뀌면(정렬 완료·재배치) 함께 움직인다 —
# 스냅숏으로 두면 정렬 전에 불린 호출이 0 폭 rect 를 박제한다(하네스 실측: 띠가 내용 폭 326·y 100 에 남았다).
func place_over(host: Control) -> void:
	if _host != host:
		if _host != null and _host.item_rect_changed.is_connected(_place_bar):
			_host.item_rect_changed.disconnect(_place_bar)
		_host = host
		if _host != null:
			_host.item_rect_changed.connect(_place_bar)
	_place_bar()


func _place_bar() -> void:
	if _bar == null or _host == null:
		return
	var strip := _host.get_global_rect()
	if strip.size == Vector2.ZERO:
		return
	var height := _bar.get_combined_minimum_size().y
	_bar.size = Vector2(strip.size.x, height)
	_bar.position = Vector2(strip.position.x, strip.end.y - height) - global_position


# 대치 표기 — No.13(플레이어 — D03 §1.1 데칼) ↔ 상대 "No.{넘버} {이름}" (§A-7 E01 "No.1 로렌츠").
# 네임드 카 넘버는 D03 결정 로그 #13-③ 확정값의 데이터 전사(IMPL-092)로 결선됐다.
# 네임드 초상 미니(E01 잔여)는 아트 실물 유입 대상 — 주력 레인 몫.
func show_duel(strings: StringTable, opponent: Dictionary, duel_type: int) -> void:
	_strings = strings
	var player_text := strings.text("ui.duel.playerFormat", {"number": 13})
	_player_label.text = player_text
	var opponent_name := ""
	if bool(opponent["is_filler"]):
		opponent_name = strings.text(String(opponent["name_key"]), {
			"number": int(opponent["number"]),
		})
	else:
		opponent_name = strings.text("ui.duel.namedFormat", {
			"number": int(opponent["number"]),
			"name": strings.text(String(opponent["name_key"])),
		})
	_opponent_label.text = opponent_name
	var kind_key := "ui.duel.overtake" if duel_type == RaceTypes.DuelType.OVERTAKE else "ui.duel.defense"
	_kind_label.text = strings.text(kind_key)
	_boost_button.text = strings.text("ui.duel.boost")
	_result_label.text = ""
	_set_result_mode(false)
	visible = true
	_place_bar()


# ◆/◇ 도 스트링 키 경유다 (V4 — 전 표시 문자열 키 참조 · ui.race.costFormat "◆{cost}" 전례)
func set_boost(count: int, cap: int, can_add: bool) -> void:
	var filled := _strings.text("ui.duel.boostFilled")
	var empty := _strings.text("ui.duel.boostEmpty")
	var stack := ""
	for i in range(cap):
		stack += filled if i < count else empty
	_boost_stack.text = stack
	_boost_button.disabled = not can_add


func boost_pressed_signal() -> Signal:
	return _boost_button.pressed


# 결과를 띠에 표기한 뒤 해제한다 (D09 §3.5 — 해제 후 전개 국면의 중계 로그로 번역).
func show_result(text: String) -> void:
	_result_label.text = text
	_set_result_mode(true)
	_place_bar()


func dismiss() -> void:
	visible = false


# 결과 국면 — 대치·부스트를 내리고 결과 한 줄만 띠에 남긴다. 같은 띠·같은 자리라 시선이 옮겨 가지 않는다.
func _set_result_mode(on: bool) -> void:
	_player_label.visible = not on
	_kind_label.visible = not on
	_opponent_label.visible = not on
	_boost_stack.visible = not on
	_boost_button.visible = not on
	_result_label.visible = on
