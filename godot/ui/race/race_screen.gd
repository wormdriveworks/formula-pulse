# RACE-01 레이스 화면 — D09 §3 / 별첨A §A-6의 실화면.
#
# 4존 골격(D09 §3.1): A 레이스 스트립 / B0 레이스 씬 패널 / B 릴·개입 존 / C 로그 피드 / D 자원 바.
# 좌 = 조작·베인(릴 국면) · 우 = 서사·중계(전개 국면) — D04 §8.1 국면 분리의 화면 번역이다.
#
# **국면 분리 이행 (D09 §3.1 — MS-1 디버그 UI가 어긴 지점):** 베인 발화(`vane.*`)는 릴 존
# 콜아웃 전속이며 로그 피드에 흐르지 않는다. 중계(`raceLog.*`)만 C존으로 간다.
# 개입 창 중 시선이 릴 존을 떠나지 않게 하는 10초 성립 원칙(D09 §1.4)의 장치다.
#
# **봉인 (불변규칙 5 · D12 §6.3):** 스핀 결과는 릴 정지 연출이 끝나기 전 어떤 표시 경로에도
# 나오지 않는다. 리스핀도 같다 — 재정지분은 순차 정지를 다시 재생한다(IMPL-019 이월분 해소).
#
# **세이브는 SaveManager 경유** (IMPL-037 · ARCH 정적 규칙). SaveService 직접 호출은 빌드가 막는다.
# **표시 문자열은 전량 스트링 키** (V4 — 서식 문자열 포함).
extends FlowScreen

const REEL_COUNT := 3
const HOLD_KEYS := [KEY_1, KEY_2, KEY_3]
const ICON_DIR := "res://assets/ui/icons/"

var _icon_cache: Dictionary = {}

var data: GameData
var rng: RngService
var engine: RaceEngine

var _timer_active := false
var _timer_remaining := 0.0
var _timer_base := 10.0
var _timer_effective_base := 10.0
var _timer_disabled := false
var _revealing := false
var _confirm_lockout := 0.0
var _lockout_base := 0.3

var _reel_icons: Array[TextureRect] = []
var _reel_panels: Array[PanelContainer] = []
var _hold_boxes: Array[CheckBox] = []
var _skill_buttons: Array[Button] = []

@onready var _e01_position: Label = %E01Position
@onready var _e02_lap_sector: Label = %E02LapSector
@onready var _e02_corner: Label = %E02Corner
@onready var _e02_attr: TextureRect = %E02SectorAttr
@onready var _e02_resonance: Label = %E02Resonance
@onready var _e03_front: ProgressBar = %E03FrontGauge
@onready var _e03_rear: ProgressBar = %E03RearGauge
@onready var _e04_timer_ring: Control = %E04TimerRing
@onready var _e04_timer_value: Label = %E04TimerValue
@onready var _e05_reels: HBoxContainer = %E05Reels
@onready var _e07_wave: Control = %E07VaneWave
@onready var _e07_text: Label = %E07VaneText
@onready var _e08_respin: Button = %E08Respin
@onready var _e08_skills: HBoxContainer = %E08Skills
@onready var _e08_charge: Button = %E08ChargeIntervene
@onready var _e08_confirm: Button = %E08Confirm
@onready var _e10_log: VBoxContainer = %E10LogFeed
@onready var _e11_chassis_bar: ProgressBar = %E11ChassisBar
@onready var _e11_chassis_value: Label = %E11ChassisValue
@onready var _e12_charge: Label = %E12Charge
@onready var _duel_overlay: Control = %DuelOverlay
@onready var _pause_overlay: Control = %PauseOverlay

var _paused := false

# 통상 턴의 릴 표시 배열 — 듀얼 중에는 오버레이의 릴로 스왑된다 (아래 _enter_duel 참조)
var _base_reel_icons: Array[TextureRect] = []


# 세션 주입 없이 단독 인스턴스화되는 경로(검사 하네스)를 위해 자체 세션을 연다.
# 폴백이 아니라 **동등한 개시 경로**다 — 라우터가 하는 일을 그대로 한다.
func _on_bound(_payload: Dictionary) -> void:
	_boot()


func _ready() -> void:
	if session == null:
		_boot()


func _boot() -> void:
	if engine != null:
		return
	if session == null:
		var standalone := GameData.new()
		standalone.load_all()
		session = RunSession.new()
		session.setup(standalone)
		session.begin_career(1)
	data = session.data
	_timer_base = data.param("param_timer_base_sec")
	_lockout_base = data.param("param_confirm_lockout_sec")
	_collect_reels()
	_e04_timer_ring.configure(
		data.param("param_timer_leeway_ratio"), data.param("param_timer_warning_ratio")
	)
	# 성장 단계 진폭 계수 — D13 별첨A §8.2. 1단계 고정(성장 상태는 아웃게임 층 소관).
	_e07_wave.configure(data.param("param_vane_amp_stage1"))
	_e10_log.configure(int(data.param("param_log_slot_cap")), int(data.param("param_font_size_body")))
	_duel_overlay.boost_pressed_signal().connect(_on_boost)
	_pause_overlay.setup(session)
	_pause_overlay.resumed.connect(func(): _paused = false)
	_pause_overlay.quit_to_title.connect(func(): go("SYS-01", {}))
	(%E14Menu as Button).pressed.connect(_open_pause)
	_apply_static_strings()
	_start_gp()


func _open_pause() -> void:
	if _paused:
		return
	_paused = true
	# 개입 창 중이면 가림막 — 정지 중 보드 숙고 차단 (D09 §3.7 · F2 보호)
	_pause_overlay.open(_timer_active)


# 씬에는 표시 문자열을 굳히지 않는다 — 전량 런타임 키 참조 (D09 §6.6 · D12 §8.1).
func _apply_static_strings() -> void:
	var s := data.strings
	(%FrontLabel as Label).text = s.text("ui.race.gaugeFront")
	(%RearLabel as Label).text = s.text("ui.race.gaugeRear")
	(%ChassisLabel as Label).text = s.text("ui.race.chassisLabel")
	(%ChargeLabel as Label).text = s.text("ui.race.chargeLabel")
	_e08_respin.text = s.text("ui.race.respin")
	_e08_charge.text = s.text("ui.race.chargeIntervene")
	(%E14Menu as Button).text = s.text("ui.race.menu")
	for box in _hold_boxes:
		box.text = s.text("ui.race.hold")
	for i in range(_skill_buttons.size()):
		# 덱 결선 전이라 전 슬롯이 잠금 표기다 (D09 §3.2 미확장 슬롯 규격 준용).
		var slot_label := s.text("ui.race.skillSlotFormat", {"index": i + 1})
		_skill_buttons[i].text = s.text("ui.race.locked")
		_skill_buttons[i].tooltip_text = slot_label
	# 비용 ◆n 상시 병기 (D09 §3.2). 어순도 문면이므로 서식은 스트링 키가 갖는다(IMPL-027 전례).
	var respin_label := _with_cost("ui.race.respin", "param_charge_hold_cost")
	var negate_label := _with_cost("ui.race.chargeIntervene", "param_charge_negate_cost")
	_e08_respin.text = respin_label
	_e08_charge.text = negate_label
	var empty_slot := s.text("ui.race.consumableEmpty")
	for slot in (%E13Consumables as Node).get_children():
		(slot.get_node("Label") as Label).text = empty_slot


func _with_cost(label_key: String, cost_param: String) -> String:
	var s := data.strings
	var cost := s.text("ui.race.costFormat", {"cost": int(data.param(cost_param))})
	return s.text("ui.race.actionWithCost", {"label": s.text(label_key), "cost": cost})


func _process(delta: float) -> void:
	if _paused:
		return  # 타이머 정지 (D09 §3.7) — 잔량·링·확정 잠금 전부 동결
	_process_shake(delta)
	if _confirm_lockout > 0.0:
		_confirm_lockout = maxf(0.0, _confirm_lockout - delta)
		_refresh_action_enabled()
	if not _timer_active or _timer_disabled:
		return  # 비활성 = 잔량이 흐르지 않는다 — 타임아웃도 자연 부재 (D09 §6.2)
	_timer_remaining = maxf(0.0, _timer_remaining - delta)
	_e04_timer_ring.set_ratio(_timer_remaining / _timer_effective_base)
	_update_timer_value()
	if _timer_remaining <= 0.0:
		_timer_active = false
		_e04_timer_ring.set_active(false)
		var timeout_events := engine.timeout()
		_push_events(timeout_events)
		_run_presentation(timeout_events)  # 타임아웃 자동 확정도 확정이다 — 채널 동일
		_next_turn()


# 입력 매핑은 D09 §1.3 — 확정과 스핀이 같은 키인 것이 원칙이다
# ("결과를 불러온다 → 결과를 받아들인다"가 같은 물리 동작으로 순환).
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		_open_pause()
		get_viewport().set_input_as_handled()
		return
	if _paused:
		return  # 정지 중 레이스 입력 차단 — 오버레이가 자체 포커스를 갖는다
	if key.keycode == KEY_SPACE or key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_on_primary_action()
		get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_R:
		_on_respin()
		get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_C:
		_on_charge_intervene()
		get_viewport().set_input_as_handled()
		return
	var hold_index := HOLD_KEYS.find(key.keycode)
	if hold_index >= 0:
		_toggle_hold(hold_index)
		get_viewport().set_input_as_handled()


# ── 노드 수집 ──
func _collect_reels() -> void:
	for i in range(REEL_COUNT):
		var column := _e05_reels.get_child(i)
		_reel_panels.append(column.get_node("Frame"))
		_base_reel_icons.append(column.get_node("Frame/Symbol"))
		var box: CheckBox = column.get_node("Hold")
		box.toggled.connect(_on_hold_toggled)
		_hold_boxes.append(box)
	_reel_icons = _base_reel_icons
	for child in _e08_skills.get_children():
		_skill_buttons.append(child)


# ── GP 수명 주기 ──
# 서킷 선택·슬롯 보정 주입은 시즌 층이 한다 (D08 §2.4 — 화면은 규칙을 갖지 않는다).
func _start_gp() -> void:
	if not session.begin_gp():
		push_error("RaceScreen: season layer produced no circuit for this slot")
		return
	rng = session.rng
	engine = session.engine
	_e10_log.clear_feed()
	_push_events(engine.start_gp())
	_next_turn()


func _next_turn() -> void:
	_timer_active = false
	_revealing = false
	_e04_timer_ring.set_active(false)
	var info := engine.begin_turn()
	if String(info.get("type", "")) == "finished":
		_on_gp_finished()
		return
	# 듀얼 삽입·복귀 (D05 §3 DUEL) — 오버레이 표시는 화면 전환이 아니다 (D09 §3.5).
	# 릴 은닉은 **배열 스왑이 끝난 뒤**여야 한다 — 스왑 전에 지우면 복귀 쪽 릴에
	# 직전 턴 심볼이 남는다 (SEAL-E가 실제로 잡았다: T1 대기 중 비공개 실패 15건).
	if String(info.get("type", "")) == "duel":
		_enter_duel(info)
	else:
		_exit_duel()
	_hide_reels()
	_push_events(info.get("events", []))
	_refresh_strip()
	_refresh_resources()
	_refresh_action_enabled()
	_update_timer_value()


# 릴 표시 배열을 오버레이로 스왑한다 — 공개·은닉·봉인 검사(SEAL-E)가 전부 같은 경로로
# 오버레이 릴을 보게 하는 장치다. 이중 구현이 없으므로 봉인 규칙이 갈라지지 않는다.
func _enter_duel(info: Dictionary) -> void:
	var opponent_id := String(info.get("opponent", ""))
	var opponent: Dictionary = engine.entrants.get(opponent_id, {})
	if opponent.is_empty():
		push_error("RaceScreen: duel opponent missing - %s" % opponent_id)
		return
	_duel_overlay.show_duel(data.strings, opponent, int(info.get("duel_type", 0)))
	_reel_icons = _duel_overlay.reel_icons()
	_hide_reels()
	_refresh_boost()


func _exit_duel() -> void:
	if not _duel_overlay.visible:
		return
	_duel_overlay.dismiss()
	_reel_icons = _base_reel_icons


func _refresh_boost() -> void:
	var cap := int(data.param("param_charge_boost_max"))
	var can_add := _timer_active and not _revealing and engine.charge >= 1 and engine.duel_boost < cap
	_duel_overlay.set_boost(engine.duel_boost, cap, can_add)


func _on_boost() -> void:
	if not _timer_active or _revealing or not engine.current_turn_is_duel:
		return
	engine.add_duel_boost()
	_refresh_boost()
	_refresh_resources()


func _on_gp_finished() -> void:
	_push_events([{
		"phase": "T5", "key": "raceLog.gpFinish01",
		"params": {"rank": engine.result.get("player_rank", 0)},
	}])
	_refresh_strip()
	_refresh_resources()
	_refresh_action_enabled()
	# 결산 화면이 저장 지점이다 (D09 §2.4 RESULT) — 전이는 라우터가 수행한다.
	# 단독 실행(검사 하네스)에서는 라우터가 없으므로 요청만 남는다.
	session.close_gp()
	go("RACE-03", {})


# ── 개입 창 (T2~T4) ──
func _on_primary_action() -> void:
	if _revealing or engine == null or engine.finished:
		return
	if _timer_active:
		_on_confirm()
		return
	if engine.turn_phase == RaceTypes.TurnPhase.T1_SECTOR_OPEN:
		_on_spin()


func _on_spin() -> void:
	engine.spin()  # T2 커밋 — reel 스트림 소비. 결과는 아직 어떤 경로에도 없다
	_refresh_action_enabled()
	_reveal_reels([0, 1, 2], true)


func _on_confirm() -> void:
	if not _timer_active or _confirm_lockout > 0.0:
		return
	_timer_active = false
	_e04_timer_ring.set_active(false)
	# 비활성 시 모멘텀 = 조건 불성립 (여유 구간 자체가 없다 — D09 §6.2 채택 구조)
	var ratio := 0.0 if _timer_disabled else _timer_remaining / _timer_effective_base
	var events := engine.confirm(ratio)
	_push_events(events)
	_run_presentation(events)  # 확정 후 이벤트에서만 — 봉인 (불변규칙 5)
	# 듀얼 결과는 프레임 내 표기 후 해제한다 (D09 §3.5). [가안] 표기 유지 0.6초 —
	# 연출 시간 규격이 D13에 없어 임시값이며 실기 조정 대상이다.
	if _duel_overlay.visible:
		var result_event := _duel_result_event(events)
		if not result_event.is_empty():
			# 결과 문면의 매개({amount} 등)는 이벤트 params 로 치환한다 — 로그 번역과 동일 경로
			var result_text := data.strings.text(
				String(result_event["key"]), result_event.get("params", {})
			)
			_duel_overlay.show_result(result_text)
			await get_tree().create_timer(0.6).timeout
	_next_turn()


# 듀얼 결판 로그 키 대장 — 엔진이 발행하는 결과 키 전량 (접두 비교 대신 열거:
# 새 결과 키가 생기면 여기 등재해야 프레임 표기가 붙는다 — 의도적 변경만 통과)
const DUEL_RESULT_KEYS := [
	"raceLog.duelWin01", "raceLog.duelLoseOvertake01", "raceLog.duelLoseDefense01",
]


func _duel_result_event(events: Array) -> Dictionary:
	for event in events:
		if DUEL_RESULT_KEYS.has(String(event.get("key", ""))):
			return event
	return {}


func _on_respin() -> void:
	if not _timer_active or _revealing:
		return
	var keep: Array = []
	for i in range(REEL_COUNT):
		if _hold_boxes[i].button_pressed:
			keep.append(i)
	var outcome := engine.hold_respin(keep)
	if not outcome.get("ok", false):
		return
	_push_events(outcome.get("events", []))
	var changed: Array = []
	for i in range(REEL_COUNT):
		if not keep.has(i):
			changed.append(i)
	# 재정지분도 정지 연출을 다시 재생한다 — 개입 창 내라 정보 누출은 아니지만
	# 즉시 갱신은 정지 연출 규격이 아니다(IMPL-019 이월 3번 해소).
	_reveal_reels(changed, false)
	_refresh_resources()


func _on_charge_intervene() -> void:
	if not _timer_active or _revealing:
		return
	var outcome := engine.negate_trouble()
	if outcome.get("ok", false):
		_push_events(outcome.get("events", []))
	_refresh_resources()
	_refresh_action_enabled()


func _toggle_hold(index: int) -> void:
	if not _timer_active or _revealing:
		return
	_hold_boxes[index].button_pressed = not _hold_boxes[index].button_pressed


func _on_hold_toggled(_pressed: bool) -> void:
	_refresh_reel_frames()


# 순차 정지 공개 (D09 §3.2 — 간격은 D13 릴 정지 간격).
# **연출 중 타이머 정지 [가안]:** 정본은 정지 연출 시간이 개입 창에 포함되는지 말하지 않는다.
# 흐르게 두면 리스핀을 쓸수록 모멘텀 잔여 비율(D05 §7.3)이 구조적으로 깎여 개입 선택에
# 이중 페널티가 붙는다 — D09 §3.2가 타임아웃에 대해 명문화한 "이중 처벌 아님"과 같은 방향으로 잡았다.
func _reveal_reels(indices: Array, start_window: bool) -> void:
	_revealing = true
	var was_running := _timer_active
	_timer_active = false
	_refresh_action_enabled()
	# O4 릴 정지 속도 — 표준 / 고속(배율 D13 창구) / 일괄 정지 (D09 §6.1 · D05 §5.1 예약 이행).
	# 일괄 정지도 정지 이벤트 자체는 유지한다 — 연출 압축이지 결과 선표시가 아니다 (간격 0).
	var interval := data.param("param_reel_stop_interval_sec")
	match session.options.index_of("o4"):
		1:
			interval *= data.param("param_opt_reel_fast_mult")
		2:
			interval = 0.0
	var provisional := engine.get_provisional()
	for i in indices:
		if interval > 0.0:
			await get_tree().create_timer(interval).timeout
		if engine == null:
			return
		_reel_icons[i].texture = _icon_texture(String(provisional[i]))
	_revealing = false
	# O5 개입 창 타이머 — 기본 / ×1.5 / ×2 / 비활성 (D09 §6.1·§6.2 — 배율은 D13 창구 전사값).
	# 비활성 = 타이머·구간 자체가 부재. 개입 창은 열리되(가드 재사용) 잔량이 흐르지 않고
	# 링은 소등, 모멘텀은 조건 불성립으로 자연 미발생(_on_confirm 이 ratio 0 을 넘긴다).
	_timer_disabled = session.options.index_of("o5") == 3
	var effective_base := _timer_base
	match session.options.index_of("o5"):
		1:
			effective_base *= data.param("param_opt_timer_mult_1")
		2:
			effective_base *= data.param("param_opt_timer_mult_2")
	if start_window:
		_push_events([{"phase": "T3", "key": "vane.brief.provisional01", "params": {}}])
		_timer_effective_base = effective_base
		_timer_remaining = effective_base
		_confirm_lockout = _lockout_base  # T3 진입 후 확정 오입력 방어 (D09 §1.3)
	_timer_active = true if start_window else was_running
	if _timer_active and not _timer_disabled:
		_e04_timer_ring.set_active(true)
		_e04_timer_ring.set_ratio(_timer_remaining / _timer_effective_base)
	if engine.current_turn_is_duel:
		_refresh_boost()
	_refresh_strip()
	_refresh_action_enabled()
	_update_timer_value()


# 도상 경로 규약: 셀 파일명 = 테이블 id (심볼 `symbol_*` · 속성 `attr_*`).
# D10 §8.1 에셋 대장의 요소 매핑 열이 아직 없어 파일명 규약으로 잇는다 —
# [가안]이며 대장 도입 시 교체한다. 없는 도상은 침묵하지 않고 보고한다(IMPL-019 계열).
func _icon_texture(asset_id: String) -> Texture2D:
	if asset_id.is_empty():
		return null
	if _icon_cache.has(asset_id):
		return _icon_cache[asset_id]
	var path := "%s%s.png" % [ICON_DIR, asset_id]
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if texture == null:
		# 진단 문자열은 영문 — 표시 문자열이 아니지만 V4는 한글 리터럴을 경로 불문 차단한다
		# (코어의 push_error 관행과 동일하게 맞춘다)
		push_error("RaceScreen: icon asset missing - %s" % path)
	_icon_cache[asset_id] = texture
	return texture


# ── 표시 갱신 ──
# 비공개 상태 = 도상 부재. 회전 중 심볼을 흘리는 연출은 두지 않는다 —
# 표시되는 것이 결과와 상관되면 그 자체가 봉인 누출 경로이고, 상관 없는 심볼을 흘리려면
# 난수가 필요한데 RNG 6스트림은 게임 로직 전속이다(D12 §6). 연출 결선은 아트 유입 시.
func _hide_reels() -> void:
	for icon in _reel_icons:
		icon.texture = null
	for box in _hold_boxes:
		box.button_pressed = false
	_refresh_reel_frames()


# 홀드 상태 = 프레임 잠금 표시 + 토글 점등의 이중 표시 (D09 §3.2)
func _refresh_reel_frames() -> void:
	for i in range(REEL_COUNT):
		var held: bool = _hold_boxes[i].button_pressed
		_reel_panels[i].modulate = Color(1.0, 1.0, 1.0) if held else Color(0.75, 0.78, 0.82)


func _refresh_strip() -> void:
	var s := data.strings
	_e01_position.text = s.text("ui.race.positionFormat", {
		"rank": engine.player_position(), "total": engine.positions.size(),
	})
	_e02_lap_sector.text = s.text("ui.race.lapSectorFormat", {
		"lap": engine.lap, "laps": data.circuit_int("laps"),
		"sector": engine.sector, "sectors": data.circuit_int("sectors_per_lap"),
	})
	# GP_START~첫 begin_turn 사이에는 섹터가 아직 0이다 — 조회하면 침묵 기본값 가드가
	# 정당하게 push_error를 낸다(IMPL-019). 진입 전에는 코너명을 비운다.
	if engine.sector > 0:
		var sector_entry := data.sector_entry(engine.sector)
		var corner_key := String(sector_entry.get("name_key", ""))
		_e02_corner.text = s.text(corner_key)
		_e02_attr.texture = _icon_texture(String(sector_entry.get("main_attr", "")))
	else:
		_e02_corner.text = ""
		_e02_attr.texture = null
	# 레조넌스는 **진입 시점에만** 공표한다 — 위치 사전 표시·예고는 어떤 채널로도 하지 않는다
	# (D08 §3.7 R6 · D09 §3.6). 엔진의 announced 플래그를 그대로 따른다.
	_e02_resonance.visible = engine.resonance_announced
	_e02_resonance.text = s.text("ui.race.resonanceBanner")
	_e03_front.value = engine.front_gauge
	_e03_rear.value = engine.rear_gauge
	# 베인 콜아웃(E07)은 여기서 건드리지 않는다 — 발화는 `vane.*` 이벤트가 소유하며,
	# 상태 갱신이 콜아웃을 덮으면 발화가 화면에 남지 못한다(첫 구현에서 실제로 지워졌다).


func _refresh_resources() -> void:
	var s := data.strings
	var chassis_max := data.param("param_chassis_max")
	_e11_chassis_bar.max_value = chassis_max
	_e11_chassis_bar.value = engine.chassis
	var chassis_text := s.text("ui.race.chassisFormat", {"value": int(engine.chassis)})
	_e11_chassis_value.text = chassis_text
	var fill: StyleBoxFlat = _e11_chassis_bar.get_theme_stylebox("fill").duplicate()
	fill.bg_color = UiPalette.CHASSIS_WARN if engine.chassis <= chassis_max * 0.25 else UiPalette.CHASSIS_OK
	_e11_chassis_bar.add_theme_stylebox_override("fill", fill)
	_e12_charge.text = s.text("ui.race.chargeFormat", {
		"value": engine.charge, "cap": int(data.param("param_charge_cap")),
	})


func _refresh_action_enabled() -> void:
	var open := _timer_active and not _revealing
	_e08_respin.disabled = not open or engine == null or engine.hold_used
	_e08_charge.disabled = not open
	for box in _hold_boxes:
		box.disabled = not open
	var can_spin := (
		engine != null and not engine.finished and not _revealing and not _timer_active
		and engine.turn_phase == RaceTypes.TurnPhase.T1_SECTOR_OPEN
	)
	_e08_confirm.disabled = not (can_spin or (open and _confirm_lockout <= 0.0))
	_e08_confirm.text = data.strings.text("ui.race.confirm" if _timer_active else "ui.race.spin")


func _update_timer_value() -> void:
	# 수치는 기본 비표시 — 압박의 아날로그화(D04 §8.2). O6 옵션으로만 켠다 (즉시 반영).
	# 소수 자리도 문면이므로 서식은 스트링 키가 갖는다 (IMPL-027 전례).
	_e04_timer_value.visible = session.options.index_of("o6") == 1 and not _timer_disabled
	var seconds := snappedf(_timer_remaining, 0.1)
	var timer_text := data.strings.text("ui.race.timerFormat", {"value": seconds})
	_e04_timer_value.text = timer_text


# ── 연출 등급 채널 실행 (§3.4 몫 — D09 §3.6 · D12 §5.8) ──
# 등급 판정·상한·우선순위는 코어(PresentationGrade)가 갖고, 여기서는 **확정된 등급의
# 표현 채널만** 실행한다. 접근성 옵션(O1~O3)은 출력 단계 마스킹이며 판정에 관여하지 않는다.
#
# 트리거 후보는 확정 후(T5) 이벤트에서만 뽑는다 — 릴 정지 연출 전에 발화하면
# 그 자체가 결과 상관 신호다 (봉인 — 불변규칙 5).
const TRIGGER_BY_KEY := {
	"raceLog.duelWin01": "trigger_duel_decision",
	"raceLog.duelLoseOvertake01": "trigger_duel_decision",
	"raceLog.duelLoseDefense01": "trigger_duel_decision",
	"raceLog.chanceDuel01": "trigger_chance_three_match",
}

var _shake_left := 0.0
var _shake_strength := 0.0


func _collect_triggers(events: Array) -> Array:
	var triggers: Array = []
	for event in events:
		var key := String(event.get("key", ""))
		if TRIGGER_BY_KEY.has(key):
			var trigger := String(TRIGGER_BY_KEY[key])
			if not triggers.has(trigger):
				triggers.append(trigger)
			# 벽 라이벌 격파 = 듀얼 승리 + 상대가 무대 벽 라이벌 (D08 §8.5 — 무대 1은 부재라
			# 자연 미발동. 매핑만 결선해 두면 무대 2+ 데이터 유입 시 그대로 붙는다)
			if key == "raceLog.duelWin01":
				var wall := String(data.stage_of_active_circuit().get("wall_rival", ""))
				if not wall.is_empty() and engine.duel_opponent == wall:
					triggers.append("trigger_wall_rival_beat")
	return triggers


func _run_presentation(events: Array) -> void:
	var triggers := _collect_triggers(events)
	if triggers.is_empty():
		return
	# 한 턴의 후보를 배치로 넘긴다 — 개별 호출은 우선순위 역전을 만든다 (IMPL-034)
	for resolved in session.presentation.resolve(triggers):
		var channels: Dictionary = session.presentation.channels(String(resolved["grade"]))
		_fire_channels(channels)


func _fire_channels(channels: Dictionary) -> void:
	if channels.is_empty():
		return
	var code := String(channels.get("code", "L0"))
	# 로그 채널은 이벤트 자체가 이미 발화했다 (전 등급 공통).
	# SFX 스팅·햅틱: 음원·지속 시간 실물 부재 — sting_length_sec 소비 지점만 확보(IMPL-035).
	if code == "L1":
		_pulse_gauge()
		_start_shake(data.param("param_fx_shake_weak_px"))
	elif code == "L2" or code == "L3":
		_start_shake(data.param("param_fx_shake_strong_px"))
		if bool(channels.get("flash_slow", false)):
			_fire_flash()
	# L3 전용 일러스트 컷인: 도트 CG 미유입 + 발동 조건(찬스 3매치 + 히든)이 무대 1 골격
	# 밖이라 소비부를 두지 않는다 — CG 유입 시 결선. 정보 채널(로그)은 이미 보존된다.


# 게이지 섬광 (L1 — D09 §3.6). 플래시(O2)와 별개 채널이라 감쇠 대상이 아니다 —
# 게이지 자체가 정보 표시이므로 정보 보존 축에 속한다.
func _pulse_gauge() -> void:
	var duration := data.param("param_fx_gauge_pulse_sec")
	var tween := create_tween()
	tween.tween_property(_e03_front, "modulate", Color(1.6, 1.6, 1.6), duration * 0.3)
	tween.tween_property(_e03_front, "modulate", Color.WHITE, duration * 0.7)


# 셰이크 — O1 감쇠 (표준 1.0 / 감소 0.5 / 끔 0 — 출력 마스킹, D09 §6.3)
func _start_shake(base_px: float) -> void:
	var mask := _fx_mask("o1")
	if mask <= 0.0:
		return
	_shake_strength = base_px * mask
	_shake_left = data.param("param_fx_shake_sec")


# 플래시 — O2 감쇠 (광과민 대응). 끔이어도 로그·게이지의 정보 채널은 남는다 (정보 보존 의무)
func _fire_flash() -> void:
	var mask := _fx_mask("o2")
	if mask <= 0.0:
		return
	var flash := %FxFlash as ColorRect
	flash.color.a = data.param("param_fx_flash_alpha") * mask
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.0, data.param("param_fx_flash_sec"))


func _fx_mask(option_id: String) -> float:
	match session.options.index_of(option_id):
		1:
			return data.param("param_fx_reduced_mult")
		2:
			return 0.0
	return 1.0


func _process_shake(delta: float) -> void:
	var root_box := get_node("Root") as Control
	if _shake_left <= 0.0:
		if root_box.position != Vector2.ZERO:
			root_box.position = Vector2.ZERO
		return
	_shake_left -= delta
	# 결정적 흔들림 — 난수를 쓰지 않는다 (RNG 스트림은 게임 로직 전속 — D12 §6)
	var phase := _shake_left * 60.0
	root_box.position = Vector2(sin(phase * 1.7), cos(phase * 2.3)) * _shake_strength


# ── 이벤트 → 표시 경로 분기 (D09 §3.1 국면 분리) ──
func _push_events(events: Array) -> void:
	for event in events:
		var key := String(event.get("key", ""))
		var params: Dictionary = event.get("params", {}).duplicate()
		for param_name in params:
			var value: Variant = params[param_name]
			if typeof(value) == TYPE_STRING and data.strings.has_key(String(value)):
				# 참조 키의 문면에 매개(필러의 {number} 등)가 있으면 같은 params 로 치환한다
				params[param_name] = data.strings.text(String(value), params)
		var body := data.strings.text(key, params)
		if key.begins_with("vane."):
			_e07_text.text = body  # 릴 존 콜아웃 전속 — 로그 피드로 흘리지 않는다
		else:
			# 화자 축이 이벤트에 아직 없다 — 발행 층(코어)이 화자를 구분하지 않으므로
			# 전량 중계로 표기한다. [가안] 화자 구분(D09 §3.3 4종)은 이벤트 스키마에
			# 화자 필드가 생긴 뒤 결선한다. — IMPL-071
			_e10_log.push_line(data.strings.text("ui.race.speakerRelay"), body)
	_refresh_strip()
	_refresh_resources()
