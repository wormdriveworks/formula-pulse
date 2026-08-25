# CG — 전용 CG 대장·실물 검사 (D10 §7 결정 #6 · 유입 IMPL-418 · 소비부 결선 28차).
#
# **왜 별도 스위트인가.** AUD 와 같은 사유다(AUDIO-A 머리말): `run_validators.gd` 는
# 프로젝트리스 실행이라 `res://` 리소스를 적재하지 못한다. 파일명 문자열이 맞는 것과
# **그 이름으로 실제 텍스처가 서는 것**은 다른 사실이고, 후자는 프로젝트 문맥이 필요하다.
#
# **양방향 대장이 이 스위트의 축이다.** 한 방향만 보면 대장은 반드시 낡는다:
#   · 행 → 파일 : 표에 있는데 그림이 없으면 실기에서 빈 화면이 뜬다
#   · 파일 → 행 : 그림이 들어왔는데 행이 없으면 **아무도 그 그림을 띄우지 않는다**
#   · 행 → 발화원 : 업적·막 VN·비트 중 정확히 하나를 가리켜야 한다
#   · 조우 3종 → 행 : 판정 함수가 낼 수 있는 발견 id 전부에 그림이 있어야 한다
# 마지막 축이 27차 계보다 — **원본에 이름이 있다는 것과 그것이 일하는 것은 다른 사실이다.**
extends SceneTree

const ILLUSTRATION_DIR := "res://assets/illustrations/"
const RACE_SCREEN_SCRIPT := "res://ui/race/race_screen.gd"

# D10 §7 "상한 6종" · "두 계열 각 3종" — 정본 계수의 핀. 늘리려면 정본이 먼저 움직인다.
const EXPECTED_ROWS := 6
const EXPECTED_ENCOUNTER := 3
const EXPECTED_HIDDEN := 3
# D10 §7 "대형 도트 CG (640×360 전면 원도)"
const CANVAS_W := 640
const CANVAS_H := 360
# 대장이 CG 로 세는 파일의 이름 규약 — 키 비주얼(`kv_*`)은 같은 디렉토리의 다른 계다.
const CG_PREFIX := "cg"

const SOURCE_COLUMNS := ["source_achievement", "source_act_vn", "source_beat"]

var _checked := 0
var _failures := 0


func _init() -> void:
	SaveManager.use_test_root()   # 저장 격리 — 실 프로필 무접촉 (25차)
	var data := GameData.new()
	if not data.load_all():
		print("CG_FAIL data load")
		quit(1)
		return
	_ledger_shape(data)
	_assets_exist(data)
	_files_have_rows(data)
	_sources_resolve(data)
	_encounters_covered(data)
	_lookup_negatives(data)
	_component_contract(data)
	print("")
	if _checked < 69:
		print("CG_FAIL checks=%d < 하한 69 (스위트 축소 의심)" % _checked)
		quit(1)
		return
	if _failures == 0:
		print("CG_PASS checks=%d" % _checked)
		quit(0)
	else:
		print("CG_FAIL failures=%d checks=%d" % [_failures, _checked])
		quit(1)


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checked += 1
	if condition:
		return
	_failures += 1
	print("  [FAIL] %s%s" % [label, (" — " + detail) if detail != "" else ""])


# ── ① 대장 형태 — 계수 핀 + 발화원 배타 ──
func _ledger_shape(data: GameData) -> void:
	_ok("D10 §7 상한 6종", data.cg_cutins.size() == EXPECTED_ROWS, str(data.cg_cutins.size()))
	var encounter := 0
	var hidden := 0
	for cutin_id in data.cg_cutins:
		var row: Dictionary = data.cg_cutins[cutin_id]
		var declared: Array = []
		for column in SOURCE_COLUMNS:
			if not String(row.get(column, "")).strip_edges().is_empty():
				declared.append(column)
		# **정확히 하나다.** 0 이면 영원히 안 뜨는 그림이고, 2 이상이면 조회 창구 두 개가
		# 같은 행을 물어 어느 쪽이 먼저인지가 코드 순서에 달린다.
		_ok("%s 발화원 정확히 1" % cutin_id, declared.size() == 1, str(declared))
		if declared.size() != 1:
			continue
		if String(declared[0]) == "source_achievement":
			encounter += 1
		else:
			hidden += 1
	_ok("D10 §7 L3 조우 계열 3종", encounter == EXPECTED_ENCOUNTER, str(encounter))
	_ok("D10 §7 히든 내러티브 3종", hidden == EXPECTED_HIDDEN, str(hidden))


# ── ② 행 → 실물 ──
func _assets_exist(data: GameData) -> void:
	for cutin_id in data.cg_cutins:
		var asset := String(data.cg_cutins[cutin_id]["asset"]).strip_edges()
		var path := ILLUSTRATION_DIR + asset + ".png"
		var texture := load(path) as Texture2D
		_ok("%s 실물 적재 (%s)" % [cutin_id, asset], texture != null, path)
		if texture == null:
			continue
		_ok("%s 원도 %d×%d" % [cutin_id, CANVAS_W, CANVAS_H],
			texture.get_width() == CANVAS_W and texture.get_height() == CANVAS_H,
			"%d×%d" % [texture.get_width(), texture.get_height()])


# ── ③ 실물 → 행 (역방향 — 이 축이 없으면 대장은 늘 낡는다) ──
func _files_have_rows(data: GameData) -> void:
	var declared: Dictionary = {}
	for cutin_id in data.cg_cutins:
		declared[String(data.cg_cutins[cutin_id]["asset"]).strip_edges()] = cutin_id
	var found: Array = []
	for file_name in DirAccess.get_files_at(ILLUSTRATION_DIR):
		var name := String(file_name)
		# 임포트된 프로젝트에서는 원본 옆에 `.import` 가 함께 열거된다 — 같은 파일이다.
		if name.ends_with(".import"):
			name = name.trim_suffix(".import")
		if not name.ends_with(".png") or not name.begins_with(CG_PREFIX):
			continue
		var stem := name.trim_suffix(".png")
		if not found.has(stem):
			found.append(stem)
	# 열거 자체가 비면 이 축은 0==0 으로 성립해 버린다 — 비공허성을 먼저 못박는다.
	_ok("일러스트 디렉토리 열거 비공허", found.size() == EXPECTED_ROWS, str(found))
	for stem in found:
		_ok("실물 '%s' 에 대장 행이 있다" % stem, declared.has(stem),
			"대장에 없는 CG 는 아무도 띄우지 않는다")


# ── ④ 발화원 해소 ──
func _sources_resolve(data: GameData) -> void:
	for cutin_id in data.cg_cutins:
		var row: Dictionary = data.cg_cutins[cutin_id]
		var achievement_id := String(row.get("source_achievement", "")).strip_edges()
		var act_vn_id := String(row.get("source_act_vn", "")).strip_edges()
		var beat_id := String(row.get("source_beat", "")).strip_edges()
		if not achievement_id.is_empty():
			var achievement: Dictionary = data.achievements.get(achievement_id, {})
			_ok("%s 업적 행 실재" % cutin_id, not achievement.is_empty(), achievement_id)
			if achievement.is_empty():
				continue
			# D10 §7 "발견형 히든 업적과 1:1" — 성격이 어긋나면 1:1 이 아니다.
			_ok("%s 업적 = 발견형" % cutin_id,
				String(achievement.get("source", "")) == "discovery", str(achievement))
			_ok("%s 업적 = 히든" % cutin_id,
				String(achievement.get("hidden", "")).strip_edges() == "1", str(achievement))
			var discovery_id := String(achievement.get("source_id", "")).strip_edges()
			_ok("%s 발견 id 비공란" % cutin_id, not discovery_id.is_empty())
			_ok("%s 발견 id 역조회 일치" % cutin_id,
				String(data.cg_cutin_for_discovery(discovery_id).get("id", "")) == cutin_id,
				discovery_id)
		if not act_vn_id.is_empty():
			_ok("%s 막 VN 항목 실재" % cutin_id,
				not data.act_vn_entry(act_vn_id).is_empty(), act_vn_id)
			_ok("%s VN 역조회 일치" % cutin_id,
				String(data.cg_cutin_for_vn(act_vn_id).get("id", "")) == cutin_id, act_vn_id)
		if not beat_id.is_empty():
			_ok("%s 비트 행 실재" % cutin_id, not data.vn_beat(beat_id).is_empty(), beat_id)
			_ok("%s 비트 역조회 일치" % cutin_id,
				String(data.cg_cutin_for_vn(beat_id).get("id", "")) == cutin_id, beat_id)


# ── ⑤ 조우 3종 → 대장 (판정 함수가 낼 수 있는 값 전부에 그림이 있는가) ──
#
# 발견 id 리터럴을 여기 적지 않는다 — 적으면 "표와 검사가 같은 오답을 공유"하는 자리가 생긴다.
# **판정 함수를 실제로 불러** 나오는 값을 모으고, 그 집합과 대장이 아는 집합을 맞댄다.
func _encounters_covered(data: GameData) -> void:
	var race_screen: GDScript = load(RACE_SCREEN_SCRIPT)
	var final_stage_id := String(data.season_calendar.get("fixed_final_stage", ""))
	var final_stage: Dictionary = data.stages.get(final_stage_id, {})
	var wall := String(final_stage.get("wall_rival", ""))
	var adjacent_max := int(data.param("param_jude_adjacent_max"))
	var produced: Array = []
	for value in [
		String(race_screen.l3_encounter_for(final_stage, final_stage_id, wall, true)),
		String(race_screen.l3_kinship_for("ai_jude", true, adjacent_max, adjacent_max)),
		String(race_screen.l3_reunion_for("ai_sherwood", 9, true)),
	]:
		if not value.is_empty() and not produced.has(value):
			produced.append(value)
	_ok("조우 판정 3종이 실제로 값을 낸다", produced.size() == EXPECTED_ENCOUNTER, str(produced))
	for discovery_id in produced:
		_ok("조우 '%s' 에 CG 행이 있다" % discovery_id,
			not data.cg_cutin_for_discovery(discovery_id).is_empty())
	# 역방향 — 대장이 아는 조우가 판정 함수 밖의 것이면 그 그림은 뜰 수 없다.
	for cutin_id in data.cg_cutins:
		var achievement_id := String(data.cg_cutins[cutin_id].get("source_achievement", "")).strip_edges()
		if achievement_id.is_empty():
			continue
		var discovery_id := String(data.achievements.get(achievement_id, {}).get("source_id", ""))
		_ok("대장 조우 '%s' 를 판정 함수가 낸다" % discovery_id, produced.has(discovery_id),
			str(produced))


# ── ⑥ 조회 음성 — 없는 것을 없다고 하는가 ──
func _lookup_negatives(data: GameData) -> void:
	_ok("공란 발견 id = 무조회", data.cg_cutin_for_discovery("").is_empty())
	_ok("공란 VN id = 무조회", data.cg_cutin_for_vn("").is_empty())
	_ok("미상 발견 id = 무조회", data.cg_cutin_for_discovery("cg_99_nowhere").is_empty())
	# CG 없는 VN 이 정상이다 — 1막은 그림이 없고, 있다고 답하면 전 VN 이 그림을 얻는다.
	_ok("CG 없는 막 VN = 무조회", data.cg_cutin_for_vn("vn_act1").is_empty())
	_ok("CG 없는 비트 = 무조회", data.cg_cutin_for_vn("vnbeat_crew_nadia").is_empty())
	_ok("대장 조회 중 데이터 침묵 기본값 0", data.is_ok())


# ── ⑦ 컴포넌트 계약 — 텍스처가 실제로 붙는가 · 부재를 부재라고 하는가 ──
func _component_contract(data: GameData) -> void:
	var row := data.cg_cutin_for_vn("vn_origin")
	_ok("전제: 기원 공개에 CG 행이 있다", not row.is_empty())
	if row.is_empty():
		return
	var asset := String(row["asset"])
	var present := CgCutIn.new(asset)
	_ok("컴포넌트 실물 적재", present.missing_asset.is_empty(), present.missing_asset)
	var art := present.get_node_or_null("Art") as TextureRect
	_ok("컴포넌트 텍스처 노드 실재", art != null)
	if art != null:
		_ok("컴포넌트 텍스처 비어 있지 않다", art.texture != null)
		_ok("컴포넌트 입력 비차단", present.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_ok("비지속 기본값 = 0", is_equal_approx(present.hold_sec, 0.0), str(present.hold_sec))
	present.free()
	# **경보의 자기 검사** — 부재를 부재라고 말하지 못하면 실물 누락이 빈 화면으로만 드러난다.
	var absent := CgCutIn.new("cg_00_not_a_real_asset")
	_ok("실물 부재 = 관측 지점 기록", absent.missing_asset == "cg_00_not_a_real_asset",
		absent.missing_asset)
	absent.free()
