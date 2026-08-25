# 씬 컷 매핑 (D12 §5.9 · D09 §3.1.1 · D13 별첨A §8.2 우선순위).
#
# **왜 코어에 순수 함수로 두는가.** 매핑은 *확정 결과 → 상황*이고 화면 상태를 타지 않는다.
# 화면 안에 두면 무대 5·트러블·리타이어처럼 실기로 밟기 어려운 경로가 검사에서 빠진다
# (`l3_encounter_for` 3종을 정적 함수로 둔 것과 같은 사유 — 21차 계보).
#
# **봉인 (불변규칙 5 · 사양서 §5.2.2).** 이 함수는 *무엇이 확정됐는가*를 입력으로 받는다 —
# 확정 전에 부르면 그 자체가 누설이다. 호출부는 T5 이후에만 부른다(`_run_presentation` 과
# 같은 자리). **릴 국면에는 이 함수를 부르지 않고 기본 주행 컷으로 고정한다** — "고정"이
# 데이터 조회가 아니라 **경로 부재**인 것이 봉인의 구조적 보장이다.
class_name SceneCutMap
extends RefCounted

# 릴 국면(T1~T4) 고정 컷 — D09 §3.1.1 "기본 주행 루프 고정 + 저강조".
# 단독/그룹은 **필드 상황**이 가르므로 여기서 고르지 않는다(`resolve` 의 group_field 와 같은 판정).
const REEL_PHASE_SOLO := "cut_basic_solo"
const REEL_PHASE_GROUP := "cut_basic_group"

# 미배정 컷을 가려내는 우선순위 값. D13 §8.2 대장은 **7단**을 선언하고 그 밖의 컷을 세지
# 않으므로, 대장에 자리가 없는 컷은 0 으로 선언해 **평가 대상에서 구조적으로 빠진다.**
# 임의 순위를 부여하면 정본이 정하지 않은 서열이 코드로 굳는다(불변규칙 2·9).
const UNASSIGNED_PRIORITY := 0

var data: GameData


func setup(game_data: GameData) -> void:
	data = game_data


# 확정 결과 → 상황 컷.
#
# `context` = {
#   "log_keys": Array[String]   확정이 발행한 로그 키 (T5 이벤트)
#   "duel_turn": bool           이 턴이 듀얼 턴이었는가 (D09 §3.5 대치 고정)
#   "front_gauge": float, "rear_gauge": float
#   "gp_finished": bool
#   "field_size": int           같은 화면에 서는 머신 수 (단독/그룹 판정)
# }
#
# 반환 = 컷 id. **폴백이 데이터에 있으므로 빈 문자열을 돌려주지 않는다** — 코드가 기본값을
# 들고 있으면 표에서 폴백 행이 사라져도 화면이 멀쩡해 보이고, 그 순간 표는 거짓이 된다.
func resolve(context: Dictionary) -> String:
	var best := ""
	var best_priority := 99
	for trigger in data.scene_cut_triggers:
		if not _matches(trigger, context):
			continue
		var cut_id := String(trigger["cut_id"])
		var cut := data.scene_cut(cut_id)
		var priority := CsvTable.to_int(String(cut.get("priority", "0")))
		if priority <= UNASSIGNED_PRIORITY:
			continue      # 정본 대장에 자리가 없는 컷 — 평가하지 않는다
		if priority < best_priority:
			best_priority = priority
			best = cut_id
	return best


# 릴 국면 고정 컷 — 필드 상황만 본다. **확정 결과를 보지 않는 것이 요건이다**(봉인).
func reel_phase_cut(field_size: int) -> String:
	return REEL_PHASE_GROUP if field_size >= _group_threshold() else REEL_PHASE_SOLO


# 그룹 판정 문턱 = **그룹 컷이 선언한 머신 수**. 코드에 2 를 적지 않는다 —
# 표가 "그룹은 머신 3대"라고 말하면 그 3이 곧 문턱이다.
func _group_threshold() -> int:
	return CsvTable.to_int(String(data.scene_cut(REEL_PHASE_GROUP).get("machines", "2")))


func _matches(trigger: Dictionary, context: Dictionary) -> bool:
	match String(trigger.get("match_kind", "")):
		"duel_turn":
			return bool(context.get("duel_turn", false))
		"log_event":
			return Array(context.get("log_keys", [])).has(String(trigger.get("log_key", "")))
		"close_gauge":
			# 접전 판정 임계 = 전방 **또는** 후방 게이지 ≥ 70G (D13 별첨A §8.1).
			var threshold := data.param("param_closerace_gauge_threshold")
			return float(context.get("front_gauge", 0.0)) >= threshold \
				or float(context.get("rear_gauge", 0.0)) >= threshold
		"gp_finish":
			return bool(context.get("gp_finished", false))
		"group_field":
			return int(context.get("field_size", 1)) >= _group_threshold()
		"fallback":
			return true
	return false
