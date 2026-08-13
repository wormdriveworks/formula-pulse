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
extends Control

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


func _ready() -> void:
	data = GameData.new()
	data.load_all()
	SaveManager.configure(data)
	_timer_base = data.param("param_timer_base_sec")
	_lockout_base = data.param("param_confirm_lockout_sec")
	_collect_reels()
	_e04_timer_ring.configure(
		data.param("param_timer_leeway_ratio"), data.param("param_timer_warning_ratio")
	)
	# 성장 단계 진폭 계수 — D13 별첨A §8.2. 1단계 고정(성장 상태는 아웃게임 층 소관).
	_e07_wave.configure(data.param("param_vane_amp_stage1"))
	_e10_log.configure(int(data.param("param_log_slot_cap")), int(data.param("param_font_size_body")))
	_apply_static_strings()
	_start_gp()


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
	if _confirm_lockout > 0.0:
		_confirm_lockout = maxf(0.0, _confirm_lockout - delta)
		_refresh_action_enabled()
	if not _timer_active:
		return
	_timer_remaining = maxf(0.0, _timer_remaining - delta)
	_e04_timer_ring.set_ratio(_timer_remaining / _timer_base)
	_update_timer_value()
	if _timer_remaining <= 0.0:
		_timer_active = false
		_e04_timer_ring.set_active(false)
		_push_events(engine.timeout())
		_next_turn()


# 입력 매핑은 D09 §1.3 — 확정과 스핀이 같은 키인 것이 원칙이다
# ("결과를 불러온다 → 결과를 받아들인다"가 같은 물리 동작으로 순환).
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
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
		_reel_icons.append(column.get_node("Frame/Symbol"))
		var box: CheckBox = column.get_node("Hold")
		box.toggled.connect(_on_hold_toggled)
		_hold_boxes.append(box)
	for child in _e08_skills.get_children():
		_skill_buttons.append(child)


# ── GP 수명 주기 ──
func _start_gp() -> void:
	rng = RngService.new()
	var seeder := RandomNumberGenerator.new()
	seeder.randomize()  # 마스터 시드 (D12 §6.1)
	rng.setup(seeder.randi())
	engine = RaceEngine.new()
	engine.setup(data, rng)
	_e10_log.clear_feed()
	_push_events(engine.start_gp())
	_next_turn()


func _next_turn() -> void:
	_timer_active = false
	_revealing = false
	_e04_timer_ring.set_active(false)
	_hide_reels()
	var info := engine.begin_turn()
	if String(info.get("type", "")) == "finished":
		_on_gp_finished()
		return
	_push_events(info.get("events", []))
	_refresh_strip()
	_refresh_resources()
	_refresh_action_enabled()
	_update_timer_value()


func _on_gp_finished() -> void:
	_push_events([{
		"phase": "T5", "key": "raceLog.gpFinish01",
		"params": {"rank": engine.result.get("player_rank", 0)},
	}])
	_refresh_strip()
	_refresh_resources()
	_refresh_action_enabled()


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
	var ratio := _timer_remaining / _timer_base
	_push_events(engine.confirm(ratio))
	_next_turn()


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
	var interval := data.param("param_reel_stop_interval_sec")
	var provisional := engine.get_provisional()
	for i in indices:
		await get_tree().create_timer(interval).timeout
		if engine == null:
			return
		_reel_icons[i].texture = _icon_texture(String(provisional[i]))
	_revealing = false
	if start_window:
		_push_events([{"phase": "T3", "key": "vane.brief.provisional01", "params": {}}])
		_timer_remaining = _timer_base
		_confirm_lockout = _lockout_base  # T3 진입 후 확정 오입력 방어 (D09 §1.3)
	_timer_active = true if start_window else was_running
	if _timer_active:
		_e04_timer_ring.set_active(true)
		_e04_timer_ring.set_ratio(_timer_remaining / _timer_base)
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
	# 수치는 기본 비표시 — 압박의 아날로그화(D04 §8.2). O6 옵션으로만 켠다.
	# 소수 자리도 문면이므로 서식은 스트링 키가 갖는다 (IMPL-027 전례).
	var seconds := snappedf(_timer_remaining, 0.1)
	var timer_text := data.strings.text("ui.race.timerFormat", {"value": seconds})
	_e04_timer_value.text = timer_text


# ── 이벤트 → 표시 경로 분기 (D09 §3.1 국면 분리) ──
func _push_events(events: Array) -> void:
	for event in events:
		var key := String(event.get("key", ""))
		var params: Dictionary = event.get("params", {}).duplicate()
		for param_name in params:
			var value: Variant = params[param_name]
			if typeof(value) == TYPE_STRING and data.strings.has_key(String(value)):
				params[param_name] = data.strings.text(String(value))
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
