# SCENE — 씬 컷 합성 대장·실물·매핑 검사 (D09 §3.1.1 · D12 §5.9 · D13 별첨A §8.2 · 사양서 v1.11 §5.2).
#
# **왜 스위트인가.** CG·AUDIO-A 와 같은 사유다 — 검증기는 프로젝트리스라 `res://` 텍스처를
# 적재하지 못하고, "파일명이 맞다"와 "그 이름으로 실제 원도가 선다"는 다른 사실이다.
#
# **축의 요지는 역방향과 우선순위 두 가지다.**
#   · 역방향 — 요소 8종·배경 10장이 **하나도 빠짐없이 어느 컷엔가 소비되는가.** 29차 착수의
#     이유 자체가 "`fx_*` 8 · `stage_*` 5 소비부 0건"이었으므로, 이 축이 그 0 을 다시 만들지
#     않는다는 보장이다.
#   · 우선순위 — D13 §8.2 가 **말로** 정한 서열을 실제 호출로 재현한다. 표의 숫자가 아니라
#     `resolve()` 의 결과를 본다(숫자를 숫자와 맞대면 표를 옮겨 적은 것을 확인할 뿐이다).
extends SceneTree

const SCENECUT_DIR := "res://assets/scenecuts/"
const CANVAS_W := 408      # 사양서 §5.1 제작 원도 (확정 기준값 v1.1)
const CANVAS_H := 100      # D10 §6.2 패널 원도 높이
const EXPECTED_ELEMENTS := 8   # 사양서 §5.2.1 연출 요소 8종
const EXPECTED_CUTS := 10      # D10 §6.2 10종 + 예비 2
const EXPECTED_BACKDROPS := 5  # 무대 5

# D13 별첨A §8.2 서열의 전사 — **말을 순서 배열로만 옮긴다.** 숫자는 표가 갖고 검사는
# 서열만 갖는다(양쪽에 숫자를 두면 한쪽이 밀려도 대조가 성립한다).
const PRIORITY_ORDER := [
	"cut_duel_standoff", "cut_trouble", "cut_overtake", "cut_defense",
	"cut_close_battle", "cut_start", "cut_basic_solo",
]

var _checked := 0
var _failures := 0


func _init() -> void:
	SaveManager.use_test_root()
	var data := GameData.new()
	if not data.load_all():
		print("SCENE_FAIL data load")
		quit(1)
		return
	_ledger_shape(data)
	_element_assets(data)
	_backdrop_assets(data)
	_consumption_reverse(data)
	_placement_constraints(data)
	_mapping_priority(data)
	_mapping_negatives(data)
	print("")
	if _checked < 139:
		print("SCENE_FAIL checks=%d < 하한 139 (스위트 축소 의심)" % _checked)
		quit(1)
		return
	if _failures == 0:
		print("SCENE_PASS checks=%d" % _checked)
		quit(0)
	else:
		print("SCENE_FAIL failures=%d checks=%d" % [_failures, _checked])
		quit(1)


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checked += 1
	if condition:
		return
	_failures += 1
	print("  [FAIL] %s%s" % [label, (" — " + detail) if detail != "" else ""])


# ── ① 대장 형태 ──
func _ledger_shape(data: GameData) -> void:
	_ok("사양서 §5.2.1 연출 요소 8종", data.fx_elements.size() == EXPECTED_ELEMENTS,
		str(data.fx_elements.size()))
	_ok("D10 §6.2 씬 컷 10종", data.scene_cuts.size() == EXPECTED_CUTS, str(data.scene_cuts.size()))
	_ok("무대 배경 5식", data.stage_backdrops.size() == EXPECTED_BACKDROPS,
		str(data.stage_backdrops.size()))
	# 프레임 수는 정본 표(사양서 §5.2)의 값이며 D09 §3.1.1 의 컷당 10프레임 상한 안이어야 한다.
	for cut_id in data.scene_cuts:
		var frames := CsvTable.to_int(String(data.scene_cuts[cut_id]["frames"]))
		_ok("%s 프레임 ≤ 10 (D09 §3.1.1 상한)" % cut_id, frames >= 1 and frames <= 10, str(frames))
	# 트리거는 컷을 가리키고, 폴백은 **정확히 하나**다 — 둘이면 어느 쪽이 서는지가
	# 표 행 순서에 달리고, 없으면 코드가 기본값을 들게 된다.
	var fallbacks := 0
	for trigger in data.scene_cut_triggers:
		if String(trigger["match_kind"]) == "fallback":
			fallbacks += 1
		_ok("%s 가 가리키는 컷 실재" % String(trigger["id"]),
			not data.scene_cut(String(trigger["cut_id"])).is_empty(), String(trigger["cut_id"]))
	_ok("폴백 트리거 정확히 1", fallbacks == 1, str(fallbacks))


# ── ② 요소 실물 — 원도 치수 대조 ──
func _element_assets(data: GameData) -> void:
	for element_id in data.fx_elements:
		var row: Dictionary = data.fx_elements[element_id]
		var texture := load(SCENECUT_DIR + String(row["asset"]) + ".png") as Texture2D
		_ok("%s 실물 적재" % element_id, texture != null, String(row["asset"]))
		if texture == null:
			continue
		var cell_w := CsvTable.to_int(String(row["cell_w"]))
		var cell_h := CsvTable.to_int(String(row["cell_h"]))
		var frames := CsvTable.to_int(String(row["frames"]))
		# 시트는 **셀 × 프레임**이 곧 파일 폭이다 — 이 등식이 깨지면 `AtlasTexture` 가
		# 옆 칸을 잘라 온다(fx_spec 의 `edge_margin` 이 막으려던 바로 그 사고).
		_ok("%s 원도 = 셀 %d×%d × %d프레임" % [element_id, cell_w, cell_h, frames],
			texture.get_width() == cell_w * frames and texture.get_height() == cell_h,
			"%d×%d" % [texture.get_width(), texture.get_height()])
		var still := CsvTable.to_int(String(row["still_frame"]))
		_ok("%s 대표 프레임이 시트 안" % element_id, still >= 0 and still < frames, str(still))
	# 역방향 — 디렉토리의 `fx_*` 전량에 대장 행이 있는가
	var declared: Array = []
	for element_id in data.fx_elements:
		declared.append(String(data.fx_elements[element_id]["asset"]))
	var found: Array = []
	for file_name in DirAccess.get_files_at(SCENECUT_DIR):
		var name := String(file_name).trim_suffix(".import")
		if name.begins_with("fx_") and name.ends_with(".png") and not found.has(name):
			found.append(name)
	_ok("fx 실물 열거 비공허", found.size() == EXPECTED_ELEMENTS, str(found.size()))
	for name in found:
		_ok("실물 '%s' 에 대장 행이 있다" % name, declared.has(name.trim_suffix(".png")),
			"대장 밖 요소는 아무 컷도 얹지 않는다")


# ── ③ 배경 실물 — 2레이어 × 5무대 ──
func _backdrop_assets(data: GameData) -> void:
	for backdrop_id in data.stage_backdrops:
		var row: Dictionary = data.stage_backdrops[backdrop_id]
		for column in ["far_asset", "near_asset"]:
			var texture := load(SCENECUT_DIR + String(row[column]) + ".png") as Texture2D
			_ok("%s.%s 실물 적재" % [backdrop_id, column], texture != null, String(row[column]))
			if texture == null:
				continue
			_ok("%s.%s 원도 %d×%d" % [backdrop_id, column, CANVAS_W, CANVAS_H],
				texture.get_width() == CANVAS_W and texture.get_height() == CANVAS_H,
				"%d×%d" % [texture.get_width(), texture.get_height()])
		_ok("%s 가 가리키는 무대 실재" % backdrop_id,
			data.stages.has(String(row["stage_id"])), String(row["stage_id"]))
	# 무대 전량이 배경을 갖는가 — 한 무대라도 빠지면 그 무대에서 패널이 빈 채로 선다.
	for stage_id in data.stages:
		_ok("무대 '%s' 에 배경 2레이어" % stage_id,
			not data.stage_backdrop(String(stage_id)).is_empty())


# ── ④ 소비 역방향 — 요소가 하나도 놀지 않는가 (29차 착수 사유의 폐문 증명) ──
func _consumption_reverse(data: GameData) -> void:
	var consumed: Dictionary = {}
	for cut_id in data.scene_cuts:
		for row in data.scene_cut_layers_for(String(cut_id)):
			consumed[String(row["element_id"])] = true
	for element_id in data.fx_elements:
		_ok("요소 '%s' 를 어느 컷인가 소비한다" % element_id, consumed.has(String(element_id)),
			"소비부 0 = 29차 착수 사유 그 자체다")
	# 컷 → 요소 방향도 본다. 요소 없는 컷은 정상이지만(정지 폴백 = 배경+머신) **선언한
	# 요소가 대장 밖**이면 그 층은 조용히 빠진다.
	for cut_id in data.scene_cuts:
		for row in data.scene_cut_layers_for(String(cut_id)):
			_ok("%s 의 요소 참조 해소" % String(row["id"]),
				not data.fx_element(String(row["element_id"])).is_empty(),
				String(row["element_id"]))


# ── ⑤ 배치 제약 ① — 색 치환 강제 (제원표 §3.1 ①) ──
#
# 제약 ②(지평선 대역)는 무대별 분할 y 가 `tools/assets/bg_spec.json` 에 있어 `res://` 밖이다 —
# 검증기(리포 루트 실행) 소관으로 갈랐다. 여기서는 **데이터 안에서 판정 가능한 것**만 본다.
func _placement_constraints(data: GameData) -> void:
	for cut_id in data.scene_cuts:
		for row in data.scene_cut_layers_for(String(cut_id)):
			var element := data.fx_element(String(row["element_id"]))
			if element.is_empty():
				continue
			if CsvTable.to_int(String(element["tint_required"])) != 1:
				continue
			# **모든 사용처가 대상이다** — 한 컷에서만 치환하면 다른 컷에서 배경에 묻힌다.
			_ok("%s 색 치환 선언 (제약 ①)" % String(row["id"]),
				not String(row.get("tint", "")).strip_edges().is_empty(),
				"중립 회백 그대로면 밝은 무대에서 사라진다")
	# 역할 표가 화면 층에 실재하는가 — 선언은 있는데 해소가 없으면 흰색으로 뜬다.
	var panel_source := FileAccess.get_file_as_string("res://ui/race/scene_panel.gd")
	for cut_id in data.scene_cuts:
		for row in data.scene_cut_layers_for(String(cut_id)):
			var tint := String(row.get("tint", "")).strip_edges()
			if tint.is_empty():
				continue
			_ok("역할 '%s' 를 화면 층이 안다" % tint, panel_source.contains('"%s"' % tint))


# ── ⑥ 매핑 우선순위 — D13 §8.2 서열을 호출로 재현 ──
func _mapping_priority(data: GameData) -> void:
	var map := SceneCutMap.new()
	map.setup(data)
	# 각 컷을 **단독으로** 세워 조건이 실제로 그 컷을 뽑는지부터 본다(비공허성).
	for cut_id in PRIORITY_ORDER:
		_ok("단독 조건에서 %s 성립" % cut_id,
			map.resolve(_context_for(data, String(cut_id))) == String(cut_id),
			map.resolve(_context_for(data, String(cut_id))))
	# 그 다음 서열 — 상위 조건을 **함께** 세우면 상위가 이긴다.
	for i in range(1, PRIORITY_ORDER.size()):
		var higher := String(PRIORITY_ORDER[i - 1])
		var lower := String(PRIORITY_ORDER[i])
		var merged := _merge(_context_for(data, higher), _context_for(data, lower))
		_ok("%s > %s (D13 §8.2)" % [higher, lower], map.resolve(merged) == higher,
			map.resolve(merged))
	# 피니시는 스타트와 같은 단이다 — 서열 배열에 넣으면 순서가 없는 곳에 순서를 만든다.
	_ok("피니시 단독 성립",
		map.resolve(_context_for(data, "cut_finish")) == "cut_finish")


func _mapping_negatives(data: GameData) -> void:
	var map := SceneCutMap.new()
	map.setup(data)
	# 아무 조건도 서지 않으면 **폴백이 데이터에서 나온다** (코드 기본값 없음)
	var bare := {"log_keys": [], "duel_turn": false, "front_gauge": 0.0, "rear_gauge": 0.0,
		"gp_finished": false, "field_size": 1}
	_ok("무조건 = 기본 주행 단독", map.resolve(bare) == "cut_basic_solo", map.resolve(bare))
	# **미배정 컷은 절대 서지 않는다** — D13 §8.2 대장에 자리가 없는 컷(SC-10)은
	# 우선순위 0 으로 선언돼 평가에서 구조적으로 빠진다(임의 서열 부여 금지 — 불변규칙 9).
	_ok("전제: 미배정 컷이 실재한다",
		CsvTable.to_int(String(data.scene_cut("cut_pulse_drive")["priority"])) == 0)
	# **불변식은 데이터 층에 건다: 미배정 = 미발화.** 문맥 몇 개를 돌려 보는 형태로는
	# *그 컷을 부를 수 있는 문맥*을 검사가 스스로 만들지 못한다 — 29차 2단 탐침에서
	# 실제로 그 구멍이 드러났다(조건을 붙이고 코드 가드를 빼도 세 문맥 중 어디에도
	# 걸리지 않아 미검출). 서열 없는 컷에 조건이 붙는 것 자체를 막는다.
	# **계수로 센다** — 위반마다 짖는 형태로 두면 위반 0 일 때 검사가 0건이 되고,
	# 그 검사를 통째로 지워도 검사 수 하한이 움직이지 않는다(27차 "계수가 사실을 왜곡한다").
	var unranked: Array = []
	for trigger in data.scene_cut_triggers:
		var cut := data.scene_cut(String(trigger["cut_id"]))
		if CsvTable.to_int(String(cut.get("priority", "0"))) <= 0:
			unranked.append(String(trigger["id"]))
	_ok("미배정 컷에 조건이 붙지 않는다 (미배정 = 미발화)", unranked.is_empty(),
		"%s — D13 §8.2 대장에 서열이 없는 컷은 발화 경로를 가질 수 없다" % str(unranked))
	# 코드 가드는 두 번째 벨트다 — 조건이 붙은 상태에서도 서열 0 은 뽑히지 않아야 한다.
	var any_unassigned := false
	for context in [bare, _context_for(data, "cut_trouble"), _context_for(data, "cut_finish"),
			{"log_keys": [], "duel_turn": true, "front_gauge": 999.0, "rear_gauge": 999.0,
			"gp_finished": true, "field_size": 9}]:
		if map.resolve(context) == "cut_pulse_drive":
			any_unassigned = true
	_ok("미배정 컷은 어떤 문맥에서도 선택되지 않는다", not any_unassigned)
	# 릴 국면 고정 — **결과를 인자로 받지 않는다**(봉인). 필드 상황만으로 갈린다.
	_ok("릴 국면 단독", map.reel_phase_cut(1) == SceneCutMap.REEL_PHASE_SOLO)
	_ok("릴 국면 그룹", map.reel_phase_cut(3) == SceneCutMap.REEL_PHASE_GROUP)
	# 문턱은 **표가 정한다** — 그룹 컷이 선언한 머신 수 그대로여야 한다.
	var declared := CsvTable.to_int(String(data.scene_cut(SceneCutMap.REEL_PHASE_GROUP)["machines"]))
	_ok("그룹 문턱 = 표 선언(%d) 직전은 단독" % declared,
		map.reel_phase_cut(declared - 1) == SceneCutMap.REEL_PHASE_SOLO)
	# 완급 비트 발동 = **표의 빈도를 따르는가.** 0 이면 한 번도, 1 이면 매번이어야 한다 —
	# 상수를 넣으면 둘 중 하나가 갈린다. `reserve` 스트림 소비도 함께 본다(D12 §6 직렬화 축).
	var session := RunSession.new()
	session.setup(data)
	session.begin_career(1)
	var before := str(session.rng.serialize().get("streams", {}).get("reserve", ""))
	var due := 0
	for i in range(40):
		if session.pacing_beat_due():
			due += 1
	_ok("완급 비트 발동이 상수가 아니다 (0 < n < 40)", due > 0 and due < 40, str(due))
	_ok("완급 비트 = reserve 스트림 소비",
		str(session.rng.serialize().get("streams", {}).get("reserve", "")) != before)
	_ok("대장 조회 중 데이터 침묵 기본값 0", data.is_ok())


# 컷 하나만 성립시키는 문맥. **로그 키는 표에서 읽는다** — 검사에 키를 적으면
# 표를 바꿔도 검사가 옛 키로 통과한다.
func _context_for(data: GameData, cut_id: String) -> Dictionary:
	var context := {"log_keys": [], "duel_turn": false, "front_gauge": 0.0, "rear_gauge": 0.0,
		"gp_finished": false, "field_size": 1}
	for trigger in data.scene_cut_triggers:
		if String(trigger["cut_id"]) != cut_id:
			continue
		match String(trigger["match_kind"]):
			"duel_turn":
				context["duel_turn"] = true
			"log_event":
				context["log_keys"] = [String(trigger["log_key"])]
			"close_gauge":
				context["front_gauge"] = data.param("param_closerace_gauge_threshold")
			"gp_finish":
				context["gp_finished"] = true
			"group_field":
				context["field_size"] = CsvTable.to_int(
					String(data.scene_cut(cut_id).get("machines", "3")))
		break
	return context


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var merged := a.duplicate(true)
	merged["log_keys"] = Array(a["log_keys"]) + Array(b["log_keys"])
	merged["duel_turn"] = bool(a["duel_turn"]) or bool(b["duel_turn"])
	merged["front_gauge"] = maxf(float(a["front_gauge"]), float(b["front_gauge"]))
	merged["gp_finished"] = bool(a["gp_finished"]) or bool(b["gp_finished"])
	merged["field_size"] = maxi(int(a["field_size"]), int(b["field_size"]))
	return merged
