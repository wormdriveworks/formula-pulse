# 스토어 스크린샷 5매 + 감광 후보 비교 캡처 (주력 GUI 머신 전속 — 눈 검증 경로).
#
#   <console.exe> --path godot --script tests/capture_store_shots.gd -- <출력 디렉토리> [dim|vn]
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

# 스토어 컷 = 1막 개막 VN. **양쪽 슬롯이 인물로 채워지는 첫 라인**을 고른다(마르타 좌 →
# 테오 우). 접미 없는 막 VN 이라 인스턴스 id 가 곧 표 실체 id 다(`_act_vn_payload` 와 동형).
const VN_STORE_SCENE := "vn_act1"
const VN_STORE_LINE := 2

# ── VN 4층 판독 소재 (총괄 관측 대장 · 원격 [가안]·차용 판단의 눈 폐문) ──
#
# 각 항목 = [파일명, 장면 id, 라인 색인]. 장면·라인을 **표에서 고른다** — 리터럴 문면 키를
# 적으면 표가 바뀔 때 컷만 조용히 낡는다(듀얼 상대를 표에서 고른 것과 같은 자리).
#
#   ① ② 좌우 점유 교대 — `clue_silence` 는 3인 2자리다(테오 → 사샤가 우측을 쥔다).
#      **두 장이 한 축이다**: 교대는 한 프레임으로 읽히지 않는다.
#   ③ CG 차폐 + 해빙 차분 — `crew_sasha` 가 둘을 한 장에 진다(그 장면 전용 차분 · CG 실재).
#   ④ ⑤ 베인 파형 자리와 **그 뒤 인물 복귀** — 36차 거울상 교정의 실물 확인분.
#   ⑥ ⑦ 남은 CG 장면 둘 — **차폐는 한 장으로 판정할 수 없다.** 한 원도가 우연히 겹친 것과
#      공존 규칙이 없는 것은 3장면을 다 봐야 갈린다(CG 있는 VN = 정확히 3종).
#      ⚠ **판독 전제 정정 (총괄 IMPL-484 §1 등재).** 36차는 형제 규약을 *"CG = 장소·사물,
#      인물은 스탠딩"* 으로 적었는데 **그런 정본 문면은 없고**(grep 0 — D10 §7 은 구도를
#      구속하지 않는다), 실체는 *"인물 없음"* 이 아니라 **"얼굴 없음"** 이다(cg01 관중·
#      cg06 군중이 실재한다 — A-CG-02 '맨얼굴 금지'). 결론은 그대로다: cg06 은 얼굴이
#      0 이라 스탠딩과 충돌하지 않는다. 실루엣까지 위반으로 읽지 않기 위한 정정이다.
const VN_LAYER_PLAN := [
	["vn1_handover_before", "vnbeat_clue_silence", 1],
	["vn2_handover_after", "vnbeat_clue_silence", 4],
	["vn3_cg_thaw", "vnbeat_crew_sasha", 4],
	["vn4_waveform", "vn_act1", 6],
	["vn5_waveform_back", "vn_act1", 8],
	["vn6_cg_origin", "vn_origin", 4],
	["vn7_cg_champion", "vn_epilogue", 2],
]

# ⑧ 아카이브 재열람 — **기록실이 넘기는 페이로드 그대로**다(`records_screen.gd` 실독:
# `{"vn_id", "replay", "next"}` — `line_keys` 없음). 라인 원천을 붙이지 않는 것이 이 컷의
# 요점이므로 위 계획과 세우는 함수를 갈랐다.
const VN_ARCHIVE_SCENE := "vnbeat_crew_sasha"

const WATCHDOG_MSEC := 180000
const SETTLE_FRAMES := 6

var _out_dir := ""
var _dim_mode := false
var _vn_mode := false
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
	_vn_mode = args.size() >= 2 and String(args[1]) == "vn"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_data = GameData.new()
	if not _data.load_all():
		printerr("STORESHOT_FAIL 데이터 적재 실패")
		_finish(1)
		return
	_pending = _vn_plan() if _vn_mode else (_dim_plan() if _dim_mode else _store_plan())
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




# VN 4층 판독 — `_dim_plan` 과 같은 형태다(계획은 파일명만 이고, 세팅 인자는 `_step` 으로
# 계획표를 되짚는다). 산출은 스토어 소재가 아니라 **눈 판정 소재**라 출력 디렉토리가 다르다.
func _vn_plan() -> Array:
	var plan: Array = []
	for row in VN_LAYER_PLAN:
		plan.append([String(row[0]), "_stage_vn_layer"])
	plan.append(["vn8_archive_replay", "_stage_vn_archive"])
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


# ── ㊶ RACE-03 정산 컷 — **엔진에게 실제로 달리게 한다** ──
#
# 15차는 이 컷을 3/5 에서 뺐다. 페이로드로 순위를 적어도 화면이 읽는 곳은
# `session.last_gp_result`(엔진 산출)라 전건 0 이 나왔기 때문이다 — 그때 적은 사유가
# *"엔진 있는 문맥이 선행"* 이었고, 총괄은 실플레이 회차 겸행으로 배정했다.
#
# **그런데 엔진 구동에 사람이 필요하지 않다.** GP 진행은 전건 동기 호출이고(프레임 의존 0 —
# 불변규칙 8 의 귀결) TL-5 러너가 이미 그 경로로 시즌을 관통한다. 그래서 **러너와 같은
# 경로**로 실제 판을 완주시키고 그 결과 화면을 찍는다 — 손으로 적은 숫자가 아니라 코어가
# 계산한 숫자다.
#
# **진행이 없으면 정산이 비어 보인다.** 시드 12개를 훑어도 개막 GP 는 P12~P15 밖으로 나가지
# 않는다(실측) — 시드 문제가 아니라 진행도 문제다. 개막 판의 정산은 정직하지만 게임을
# 보여주지 못한다(전건 0포인트).
#
# **그런데 시드로 고정할 수가 없다.** `begin_career()` 가 내부에서 마스터 시드를 뽑고 그
# 자리에서 시즌·투어까지 세운다 — 우리가 `rng.setup()` 을 쥐는 시점은 **투어 1이 이미 뽑힌
# 뒤**다. 그래서 같은 시드로도 앞선 판들이 갈리고, 5판째 순위가 실측 P3 에서 P15 로 튀었다.
# **고정할 수 없는 값을 고정한 척하는 것이 더 나쁘다** — 재현되는 것처럼 보이고 재현되지 않는다.
#
# 그래서 **값이 아니라 조건을 고정한다**: 첫 시상대 정산에서 멈춘다. 어느 판인지는 판마다
# 다르고, 그 컷이 시상대라는 것은 언제나 참이다.
const SETTLE_TARGET_RANK := 3
const SETTLE_MAX_GP := 20
const SETTLE_ATTEMPTS := 4
# 개입·완급을 최대로 둔다 — 스토어 컷은 *잘 달린 한 판*이어야 한다. 정책일 뿐이고
# 절단·상한·순위는 전부 코어가 쥔다(러너와 같은 분담).
const SETTLE_MOMENTUM := 1.0
const SETTLE_TUNING_ORDER := ["tuning_t1", "tuning_t2", "tuning_t4", "tuning_t3"]
const DRIVE_GUARD := 400


func _stage_gp_result() -> Control:
	var session: RunSession = null
	var reached := false
	for attempt in range(SETTLE_ATTEMPTS):
		session = _rich_session(1)
		if _drive_to_podium(session):
			reached = true
			break
	if session == null or session.last_gp_result.is_empty():
		printerr("STORESHOT_FAIL GP 결과 부재")
		return null
	if not reached:
		# **조용히 못 미치지 않는다** — 시상대 없이 찍힌 컷은 스토어 소재가 아니다.
		printerr("STORESHOT_WARN 시상대 미도달 %d수 (마지막 P%d)" % [
			SETTLE_ATTEMPTS, int(session.last_gp_result.get("player_rank", 0))])
	print("SETTLE rank=%d points=%d chassis=%d charge=%d" % [
		int(session.last_gp_result.get("player_rank", 0)),
		int(session.last_gp_result.get("tour_points", 0)),
		int(session.engine.chassis), int(session.engine.charge),
	])
	return _mount(RESULT_SCENE, session)


# TL-5 러너 `_run_tour` 의 전사다 — **경로를 줄이지 않는다.** 초판은 GP 만 이어 붙이고
# 필드 정비·이벤트 노드·리타이어 표기·투어 정산을 뺐다. 그러자 4판 누적 소모가 복원선을
# 넘어 **20판 전건 미도달·섀시 0** 이 됐다(실측). 러너가 이미 그 주석을 달아 뒀다 —
# *"이 경로가 없으면 4GP 누적 소모가 복원선을 넘어 매 투어 리타이어한다(실플레이와 다른 경로)"*.
# 즉 빠진 것은 정책이 아니라 **실플레이가 반드시 지나는 경로**였다.
func _drive_to_podium(session: RunSession) -> bool:
	var gp := 0
	while gp < SETTLE_MAX_GP and not session.season.season_finished():
		_shop(session)   # 투어 개시 정비·구매 — TL-5 러너의 그리디 정책 그대로
		while gp < SETTLE_MAX_GP and session.tour_has_remaining_gp():
			gp += 1
			if not session.begin_gp():
				return false
			session.engine.start_gp()
			_drive_gp(session)
			session.close_gp()
			var rank := int(session.last_gp_result.get("player_rank", 0))
			var retired := bool(session.last_gp_result.get("player_retired", false))
			if rank > 0 and rank <= SETTLE_TARGET_RANK and not retired:
				# **여기서 정산하지 않는다** — 지급 창구가 RACE-03 안에 있다
				# (`_on_bound` 이 `settle_gp()` 를 부른다). 먼저 부르면 두 번 지급된다.
				return true
			session.settle_gp()
			if retired:
				session.season.mark_dropout()   # 실플레이는 RACE-03 이 이 표기를 한다
				break
			var event := session.judge_event()
			if not event.is_empty():
				session.apply_event_reward(event.get("reward", {}))
			_field_service(session)
		var remaining_charge: int = session.engine.charge if session.engine != null else 0
		session.close_tour()
		session.settle_tour(remaining_charge)
	return false


# GP 사이 간이 정산 (D07 §1.2) — 러너 `_field_service` 의 전사.
func _field_service(session: RunSession) -> void:
	var outgame := session.outgame
	var cap := _data.param_int("param_repair_field_cap")
	while outgame.chassis < float(outgame.free_restore_line()):
		if outgame.field_repair(cap) <= 0:
			break   # 크레딧 부족 또는 회복 여지 소진
	var carried := 0
	for held in outgame.consumables:
		carried += int(outgame.consumables[held])
	while carried < _data.param_int("param_consumable_carry_cap"):
		if not outgame.buy_consumable("consumable_p1"):
			break
		carried += 1


# 투어 사이 구매 — TL-5 러너 `_shop` 의 전사다. **정책만 여기 있고 절단·상한·체증은 전부
# 코어가 쥔다**(러너와 같은 분담). 정본 수치를 새로 만들지 않는다.
func _shop(session: RunSession) -> void:
	var outgame := session.outgame
	var bought := true
	while bought:
		bought = false
		for skill_id in _data.skills:
			if outgame.unlocked_skills.has(skill_id):
				continue
			if outgame.unlock_skill(String(skill_id)):
				bought = true
	if outgame.chassis < _data.param("param_chassis_max"):
		outgame.full_repair()
	bought = true
	while bought:
		bought = false
		for tuning_id in SETTLE_TUNING_ORDER:
			if outgame.buy_tuning(String(tuning_id)):
				bought = true


# TL-5 러너 `_drive_gp` 의 축소판 — 정책 난수를 빼고 **항상 개입·항상 완급 성공**으로 둔다.
# 러너 쪽은 정책 분포를 재는 것이 목적이라 확률이 필요하지만, 여기서는 한 판의 그림이 목적이다.
func _drive_gp(session: RunSession) -> void:
	var engine: RaceEngine = session.engine
	var guard := DRIVE_GUARD
	while not engine.finished and guard > 0:
		guard -= 1
		var info := engine.begin_turn()
		if String(info.get("type", "")) == "finished":
			break
		engine.spin()
		if String(info.get("type", "")) == "duel":
			while bool(engine.add_duel_boost().get("ok", false)):
				pass
		else:
			var provisional := engine.get_provisional()
			if engine.charge >= 2 and provisional.has(RaceTypes.SYMBOL_TROUBLE):
				engine.negate_trouble()
			if engine.charge >= 3:
				var keep: Array = []
				var current := engine.get_provisional()
				for index in range(3):
					if current[index] != RaceTypes.SYMBOL_TROUBLE:
						keep.append(index)
				if keep.size() < 3:
					engine.hold_respin(keep)
		engine.confirm(SETTLE_MOMENTUM)
	if guard <= 0:
		printerr("STORESHOT_FAIL GP 구동 상한 초과")

# ④ 스토어 VN 컷 — **생산 경로와 같은 형태로 세운다.** 초판은 페이로드를 손으로 적었고
# (`vn_id = "vn_act1_open"` · 라인 1줄) 그래서 바탕도 스탠딩도 서지 않았다: 그 id 는 표에
# 없는 이름이었고, 문자열 라인은 화자를 잃어 전건 기본 화자(베인)로 떨어진다. 표에서 꺼내면
# 그 둘이 함께 성립한다 — `_act_vn_payload()` 가 하는 일과 같다.
func _stage_vn() -> Control:
	return _stage_vn_scene(VN_STORE_SCENE, VN_STORE_LINE)


func _stage_vn_layer() -> Control:
	var row: Array = VN_LAYER_PLAN[_step]
	return _stage_vn_scene(String(row[1]), int(row[2]))


# 기록실 재열람 경로 — **호출부가 실제로 쓰는 창구를 부른다.** 36차 초판은 기록실이 그때
# 넘기던 사전(`{vn_id, replay, next}`)을 손으로 적었고, 그것이 문면 공백(㊹)의 증거였다.
# 원격이 그 결함을 고쳐 조립을 `archive_replay_payload()` 로 옮겼으므로, 손으로 적은
# 사전은 이제 **생산에 없는 형태**다 — 그대로 두면 하네스가 고쳐진 결함을 계속 그린다.
# 이것이 16차 VN 컷과 같은 교훈의 두 번째 자리다: **컷은 생산 경로를 지나야 한다.**
func _stage_vn_archive() -> Control:
	var session := _rich_session(1)
	var payload := session.archive_replay_payload(VN_ARCHIVE_SCENE, "HUB-05")
	if payload.is_empty():
		printerr("STORESHOT_FAIL 재열람 페이로드 조회 실패: %s" % VN_ARCHIVE_SCENE)
		return null
	return _mount(VN_SCENE, session, payload)

# 재열람 경로로 세운다 — 슬롯 발생 판정·상한을 거치지 않으므로 어떤 장면이든 그대로 선다.
func _stage_vn_scene(scene_id: String, line_index: int) -> Control:
	var lines := _vn_lines(scene_id)
	if lines.is_empty():
		printerr("STORESHOT_FAIL VN 라인 부재: %s" % scene_id)
		return null
	var screen := _mount(VN_SCENE, _rich_session(1), {
		"replay": true, "vn_id": scene_id, "scene_id": scene_id, "line_keys": lines,
	})
	if screen == null:
		return null
	_seek_line(screen, line_index)
	return screen


# 장면 원천이 둘이다 — 막 VN 은 구조 파일, 비트는 라인 표. **조회처를 가르지 않고 합친다**:
# 컷 계획이 어느 원천인지 알아야 하면 계획이 데이터 구조를 따라 낡는다.
func _vn_lines(scene_id: String) -> Array:
	var entry := _data.act_vn_entry(scene_id)
	if not entry.is_empty():
		return entry.get("lines", [])
	return _data.vn_beat_lines_for(scene_id)


# 스탠딩은 **누적 점유**다(자리를 그 자리 최근 발화자가 쥔다). 목표 라인으로 뛰면 좌측이
# 비고, 빈 좌측은 그림에서 *"화자 고정 규칙이 일하지 않았다"* 와 구분되지 않는다.
# 그래서 첫 줄부터 순서대로 흘려 그 지점의 점유를 실제로 만든다.
func _seek_line(screen: Control, target: int) -> void:
	var last: int = mini(target, screen._lines.size() - 1)
	for index in range(last + 1):
		screen._line_index = index
		screen._show_line()


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
