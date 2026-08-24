# 서사 층 (D04 · D07 §5.5·§6.3 · D08 §8.4 · D12 §5.7) — VN 슬롯 · 베인 대사 3단계 필터 ·
# 형식 A 관계 전이 · 아카이브 재열람.
#
# 핵심 구속 두 개가 서로 맞물린다:
#  ①**스킵은 관계 진행의 페널티가 아니다** — 형식 A 전이는 VN의 '발생(도달)' 기준이며 열람 여부를
#    조건으로 삼지 않는다. 스킵이 진행을 막으면 비강제성(D01 §4 G2 조건 2)이 역전된다.
#  ②**아카이브 재열람은 전이를 재발화하지 않는다** — 전진형 정합. 이벤트 id당 1회 소비 멱등 플래그.
# 둘을 같은 자리에서 구현하는 이유: 하나만 지키면 다른 하나가 깨진다.
# (발생 기준만 두고 멱등이 없으면 재열람이 카운터를 밀어 올리고, 멱등만 두고 열람 기준을 쓰면
#  스킵한 플레이어가 영구히 전이를 못 받는다.)
class_name NarrativeService
extends RefCounted

var data: GameData

var vn_seen: Dictionary = {}          # vn id -> true (발생 = 도달. 열람 여부와 무관)
var vn_skipped: Dictionary = {}       # vn id -> true (기록용 — 전이 판정에 쓰지 않는다)
var _transitions_fired: Dictionary = {}  # vn id -> true (형식 A 멱등 플래그)
var season_vn_count: int = 0
var milestone_vn_count: int = 0


func setup(game_data: GameData) -> void:
	data = game_data


func begin_season() -> void:
	season_vn_count = 0
	milestone_vn_count = 0


# ── VN 발생 (D08 §8.4 슬롯 밀도·상한) ──
# 반환: {"occurred": bool, "reason": String, "relation": String}
#
# **이월 문면의 범위 교정 (24차 — 문면 대조).** 이전 주석은 *"상한 초과분은 차기 경계로
# 이월된다 (D08 §8.4 잔여분 이월 명문)"* 였는데, 정본 문면은 그 범위가 아니다:
#
#   "동일 투어 경계에 마일스톤 VN이 2건 이상 몰릴 경우 우선순위: 막 전이 > 크루 합류 >
#    기원 단서 > 일반 성취 (확정) — **잔여분은 차기 경계로 이월**."
#
# 즉 이월은 **한 투어 경계에서 우선순위 경합에 밀린 마일스톤 VN**의 처리 규칙이고,
# **시즌 상한 초과분에 대한 규칙이 아니다.** 시즌 상한 초과의 이월 기제는 정본이 침묵한다 —
# 임의로 세우지 않는다(불변규칙 9). 상한에 걸린 발화는 그 자리에서 미발생이다.
#
# 그리고 정본의 이월 규칙은 **아직 적용 대상이 없다**: 마일스톤 VN 발화 경로가 미결선이라
# 한 경계에 2건이 몰릴 수 없다(대기열도 우선순위도 실행되지 않는다). 발화가 서면 함께 온다.
func trigger_vn(vn_id: String, slot_id: String, skipped: bool) -> Dictionary:
	var slot := data.vn_slot(slot_id)
	if slot.is_empty():
		return {"occurred": false, "reason": "unknown_slot", "relation": ""}
	if season_vn_count >= data.param_int("param_vn_season_cap"):
		return {"occurred": false, "reason": "season_cap", "relation": ""}
	if String(slot["slot_kind"]) == "tour_close":
		if milestone_vn_count >= data.param_int("param_vn_milestone_cap"):
			return {"occurred": false, "reason": "milestone_cap", "relation": ""}
		milestone_vn_count += 1
	season_vn_count += 1
	# **발생 = 도달.** 스킵 여부는 기록만 하고 전이 판정에 쓰지 않는다.
	vn_seen[vn_id] = true
	if skipped:
		vn_skipped[vn_id] = true
	return {"occurred": true, "reason": "", "relation": _consume_transition(vn_id)}


# 형식 A 전이 — 이벤트 id당 1회만 소비한다 (재열람 재발화 없음)
func _consume_transition(vn_id: String) -> String:
	if _transitions_fired.has(vn_id):
		return ""
	# **분류 한 겹을 거친다** (총괄 판정 ① B안). 재발화 가드는 `vn_id` 단위로 유지하고
	# 조회만 분류로 돌린다 — 그래야 같은 분류의 N 건이 각자 1회씩 전이를 소비한다
	# (공유 id 로 두면 가드가 걸려 1회만 나고, 고유 id 로 직접 조회하면 아예 안 난다).
	var row := data.milestone_vn_row(data.milestone_class_of(vn_id))
	if row.is_empty():
		return ""
	var relation := String(row["relation_transition"]).strip_edges()
	if relation == "":
		return ""
	_transitions_fired[vn_id] = true
	return relation


# ── 아카이브 재열람 (D07 §6.3 · TC-O4) ──
# 무상·상시이며 **전이를 재발화하지 않는다**. 스킵한 VN도 열람 대상이다 —
# 놓친 서사의 회수 경로가 곧 비강제성의 안전망이기 때문이다.
func archive_entries() -> Array:
	var entries: Array = []
	for vn_id in vn_seen:
		entries.append(vn_id)
	entries.sort()
	return entries


func replay_from_archive(vn_id: String) -> Dictionary:
	if not vn_seen.has(vn_id):
		return {"replayed": false, "relation": ""}
	# 재열람은 상태를 바꾸지 않는다 — 전이·카운터·상한 어디에도 손대지 않는다.
	return {"replayed": true, "relation": ""}


# ── 베인 대사 3단계 필터 (D12 §5.7) ──
# 키·풀은 불변이고 **선택 계층이 현 단계로 필터**한다 (풀 스왑 = 필터 전환, 데이터 복제 없음).
func vane_line(situation: String, stage: int) -> String:
	var fallback := ""
	for line_id in data.vane_lines:
		var row: Dictionary = data.vane_lines[line_id]
		if String(row["situation"]) != situation:
			continue
		var line_stage := CsvTable.to_int(String(row["stage"]))
		if line_stage == stage:
			return String(row["text_key"])
		if line_stage == 1:
			fallback = String(row["text_key"])
	if fallback == "":
		push_error("NarrativeService: no vane line for situation '%s'" % situation)
	return fallback


func serialize() -> Dictionary:
	return {
		"vn_seen": vn_seen.duplicate(), "vn_skipped": vn_skipped.duplicate(),
		"transitions_fired": _transitions_fired.duplicate(),
		"season_vn_count": season_vn_count, "milestone_vn_count": milestone_vn_count,
	}


func restore(payload: Dictionary) -> bool:
	if not payload.has("vn_seen") or not payload.has("transitions_fired"):
		push_error("NarrativeService: malformed payload")
		return false
	vn_seen = payload["vn_seen"]
	vn_skipped = payload.get("vn_skipped", {})
	_transitions_fired = payload["transitions_fired"]
	season_vn_count = int(payload.get("season_vn_count", 0))
	milestone_vn_count = int(payload.get("milestone_vn_count", 0))
	return true
