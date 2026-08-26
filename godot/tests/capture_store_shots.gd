# 스토어 스크린샷 5매 + 감광 후보 비교 캡처 (주력 GUI 머신 전속 — 눈 검증 경로).
#
#   <console.exe> --path godot --script tests/capture_store_shots.gd -- <출력 디렉토리> [dim]
#
# `--headless` 를 붙이면 렌더 결과가 비므로 붙이지 않는다(캡처 하네스 공통 규약).
#
# **왜 관통 걷기(`capture_flow_walk`)를 쓰지 않는가** — 그쪽은 VN 에서 입력을 기다려 멈춘다
# (실측: 180초 예산에서 3컷 뒤 타임아웃). 스토어 소재는 *특정 국면의 좋은 한 컷*이 필요한
# 것이지 관통이 필요한 것이 아니므로, 화면을 직접 세우고 그 국면을 만든다.
#
# 산출 규격 = **1920×1080** (D15 §2.2-3 · 배치 대장). 프로젝트가 640×360 뷰포트에 창
# 오버라이드 1920×1080 을 두므로 루트 텍스처가 그대로 정수 3배다(실측 확인).
#
# 두 번째 인자 `dim` 을 주면 **㊲ 감광 배율 후보**를 찍는다 — 릴 국면 씬 패널에 후보 배율을
# 걸어 같은 프레임을 여러 장 남긴다. 값이 서면 코드 한 줄이므로, 여기서 정하는 것이 아니라
# **비교할 그림을 만든다.**
extends SceneTree

const RACE_SCENE := "res://ui/race/race_screen.tscn"
const GARAGE_SCENE := "res://ui/hub/garage_screen.tscn"
const RESULT_SCENE := "res://ui/race/gp_result_screen.tscn"
const VN_SCENE := "res://ui/nar/vn_screen.tscn"
const SCENE_PANEL_NAME := "ScenePanel"

# 감광 후보 — 총괄 인계 ② 의 예시대로 3안 + 대조군(무감광 1.0).
const DIM_CANDIDATES := [1.0, 0.7, 0.6, 0.5]

const WATCHDOG_MSEC := 180000
const SETTLE_FRAMES := 6

var _out_dir := ""
var _dim_mode := false
var _started_msec := 0
var _data: GameData
var _shots := 0
var _done := false
var _step := 0
var _settle := 0
var _current: Control
var _pending: Array = []


func _initialize() -> void:
	SaveManager.use_test_root()   # 저장 격리 — 실 프로필 무접촉 (25차)
	_started_msec = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("STORESHOT_FAIL 출력 디렉토리 미지정")
		_finish(1)
		return
	_out_dir = args[0]
	_dim_mode = args.size() >= 2 and String(args[1]) == "dim"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_data = GameData.new()
	if not _data.load_all():
		printerr("STORESHOT_FAIL 데이터 적재 실패")
		_finish(1)
		return
	_pending = _dim_plan() if _dim_mode else _store_plan()
	# **첫 마운트를 `_initialize()` 에서 하지 않는다.** 그 시점의 `root` 에 붙인 노드는
	# `_ready()` 가 돌지 않아 `@onready` 가 전부 null 이고, 화면은 *"get_child on null"* 로
	# 무너진다(실측). UISCR 이 첫 프레임에 세우는 것과 같은 이유다 — 한 프레임 기다린다.


# ── 계획 ──
#
# 각 항목 = [파일명, 세우는 함수 이름]. **한 항목이 한 컷**이고 세팅은 그 함수가 진다.
func _store_plan() -> Array:
	return [
		["shot1_race_intervention", "_stage_race_intervention"],
		["shot2_race_duel", "_stage_race_duel"],
		["shot3_gp_result", "_stage_gp_result"],
		["shot4_vn", "_stage_vn"],
		["shot5_garage", "_stage_garage"],
	]


func _dim_plan() -> Array:
	var plan: Array = []
	for value in DIM_CANDIDATES:
		plan.append(["dim_%03d" % int(float(value) * 100.0), "_stage_dim"])
	return plan


func _rich_session(career_slot: int) -> RunSession:
	var session := RunSession.new()
	session.setup(_data)
	session.begin_career(career_slot)
	# 스토어 컷은 **잠금 표기가 아니라 게임이 보여야 한다** — 크루·재화·덱을 실제 진행분
	# 근처로 올린다. 세이브는 격리 루트라 실 프로필과 무관하다.
	for crew_id in ["crew_theo", "crew_marta", "crew_oscar", "crew_nadia", "crew_sasha"]:
		session.outgame.crew[crew_id] = true
	session.outgame.gain_credits(2400)
	session.outgame.gain_drive_data(600)
	# **온보딩 툴팁은 스토어 컷에 끼면 안 된다** — 1회성 안내가 스테이션 2개를 덮는다(실측).
	# 초기화(`reset_onboarding`)의 반대편 창구를 그대로 쓴다.
	for tip_id in ["currency", "tut01"]:
		session.options.mark_onboarding(String(tip_id))
	return session


func _mount(scene_path: String, session: RunSession, payload: Dictionary = {}) -> Control:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		printerr("STORESHOT_FAIL 씬 로드 실패: %s" % scene_path)
		return null
	var screen := packed.instantiate() as Control
	screen.session = session
	root.add_child(screen)
	screen.bind(session, payload)
	return screen


# ── 국면 세팅 ──
#
# **개입 창을 손으로 연다.** 릴 정지 연출은 `await` 라 프레임 구동 하네스에서 기다리면
# 컷마다 초를 먹는다 — 여기서 필요한 것은 *그 국면의 화면*이지 그 국면에 도달한 이력이 아니다.
func _open_intervention(screen: Control) -> void:
	var engine: RaceEngine = screen.engine
	engine.turn_phase = RaceTypes.TurnPhase.T4_INTERVENTION
	engine.provisional = ["symbol_pulse", "symbol_line", "symbol_slipstream"]
	engine.charge = 6
	screen._timer_active = true
	screen._revealing = false
	screen._timer_remaining = screen._timer_effective_base * 0.72
	for index in range(3):
		screen._reel_icons[index].texture = screen._icon_texture(String(engine.provisional[index]))
	screen._refresh_action_enabled()
	screen._refresh_resources()


func _stage_race_intervention() -> Control:
	var screen := _mount(RACE_SCENE, _rich_session(1))
	if screen == null:
		return null
	screen.engine.deck = ["skill_sh1", "skill_sc1", "skill_sa1"]
	_open_intervention(screen)
	screen._show_reel_phase_cut()
	return screen


func _stage_race_duel() -> Control:
	var screen := _mount(RACE_SCENE, _rich_session(1))
	if screen == null:
		return null
	var engine: RaceEngine = screen.engine
	# 상대는 **표에서 고른다** — 리터럴 id 를 적으면 표가 바뀔 때 조용히 빈 컷이 된다.
	var opponent_id := ""
	for id in engine.entrants:
		if String(id) != RaceEngine.PLAYER_ID:
			opponent_id = String(id)
			break
	if opponent_id.is_empty():
		printerr("STORESHOT_FAIL 듀얼 상대 부재")
		return screen
	engine.deck = ["skill_sh1", "skill_sc1", "skill_sa1"]
	engine.current_turn_is_duel = true
	engine.duel_opponent = opponent_id
	# **듀얼 진입이 먼저다** — `_enter_duel` 이 `_reel_icons` 를 오버레이의 것으로 갈아치우므로,
	# 순서를 뒤집으면 심볼을 본체 릴에 그려 놓고 빈 오버레이를 찍는다(초판 실측).
	screen._enter_duel({"opponent": opponent_id, "duel_type": 0})
	_open_intervention(screen)
	screen._refresh_boost()
	return screen


func _stage_gp_result() -> Control:
	return _mount(RESULT_SCENE, _rich_session(1), {"rank": 4, "retired": false})


func _stage_vn() -> Control:
	# 재열람 경로 — 슬롯 발생 판정을 거치지 않고 한 장면을 그대로 세운다.
	return _mount(VN_SCENE, _rich_session(1),
		{"replay": true, "vn_id": "vn_act1_open", "line_keys": ["vn.act1.beat01"]})


func _stage_garage() -> Control:
	return _mount(GARAGE_SCENE, _rich_session(2))


# ㊲ 감광 후보 — 릴 국면 화면을 세우고 씬 패널에만 배율을 건다.
# **패널에만 건다**: 릴·액션 열·로그는 그대로여야 "패널이 얼마나 물러나는가"를 볼 수 있다.
func _stage_dim() -> Control:
	var screen := _stage_race_intervention()
	if screen == null:
		return null
	var panel := screen.find_child(SCENE_PANEL_NAME, true, false) as Control
	if panel == null:
		printerr("STORESHOT_FAIL 씬 패널 부재")
		return screen
	var value := float(DIM_CANDIDATES[_step])
	panel.modulate = Color(value, value, value)
	return screen


# ── 구동 ──
func _advance() -> void:
	if _current != null:
		root.remove_child(_current)
		_current.queue_free()
		_current = null
	if _step >= _pending.size():
		print("STORESHOT_OK shots=%d" % _shots)
		_finish(0)
		return
	_current = call(String(_pending[_step][1]))
	if _current == null:
		printerr("STORESHOT_FAIL 화면 세우기 실패 (step=%d)" % _step)
		_finish(1)
		return
	_settle = 0


func _process(_delta: float) -> bool:
	if _done:
		return true
	if Time.get_ticks_msec() - _started_msec > WATCHDOG_MSEC:
		printerr("STORESHOT_FAIL 하네스 예산 초과 %dms (step=%d)" % [WATCHDOG_MSEC, _step])
		_finish(1)
		return true
	if _current == null:
		if _step >= _pending.size():
			print("STORESHOT_OK shots=%d" % _shots)
			_finish(0)
			return true
		_advance()
		return false
	_settle += 1
	if _settle < SETTLE_FRAMES:
		return false
	var img := root.get_texture().get_image()
	if img == null:
		printerr("STORESHOT_FAIL 뷰포트 이미지 없음")
		_finish(1)
		return true
	var path := "%s/%s.png" % [_out_dir, String(_pending[_step][0])]
	if img.save_png(path) != OK:
		printerr("STORESHOT_FAIL 저장 실패: %s" % path)
		_finish(1)
		return true
	_shots += 1
	print("SHOT %dx%d %s" % [img.get_width(), img.get_height(), path])
	_step += 1
	_advance()
	return false


func _finish(code: int) -> void:
	_done = true
	quit(code)
