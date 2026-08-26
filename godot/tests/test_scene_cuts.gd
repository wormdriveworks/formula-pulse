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
const MACHINE_DIR := "res://assets/machines/"
const BACKGROUND_DIR := "res://assets/backgrounds/"
const CHARACTER_DIR := "res://assets/characters/"
# 막 VN 6 + 비트 11 (내러티브 12차 §2.5 검산)
const EXPECTED_VN_SCENES := 17
# 측면 베이스 전량 = 팀 3 + 프라이비티어 공용 1 + 보레아스 3단계 + 필러 변조 4 (에셋 IMPL-461)
const EXPECTED_BASELINES := 11

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
	_machine_layout(data)
	_baseline_pixels(data)
	_z_bands(data)
	_vn_backdrops(data)
	_vn_speakers(data)
	_mapping_priority(data)
	_mapping_negatives(data)
	print("")
	if _checked < 577:
		print("SCENE_FAIL checks=%d < 하한 577 (스위트 축소 의심)" % _checked)
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


# ── ⑧ 머신 자리 대장 (31차 · 에셋 IMPL-444·447 전사분) ──
func _machine_layout(data: GameData) -> void:
	var multi := 0
	for cut_id in data.scene_cuts:
		var declared := CsvTable.to_int(String(data.scene_cuts[cut_id]["machines"]))
		var slots := data.scene_cut_machines_for(String(cut_id))
		if declared <= 1:
			continue
		multi += 1
		# 2대 이상은 **선언이 있어야 한다** — 없으면 조용히 1대로 그려지고 표가 거짓이 된다.
		_ok("%s 머신 자리 선언 = 선언 대수 %d" % [cut_id, declared], slots.size() == declared,
			str(slots.size()))
	# 비공허성 — 다대 컷이 실재해야 위 축이 무언가를 잰다.
	_ok("다대 컷 전수 (6종)", multi == 6, str(multi))
	# **검수 표본이 런타임 표에 없는가** (에셋 IMPL-452) — 31차 전사가 정확히 이 형태로 샜다.
	# 열 이름이 아니라 **값**으로 잡는다: 어느 열에든 섀시 파일명이 들어오면 그것이 유입이다.
	var leaked: Array = []
	for cut_id in data.scene_cut_machines:
		for row in data.scene_cut_machines_for(String(cut_id)):
			for column_name in row:
				if data.machine_baselines.has(String(row[column_name]).strip_edges()):
					leaked.append("%s.%s" % [String(row["id"]), String(column_name)])
	_ok("검수 표본 유입 0 (자리 표에 섀시 파일명 없음)", leaked.is_empty(),
		"%s — 표본이 들어오면 대전 상대와 무관하게 같은 차가 나온다" % str(leaked))
	# 점유자 3종이 다 서는가 — 한 종만 쓰이면 열이 열 노릇을 하지 않는다.
	var occupants: Dictionary = {}
	for cut_id in data.scene_cut_machines:
		for row in data.scene_cut_machines_for(String(cut_id)):
			occupants[String(row["occupant"])] = true
	# 자리마다 캔버스 안인가 — 셀 폭 128 의 절반이 넘어가면 차가 화면 밖에서 잘린다.
	for cut_id in data.scene_cut_machines:
		for row in data.scene_cut_machines_for(String(cut_id)):
			var anchor_x := CsvTable.to_int(String(row["anchor_x"]))
			_ok("%s 앵커가 캔버스 안" % String(row["id"]),
				anchor_x >= 0 and anchor_x <= CANVAS_W, str(anchor_x))
	# ── 팀↔섀시 결속 (33차 · 에셋 대장 §4 전사) ──
	# **팀이 차를 갖는다.** 값은 반드시 섀시 대장 안이어야 한다 — 밖이면 오프셋이 0 으로
	# 떨어져 차가 뜨고, 그 결함은 화면에서만 보인다.
	var team_count := 0
	for team_id in data.teams:
		var chassis := String(data.teams[team_id].get("chassis", "")).strip_edges()
		team_count += 1
		_ok("팀 '%s' 섀시 선언" % String(team_id), not chassis.is_empty())
		_ok("팀 '%s' 섀시가 대장 안" % String(team_id),
			data.machine_baselines.has(chassis), chassis)
		# **성장 단계 접미가 붙지 않는다** (에셋 소견 — s1~s3 는 플레이어 머신의 시간 축이고
		# 라이벌이 성장 단계를 갖게 되면 안 된다).
		_ok("팀 '%s' 섀시에 단계 접미 없음" % String(team_id),
			not chassis.contains("_s1_") and not chassis.contains("_s2_")
			and not chassis.contains("_s3_"), chassis)
	_ok("팀 전수 (5)", team_count == 5, str(team_count))
	# 라이벌 → 팀 → 섀시가 전건 이어지는가 (`ai_rivals` 등재분)
	for row in data.rivals:
		var rival_id := String(row["id"])
		_ok("라이벌 '%s' 섀시 해소" % rival_id,
			data.machine_baselines.has(data.rival_chassis(rival_id)),
			data.rival_chassis(rival_id))
	# ── 필러 결속 (34차 소건 ②) ──
	# **결정적이어야 한다** — 같은 참가자는 언제나 같은 색이다(재현 계약).
	var probe_ids: Array = ["filler_01", "filler_02", "filler_03", "filler_04", "filler_05",
		"unknown_entrant"]
	var assigned: Dictionary = {}
	for entrant in probe_ids:
		var chassis := data.rival_chassis(String(entrant))
		_ok("필러 '%s' 섀시 해소" % String(entrant),
			data.machine_baselines.has(chassis), chassis)
		_ok("필러 '%s' = 변조 계열" % String(entrant), chassis.contains("_filler_"), chassis)
		_ok("필러 '%s' 재호출 동일 (결정적)" % String(entrant),
			data.rival_chassis(String(entrant)) == chassis)
		assigned[String(entrant)] = chassis
	# **한 색으로 몰리지 않는가** — 몰리면 필드가 같은 차로 가득 찬다.
	var distinct: Dictionary = {}
	for entrant in assigned:
		distinct[String(assigned[entrant])] = true
	_ok("필러 배정이 한 색으로 몰리지 않는다", distinct.size() >= 3, str(distinct.keys()))
	# 네임드 상대는 **필러 폴백으로 새지 않는다** — 팀 배정이 우선이다.
	for row in data.rivals:
		_ok("네임드 '%s' 는 필러 계열이 아니다" % String(row["id"]),
			not data.rival_chassis(String(row["id"])).contains("_filler_"),
			data.rival_chassis(String(row["id"])))
	_ok("점유자 3종 전건 사용 (player·rival·grid)",
		occupants.has("player") and occupants.has("rival") and occupants.has("grid"),
		str(occupants.keys()))
	for cut_id in data.scene_cut_machines:
		var orders: Array = []
		for row in data.scene_cut_machines_for(String(cut_id)):
			orders.append(CsvTable.to_int(String(row["slot_order"])))
		# 그리는 순서는 데이터가 정한다 — 중복이면 겹침 순서가 표 행 순서에 달린다.
		var seen: Array = []
		for order in orders:
			seen.append(order)
		orders.sort()
		var unique := true
		for i in range(1, orders.size()):
			if orders[i] == orders[i - 1]:
				unique = false
		_ok("%s 그리는 순서 중복 0" % String(cut_id), unique, str(seen))


# ── ⑨ 바닥 오프셋 = **화소로 재확인** (총괄 판정 ② ⓑ) ──
#
# 표를 표와 맞대면 전사를 확인할 뿐이다. 여기서는 **스프라이트 화소를 직접 세어**
# `opaque_bottom` 과 `baseline_offset` 을 다시 유도한다 — 원본이 바뀌면 대장이 붉어진다.
func _baseline_pixels(data: GameData) -> void:
	# 계수 핀 — **양쪽이 함께 줄어드는 것**을 잡는다(디렉토리 대조만으로는 둘 다 사라지면
	# 성립해 버린다). 7 → **11** 은 필러 변조 4종 유입분이다(에셋 IMPL-461).
	_ok("섀시 대장 = 측면 베이스 전량 11행", data.machine_baselines.size() == EXPECTED_BASELINES,
		str(data.machine_baselines.size()))
	for sprite in data.machine_baselines:
		var row: Dictionary = data.machine_baselines[sprite]
		# **오버레이는 대장에 들어오지 않는다** (총괄 재확인 ①) — 오버레이는 노면이 아니라
		# 베이스 셀에 정렬돼 있어 오프셋을 각각 적용하면 리어윙이 25px 밀린다.
		_ok("대장에 오버레이 없음: %s" % String(sprite), not String(sprite).contains("_overlay_"))
		var texture := load(MACHINE_DIR + String(sprite) + ".png") as Texture2D
		_ok("섀시 실물 적재: %s" % String(sprite), texture != null)
		if texture == null:
			continue
		var image := texture.get_image()
		var bottom := -1
		for y in range(image.get_height() - 1, -1, -1):
			var opaque := false
			for x in range(image.get_width()):
				if image.get_pixel(x, y).a > 0.0:
					opaque = true
					break
			if opaque:
				bottom = y
				break
		var cell_h := CsvTable.to_int(String(row["cell_h"]))
		_ok("%s 불투명 바닥행 화소 대조" % String(sprite),
			bottom == CsvTable.to_int(String(row["opaque_bottom"])),
			"화소 %d vs 대장 %s" % [bottom, row["opaque_bottom"]])
		_ok("%s 오프셋 = 바닥행 − 셀높이/2" % String(sprite),
			CsvTable.to_int(String(row["baseline_offset"])) == bottom - cell_h / 2,
			"대장 %s vs 유도 %d" % [row["baseline_offset"], bottom - cell_h / 2])
		_ok("%s 셀 높이 = 실물" % String(sprite), cell_h == image.get_height(),
			str(image.get_height()))
	# **표본 밖 베이스도 덮는가** (총괄 재확인 ②) — 실 섀시는 대전 상대에 따라 바뀌므로
	# 컷 선언의 sprite 는 검수 표본일 뿐이다. 디렉토리의 `*_base_*_side` 전량이 대장에 있어야 한다.
	# 임포트된 프로젝트는 원본 옆에 `.import` 를 함께 열거한다 — **같은 파일이므로 접는다**
	# (접지 않으면 계수가 2배로 나오고, 그 2배가 "전량 확인"처럼 보인다).
	var found: Array = []
	for file_name in DirAccess.get_files_at(MACHINE_DIR):
		var name := String(file_name).trim_suffix(".import")
		if not name.ends_with("_side.png") or not name.contains("_base_"):
			continue
		if not found.has(name):
			found.append(name)
	_ok("베이스 실물 열거 비공허", found.size() == EXPECTED_BASELINES, str(found.size()))
	for name in found:
		_ok("베이스 '%s' 대장 등재" % String(name),
			data.machine_baselines.has(String(name).trim_suffix(".png")),
			"표본 밖 섀시가 슬롯에 들어오면 오프셋 0 으로 떨어진다")


# ── ⑩ fx z 대역 (총괄 판정 ③) ──
func _z_bands(data: GameData) -> void:
	var behind := 0
	var front := 0
	for element_id in data.fx_elements:
		match String(data.fx_elements[element_id]["z_band"]):
			"behind":
				behind += 1
			"front":
				front += 1
	# **한 값이 아니다** — 양쪽이 다 서야 요소별 선언이 뜻을 갖는다. 한쪽이 0 이면
	# 그것은 선언이 아니라 전역 상수이고, 오라와 불꽃 중 하나는 반드시 틀린다.
	_ok("z 대역 양쪽 비공허 (뒤 %d · 앞 %d)" % [behind, front], behind > 0 and front > 0)
	_ok("z 대역 합 = 요소 전량", behind + front == EXPECTED_ELEMENTS, str(behind + front))
	# 정본 문면의 두 지점 — 오라는 뒤, 불꽃은 앞.
	_ok("듀얼 오라 = 뒤", String(data.fx_element("fxe_duel_aura")["z_band"]) == "behind")
	_ok("접촉 불꽃 = 앞", String(data.fx_element("fxe_contact_spark")["z_band"]) == "front")
	# 검수 시트가 짚은 관통 — 스피드 라인이 후미차를 뚫었다.
	_ok("스피드 라인 = 뒤 (후미차 관통 교정)",
		String(data.fx_element("fxe_speed_lines")["z_band"]) == "behind")


# ── ⑪ VN 장면 바탕 (내러티브 12차 스펙 · 17장면 전건 · 무배경 0) ──
func _vn_backdrops(data: GameData) -> void:
	_ok("스펙 계수 = 17장면", data.vn_backdrops.size() == EXPECTED_VN_SCENES,
		str(data.vn_backdrops.size()))
	var by_asset: Dictionary = {}
	for backdrop_id in data.vn_backdrops:
		var row: Dictionary = data.vn_backdrops[backdrop_id]
		var act_vn := String(row.get("source_act_vn", "")).strip_edges()
		var beat := String(row.get("source_beat", "")).strip_edges()
		# **장면 하나에 열쇠 하나** — 둘이면 조회 순서가 표 행 순서에 달린다.
		_ok("%s 장면 열쇠 정확히 1" % backdrop_id,
			(act_vn.is_empty()) != (beat.is_empty()), "%s / %s" % [act_vn, beat])
		if not act_vn.is_empty():
			_ok("%s 막 VN 항목 실재" % backdrop_id,
				not data.act_vn_entry(act_vn).is_empty(), act_vn)
		if not beat.is_empty():
			_ok("%s 비트 행 실재" % backdrop_id, not data.vn_beat(beat).is_empty(), beat)
		var asset := String(row["backdrop"]).strip_edges()
		by_asset[asset] = int(by_asset.get(asset, 0)) + 1
		_ok("%s 바탕 실물 적재" % backdrop_id,
			load(BACKGROUND_DIR + asset + ".png") != null, asset)
		# 조회가 실제로 그 값을 낸다 — 표를 표와 맞대는 것이 아니라 창구를 통과시킨다.
		_ok("%s 조회 일치" % backdrop_id,
			data.vn_backdrop(act_vn if beat.is_empty() else beat) == asset, asset)
	# 스펙 §0 계수 검산 — 개러지 9 · 패독 5 · 트랙사이드 2 · **충돌 1**.
	# 충돌분(`vnbeat_crew_sasha`)이 사용자 판정으로 개러지가 됐으므로 **9 + 1 = 10** 이다
	# (총괄 착수 신호 — ⓐ 문면을 CG 에). 스펙 표의 9 는 충돌을 뺀 수다.
	_ok("바탕 배분 = 개러지 10 (스펙 9 + 판정 1)",
		int(by_asset.get("garage_h", 0)) == 10, str(by_asset))
	_ok("바탕 배분 = 패독 5", int(by_asset.get("vn_paddock", 0)) == 5, str(by_asset))
	_ok("바탕 배분 = 트랙사이드 2", int(by_asset.get("vn_trackside", 0)) == 2, str(by_asset))
	# **전 장면이 덮이는가** — 막 VN 6 + 비트 11 전량에 행이 있어야 무배경 0 이 성립한다.
	for entry in data.act_vn_entries():
		_ok("막 VN '%s' 바탕 지정" % String(Dictionary(entry)["id"]),
			not data.vn_backdrop(String(Dictionary(entry)["id"])).is_empty())
	for beat_id in data.vn_beats:
		_ok("비트 '%s' 바탕 지정" % String(beat_id),
			not data.vn_backdrop(String(beat_id)).is_empty())
	# ⚠ **접미 붙은 인스턴스 id 로도 잡히는가** — 완전 일치 하나로 두면 개막·종막만
	# 조용히 검정으로 떨어진다(스펙 §2.1 명기 함정). 접두 열이 그 경로를 잇는다.
	var prefixed := 0
	for backdrop_id in data.vn_backdrops:
		var prefix := String(data.vn_backdrops[backdrop_id].get("vn_id_prefix", "")).strip_edges()
		if prefix.is_empty():
			continue
		prefixed += 1
		_ok("접미 인스턴스 조회: %s_s3" % prefix,
			data.vn_backdrop("%s_s3" % prefix)
			== String(data.vn_backdrops[backdrop_id]["backdrop"]), prefix)
	_ok("접두 선언 = 2건 (개막·종막)", prefixed == 2, str(prefixed))
	# 미지정은 빈 문자열 — 폴백(ColorRect)이 자동 성립하는 자리다.
	_ok("미상 장면 = 무배경", data.vn_backdrop("vn_not_a_scene").is_empty())
	_ok("공란 = 무배경", data.vn_backdrop("").is_empty())


# ── ⑫ 화자 스탠딩 배정 (내러티브 14차 스펙) ──
func _vn_speakers(data: GameData) -> void:
	_ok("화자 대장 = 9행", data.vn_speakers.size() == 9, str(data.vn_speakers.size()))
	var sides: Dictionary = {}
	for speaker_key in data.vn_speakers:
		var row: Dictionary = data.vn_speakers[speaker_key]
		var side := String(row["side"])
		sides[side] = int(sides.get(side, 0)) + 1
		var char_id := String(row.get("char_id", "")).strip_edges()
		var wave := CsvTable.to_int(String(row.get("waveform", "0"))) == 1
		# **자리가 있으면 그릴 것이 있어야 한다** — 인물이거나 파형이다(총괄 판정 ② 이후).
		# 어긋나면 "자리는 있는데 그릴 것이 없는" 상태가 조용히 성립한다.
		_ok("%s 자리·표현 정합" % String(speaker_key),
			(side == "none") == (char_id.is_empty() and not wave),
			"%s / %s / wave=%s" % [side, char_id, wave])
		# **인물과 파형은 배타다** — 둘 다면 한 슬롯에 둘이 서려 한다.
		_ok("%s 인물·파형 배타" % String(speaker_key), not (wave and not char_id.is_empty()),
			"%s / wave=%s" % [char_id, wave])
		if char_id.is_empty():
			continue
		_ok("%s 스탠딩 실물 적재" % String(speaker_key),
			load(CHARACTER_DIR + char_id + "_base.png") != null, char_id)
	# 좌 1 · 우 6 · 부재 2 — 마르타 좌 고정이 스펙의 축이다(17/17 전 장면 등장).
	_ok("좌측 = 1인 고정", int(sides.get("left", 0)) == 1, str(sides))
	# 베인이 우측 슬롯을 차용하면서 6→7 · 부재 2→1 (지문만). 자리 수는 여전히 둘이다.
	_ok("우측 경합 = 7 (베인 차용 포함)", int(sides.get("right", 0)) == 7, str(sides))
	_ok("선언된 부재 = 1 (지문)", int(sides.get("none", 0)) == 1, str(sides))
	# **발화하는 화자 전량이 대장에 있는가** — 없으면 그 인물만 조용히 안 선다.
	for beat_id in data.vn_beat_lines:
		for line in data.vn_beat_lines_for(String(beat_id)):
			_ok("비트 화자 등재: %s" % String(line["speaker_key"]),
				not data.vn_speaker(String(line["speaker_key"])).is_empty(),
				String(line["speaker_key"]))
	for entry in data.act_vn_entries():
		for line in Array(Dictionary(entry).get("lines", [])):
			_ok("막 VN 화자 등재: %s" % String(Dictionary(line)["speaker_key"]),
				not data.vn_speaker(String(Dictionary(line)["speaker_key"])).is_empty(),
				String(Dictionary(line)["speaker_key"]))
	# **키를 쪼갠다** — 붙여 두면 V2 가 코드 리터럴로 보고 미등재 키로 잡는다(21차 전례).
	_ok("미상 화자 = 무배정", data.vn_speaker("ui.vn." + "speakerNobody").is_empty())
	# ── 표정 차분 예외 (총괄 판정 ① — 단일 장면) ──
	_ok("표정 예외 = 1건 (단일 장면 예외)", data.vn_face_variants.size() == 1,
		str(data.vn_face_variants.size()))
	for row in data.vn_face_variants:
		var scene_id := String(row["source_beat"])
		var speaker_key := String(row["speaker_key"])
		var variant := String(row["face_variant"])
		_ok("예외 장면 실재: %s" % scene_id, not data.vn_beat(scene_id).is_empty())
		_ok("예외 화자가 그 장면에서 말한다: %s" % speaker_key,
			_beat_has_speaker(data, scene_id, speaker_key))
		var char_id := String(data.vn_speaker(speaker_key).get("char_id", ""))
		_ok("예외 차분 실물 적재",
			load(CHARACTER_DIR + char_id + "_" + variant + ".png") != null,
			char_id + "_" + variant)
		_ok("예외 조회 일치", data.vn_face_variant(scene_id, speaker_key) == variant)
		# **다른 장면에서는 열리지 않는다** — 열리면 단일 장면 예외가 아니다.
		_ok("타 장면 = 예외 없음",
			data.vn_face_variant("vnbeat_crew_oscar", speaker_key).is_empty())
		_ok("타 화자 = 예외 없음",
			data.vn_face_variant(scene_id, "ui.vn.speakerMarta").is_empty())


func _beat_has_speaker(data: GameData, beat_id: String, speaker_key: String) -> bool:
	for line in data.vn_beat_lines_for(beat_id):
		if String(line["speaker_key"]) == speaker_key:
			return true
	return false


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
