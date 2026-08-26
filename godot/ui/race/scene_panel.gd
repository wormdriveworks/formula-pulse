# E15 레이스 씬 패널 — 컷 합성 (D09 §3.1.1 · 별첨A §127 · 사양서 v1.11 §5.2.2).
#
# **레이어 순서 = 원경 → 머신 → 근경 → 연출 요소** (사양서 §5.2.2). 근경이 머신 위인 것이
# 배경 2레이어 분리의 목적이다(§5.1 *"컷 합성용"*) — 순서를 바꾸면 분리가 무의미해진다.
#
# ── 움직임에 고를 값이 남지 않게 했다 ──
# 제원표 §3 은 요소별 움직임의 **종류**만 선언하고 진폭·주기를 비운다. 그 둘을 손으로
# 채우면 정본이 정하지 않은 수치가 코드에 앉는다(불변규칙 2). 그래서 둘 다 **파생**시킨다:
#   · 주기 = **컷이 선언한 프레임 수**(사양서 §5.2 표) ÷ **8 fps**(D13 별첨A §8.1)
#   · 진폭 = **요소 자신의 치수** — 스크롤은 제 폭만큼 흘러 한 바퀴가 정확히 맞물리고,
#     확대는 제 폭만큼 커지고, 상승은 제 높이만큼 오른다
# 진폭이 요소의 치수이므로 루프가 **구조적으로 닫힌다**(잔여 오프셋 0). 고를 값이 없다.
#
# ── 봉인 (불변규칙 5 · 사양서 §5.2.2) ──
# 릴 국면에는 **매핑 함수를 부르지 않는다.** 고정 컷을 데이터로 고르는 것이 아니라
# **결과를 보는 경로 자체가 없다** — "고정"의 구조적 형태가 그것이다.
class_name ScenePanel
extends Control

const SCENECUT_DIR := "res://assets/scenecuts/"
const MACHINE_DIR := "res://assets/machines/"
# 플레이어 머신 측면 셀 — 제원표 §5 베이스. 시즌 리버리 스왑은 씬 패널의 관심사가 아니다.
const PLAYER_MACHINE := "nw01_boreas_base_s1_side"
# 측면 셀 규격 — 제원표 §4 `[140, 30, 128, 64]` 의 폭·높이. 앵커는 데이터 창구를 거치지만
# 셀 치수는 스프라이트가 이고 있으므로 표준 자리 환산에만 쓴다.
const MACHINE_CELL := Vector2(128.0, 64.0)
# 머신 노드가 이고 있는 섀시 id — 검사·회귀의 관측 지점.
const MACHINE_SPRITE_META := "scene_machine_sprite"

# 색 치환 역할 → 팔레트 정본 색 (사양서 §5.2.1 "생성은 중립색으로 받고 팔레트는 원장이 정한다").
# **표가 선언한 역할 전부가 여기 있어야 한다** — 검사가 양방향으로 본다.
# **상수가 아니라 조회 함수다** — `SYMBOL_TROUBLE` 을 직접 참조하면 O9 색각 대체가 적용되지
# 않는다(UIOPT 축이 그 직접 참조를 잡는다). 역할 표는 이름만 이고, 색은 매 조회마다 옵션을
# 거친 값으로 받는다.
const TINT_ROLES := ["signal", "pulse"]


static func tint_color(role: String) -> Color:
	match role:
		"signal":
			return UiPalette.symbol_trouble()
		"pulse":
			return UiPalette.SYMBOL_PULSE
	return Color.WHITE

var data: GameData

var _canvas: Control
var _far: TextureRect
var _near: TextureRect
var _fx_behind: Control
var _machines: Control
var _fx_front: Control

var _cut_id := ""
var _stage_id := ""
var _frames := 1
var _elapsed := 0.0
var _motion_enabled := true
# 요소 노드 ↔ 선언 행 — 프레임마다 다시 조회하지 않는다.
var _fx_nodes: Array = []
# **미배치 관측 지점.** 컷이 머신 2대 이상을 선언했는데 배치 선언이 없다 — 조용히 1대만
# 그리지 않고 기계가 읽을 수 있게 남긴다 (`choice_omissions` 규약).
var multi_machine_omissions: Array = []
# **점유자↔섀시 결속이 아직 없다.** 자리 표는 *누가 오는가*(`occupant`)를 말하고 실제 섀시는
# 대전 상대가 정하는데, 그 결속 데이터가 어디에도 없다(`ai_rivals` 에 섀시 열 없음).
# **검수 표본을 대신 그리지 않는다** — 그것이 에셋이 IMPL-452 로 되돌린 결함 그 자체다.
# 못 그린 자리를 여기 남긴다: 조용한 1대보다 시끄러운 빈자리가 낫다.
var unbound_occupants: Array = []
# 이번 컷의 점유자 배정 — 화면 층이 넘긴다. `{"rival": [id...], "grid": [id...]}`.
# **패널은 레이스 규칙을 갖지 않는다** — 누가 인접한지·누가 그리드 몇 번인지는 화면·엔진이
# 알고, 패널은 받은 id 를 팀 표로 섀시에 옮길 뿐이다(D09 §3.1.1 "화면은 규칙을 갖지 않는다").
var _occupants: Dictionary = {}
var _rival_cursor := 0


func setup(game_data: GameData) -> void:
	data = game_data
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 비인터랙티브 (별첨A §127)
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.size = Vector2(_canvas_width(), _canvas_height())
	add_child(_canvas)
	_far = _new_layer("Far")
	_fx_behind = _new_group("FxBehind")
	_machines = _new_group("Machines")
	_near = _new_layer("Near")
	_fx_front = _new_group("FxFront")


func _new_group(group_name: String) -> Control:
	var group := Control.new()
	group.name = group_name
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(group)
	return group


func _new_layer(layer_name: String) -> TextureRect:
	var layer := TextureRect.new()
	layer.name = layer_name
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 원도 그대로 놓는다 — 408×100 캔버스에 408×100 배경이므로 신축이 없다.
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP
	_canvas.add_child(layer)
	return layer


func _canvas_width() -> float:
	return data.param("param_scene_canvas_width_px")


func _canvas_height() -> float:
	return data.param("param_scene_panel_height_px")


# 패널 실폭(데스크탑 384 안팎)이 원도 408 보다 좁다 — **가운데를 남기고 잘라낸다**
# (사양서 §5.1 "데스크탑은 384 크롭"). 왼쪽만 자르면 머신 표준 자리가 가장자리로 밀린다.
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _canvas != null:
		_canvas.position = Vector2(roundf((size.x - _canvas_width()) * 0.5), 0.0)


# 컷 전환. **같은 컷이면 되감지 않는다** — 매 턴 같은 기본 주행 컷이 서는데 그때마다
# 루프가 0 프레임으로 튀면 화면이 딸꾹질한다.
func show_cut(cut_id: String, stage_id: String, occupants: Dictionary = {}) -> void:
	if cut_id == _cut_id and stage_id == _stage_id and occupants == _occupants:
		return
	_occupants = occupants.duplicate(true)
	_cut_id = cut_id
	_stage_id = stage_id
	_frames = maxi(1, CsvTable.to_int(String(data.scene_cut(cut_id).get("frames", "1"))))
	_elapsed = 0.0
	_apply_backdrop(stage_id)
	_build_machines(cut_id)
	_build_fx(cut_id)
	_apply_frame(0)


func _apply_backdrop(stage_id: String) -> void:
	var backdrop := data.stage_backdrop(stage_id)
	if backdrop.is_empty():
		_far.texture = null
		_near.texture = null
		return
	_far.texture = load(SCENECUT_DIR + String(backdrop["far_asset"]) + ".png") as Texture2D
	_near.texture = load(SCENECUT_DIR + String(backdrop["near_asset"]) + ".png") as Texture2D


# 머신 층 — 선언된 자리에 선언된 섀시를 얹는다.
#
# **선언이 없는 컷은 표준 자리 1대다** (제원표 §4 `[140,30,128,64]`). 1대 컷은 표준 자리가
# 곧 배치이므로 선언을 요구하지 않는다 — 선언이 필요한 것은 **2대 이상의 겹침·사행**이고
# 그것은 눈 판단이다. 그래서 `machines > 1` 인데 선언이 없는 경우만 관측에 남는다.
func _build_machines(cut_id: String) -> void:
	for child in _machines.get_children():
		_machines.remove_child(child)
		child.queue_free()
	_rival_cursor = 0
	var slots := data.scene_cut_machines_for(cut_id)
	var declared := CsvTable.to_int(String(data.scene_cut(cut_id).get("machines", "1")))
	if slots.is_empty():
		if declared > 1 and not multi_machine_omissions.has(cut_id):
			multi_machine_omissions.append(cut_id)
		_place_machine(PLAYER_MACHINE,
			data.param("param_scene_machine_x") + MACHINE_CELL.x * 0.5,
			data.param("param_scene_machine_y") + MACHINE_CELL.y * 0.5)
		return
	for row in slots:
		var sprite := _chassis_for(String(row["occupant"]), String(row["slot_name"]))
		if sprite.is_empty():
			var mark := "%s/%s" % [cut_id, String(row["slot_name"])]
			if not unbound_occupants.has(mark):
				unbound_occupants.append(mark)
			continue
		# **셀 중심 = 노면선 − 바닥 오프셋** (총괄 판정 ② ⓑ)
		_place_machine(sprite, float(CsvTable.to_int(String(row["anchor_x"]))),
			float(CsvTable.to_int(String(row["anchor_road_y"]))
				- data.machine_baseline(sprite)))


# 점유자 → 섀시 (33차 결선 — 팀↔섀시 결속 유입 후).
#
#   · `player` — 플레이어 머신. **성장 단계는 아직 상태에 없다**(아웃게임에 머신 단계 축이
#     부재) → 1단계 고정. 단계가 서면 이 한 줄이 답한다.
#   · `rival`  — 화면이 넘긴 상대 id 를 **자리 순서대로** 소비한다. 팀이 차를 갖는다.
#   · `grid`   — 자리 이름이 곧 순위다(`p1`~`p4` — 도구 명문 "grid = 자리가 순위").
#     이름을 파싱하는 것은 **선언된 부호**를 읽는 것이고, 그 부호의 형태는 검사가 못박는다.
#
# **넘겨받은 것이 없으면 빈 문자열이다** — 없는 상대를 그리지 않는다.
func _chassis_for(occupant: String, slot_name: String) -> String:
	match occupant:
		"player":
			return PLAYER_MACHINE
		"rival":
			return _from_ids(Array(_occupants.get("rival", [])), _next_rival_index())
		"grid":
			return _from_ids(Array(_occupants.get("grid", [])), _grid_rank(slot_name) - 1)
	return ""


# 자리 이름의 선행 `p<숫자>` = 그리드 순위. 형태가 아니면 −1 (해석 불가 = 미결속).
func _grid_rank(slot_name: String) -> int:
	if not slot_name.begins_with("p"):
		return -1
	var digits := ""
	for index in range(1, slot_name.length()):
		if not slot_name[index].is_valid_int():
			break
		digits += slot_name[index]
	return digits.to_int() if digits != "" else -1


func _from_ids(ids: Array, index: int) -> String:
	if index < 0 or index >= ids.size():
		return ""
	return data.rival_chassis(String(ids[index]))


# 이 컷에서 몇 번째 rival 자리인가 — 그리는 동안 증가한다.
func _next_rival_index() -> int:
	var used := _rival_cursor
	_rival_cursor += 1
	return used


func _place_machine(sprite: String, center_x: float, center_y: float) -> void:
	var node := TextureRect.new()
	# **이름으로 정체를 싣지 않는다.** 같은 섀시가 두 자리에 서면(프라이비티어 공용 — 실버
	# 트레일·코멧웍스가 같은 차다) 엔진이 이름을 `@TextureRect@N` 으로 갈아 버려 정체가
	# 사라진다. 33차 반증에서 실제로 그 모양이 나왔다 — 메타로 싣는다.
	node.name = "Machine"
	node.set_meta(MACHINE_SPRITE_META, sprite)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP
	var texture := load(MACHINE_DIR + sprite + ".png") as Texture2D
	if texture == null:
		push_error("ScenePanel: machine sprite '%s' not found" % sprite)
		node.queue_free()
		return
	node.texture = texture
	node.size = texture.get_size()
	node.position = Vector2(center_x, center_y) - texture.get_size() * 0.5
	_machines.add_child(node)


func _build_fx(cut_id: String) -> void:
	for group in [_fx_behind, _fx_front]:
		for child in group.get_children():
			group.remove_child(child)
			child.queue_free()
	_fx_nodes.clear()
	for row in data.scene_cut_layers_for(cut_id):
		var element := data.fx_element(String(row["element_id"]))
		if element.is_empty():
			continue
		var node := TextureRect.new()
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		node.stretch_mode = TextureRect.STRETCH_KEEP
		var cell := Vector2i(
			CsvTable.to_int(String(element["cell_w"])), CsvTable.to_int(String(element["cell_h"])))
		var texture := load(SCENECUT_DIR + String(element["asset"]) + ".png") as Texture2D
		# 시트(E-04)는 대표 프레임 한 칸만 쓴다 — `still_frame` 소비 (사양서 §5.1 정지 폴백).
		if texture != null and CsvTable.to_int(String(element["frames"])) > 1:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(
				cell.x * CsvTable.to_int(String(element["still_frame"])), 0, cell.x, cell.y)
			texture = atlas
		node.texture = texture
		node.size = Vector2(cell)
		# 앵커는 **요소의 중심**이다 — 좌상단으로 두면 크기가 다른 요소들의 자리가
		# 같은 뜻을 갖지 못한다(확대 모션도 중심 기준이어야 제자리에서 커진다).
		node.pivot_offset = Vector2(cell) * 0.5
		node.position = Vector2(
			CsvTable.to_int(String(row["anchor_x"])), CsvTable.to_int(String(row["anchor_y"]))
		) - node.pivot_offset
		var tint := String(row.get("tint", "")).strip_edges()
		if not tint.is_empty() and TINT_ROLES.has(tint):
			node.modulate = tint_color(tint)
		# z 대역 = **요소가 선언한다** (총괄 판정 ③). 컷이 정하면 같은 불꽃이 컷마다
		# 다른 자리에 보인다 — 재사용이 설계라는 §5.2 논거가 곧 이 선언 자리의 근거다.
		var band := String(element.get("z_band", "front"))
		(_fx_behind if band == "behind" else _fx_front).add_child(node)
		_fx_nodes.append({"node": node, "element": element, "base": node.position,
			"cell": cell, "tint": node.modulate})


# 릴 국면 저강조 = **감광** (D09 §3.1.1 · 별첨A §127 · D13 별첨A §8.1 v1.12 = **0.70**).
#
# 29차에 값이 없어 비워 둔 자리다 — 그때 `param_fx_reduced_mult`(0.5)를 빌리지 않은 것은
# 그것이 **접근성 감쇠 축**이기 때문이고, D13 이 신설 행에 *"접근성 감쇠 축과 별개 축"* 을
# 명기해 그 판단을 확인해 줬다. **없는 값을 채우지 않고 기다린 자리가 정본으로 닫혔다.**
#
# 값이 0.70 인 근거도 눈이 냈다(주력 15차 4안 실기 — 0.50 은 대비 3.97:1 로 팔레트 정본
# 가독 바닥 4.5:1 미달). 헤드리스가 정할 수 없는 종류의 값이었다.
func set_dim(dimmed: bool) -> void:
	var level := data.param("param_scene_panel_dim") if dimmed else 1.0
	# 회색 곱연산 — 색을 칠하는 것이 아니라 밝기를 내린다(PAL 문맥 제외 축과 같은 성격).
	modulate = Color(level, level, level)


# O12 '씬 패널 모션: 표준 / 정지 컷' (D09 §6.1 — 접근성 폴백).
func set_motion_enabled(enabled: bool) -> void:
	_motion_enabled = enabled
	if not enabled:
		_apply_frame(0)


func _process(delta: float) -> void:
	if not _motion_enabled or _fx_nodes.is_empty():
		return
	_elapsed += delta
	_apply_frame(int(_elapsed * data.param("param_scene_cut_fps")) % _frames)


# 프레임 적용 — 진폭은 요소 치수, 주기는 컷 프레임 수. 머리말의 파생 규칙 그대로다.
func _apply_frame(frame: int) -> void:
	var phase := float(frame) / float(_frames)
	for entry in _fx_nodes:
		var node: TextureRect = entry["node"]
		var cell: Vector2i = entry["cell"]
		var base: Vector2 = entry["base"]
		node.position = base
		node.scale = Vector2.ONE
		node.modulate = entry["tint"]
		node.visible = true
		match String(Dictionary(entry["element"])["motion"]):
			"scroll_x":
				node.position = base + Vector2(cell.x * phase, 0.0)
			"rise":
				node.position = base - Vector2(0.0, cell.y * phase)
				node.modulate.a = 1.0 - phase
			"fade":
				node.scale = Vector2(1.0 + phase, 1.0)
				node.modulate.a = 1.0 - phase
			"expand":
				node.scale = Vector2.ONE * (1.0 + phase)
				node.modulate.a = 1.0 - phase
			"pulse":
				# 맥동 = 왕복이다. 한 바퀴에 1→2→1 이어야 루프가 닫힌다(단조 증가는 튄다).
				var swing := 1.0 - absf(phase * 2.0 - 1.0)
				node.scale = Vector2.ONE * (1.0 + swing)
			"blink":
				node.visible = frame % 2 == 0   # 불투명도 2단 (제원표 §3)
			"still":
				pass
