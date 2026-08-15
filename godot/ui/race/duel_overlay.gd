# RACE-02 듀얼 오버레이 — D09 §3.5 · 별첨A §A-7.
#
# **화면 전환이 아니다**: 레이스 화면 위 주변 감광 + 중앙 듀얼 프레임. 배경의 레이스 스트립·
# 자원 바는 시인 유지된다(판단 재료 상실 없음). D05 §3 상태 머신의 DUEL 삽입·복귀와 1:1이며
# 라우터 경로에 넣지 않는다 — RACE-01이 직접 띄우고 내린다.
#
# 듀얼 전용 스핀(IMPL-009 — 판정 환산 전속)의 릴 3기는 프레임 안에 있다. 릴 표시 배열은
# RACE-01이 듀얼 중 이쪽으로 스왑하므로 **봉인 규칙·SEAL-E 검사가 그대로 이 릴을 본다.**
#
# 확률·기대치·예측 표기는 어떤 형태로도 두지 않는다 (R1 — D09 §7.1).
extends Control

var _icons: Array[TextureRect] = []
var _strings: StringTable

@onready var _opponent_label: Label = %OpponentLabel
@onready var _player_label: Label = %PlayerLabel
@onready var _boost_stack: Label = %BoostStack
@onready var _boost_button: Button = %BoostButton
@onready var _result_label: Label = %ResultLabel


func _ready() -> void:
	for i in range(3):
		_icons.append(get_node("%%DuelReel%d" % i) as TextureRect)


func reel_icons() -> Array[TextureRect]:
	return _icons


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
	(%KindLabel as Label).text = strings.text(kind_key)
	_boost_button.text = strings.text("ui.duel.boost")
	_result_label.text = ""
	_result_label.visible = false
	visible = true


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


# 결과를 프레임 내 표기 후 해제한다 (D09 §3.5 — 해제 후 전개 국면의 중계 로그로 번역).
func show_result(text: String) -> void:
	_result_label.text = text
	_result_label.visible = true


func dismiss() -> void:
	visible = false
