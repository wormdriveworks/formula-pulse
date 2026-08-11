# MS-1 디버그 실행 UI — 1 GP를 사람이 처음부터 끝까지 돌리는 화면 1장.
# D09 레이스 4존 골격의 자리 배치만 차용 (A: 상태 / B: 릴·개입 / C: 로그 / D: 순위).
# 아트·사운드·VN·애니메이션 없음. 전 표시 문자열 = 스트링 키 (불변규칙 6).
#
# 봉인 규칙 (불변규칙 5): 스핀 결과는 릴 정지 연출(순차 공개 0.4s)이 끝나기 전
# 어떤 표시 경로에도 노출하지 않는다 — 공개 전 릴 표기는 자리 표시 문자.
extends Control

const SNAPSHOT_PATH := "user://debug_suspend.json"
const REEL_PLACEHOLDER := "???"

var data: GameData
var rng: RngService
var engine: RaceEngine

var _timer_active := false
var _timer_remaining := 0.0
var _timer_base := 10.0
var _revealing := false
var _hold_toggles: Array[CheckBox] = []

var _status_label: Label
var _reel_labels: Array[Label] = []
var _timer_label: Label
var _log_label: RichTextLabel
var _standings_label: Label
var _spin_button: Button
var _confirm_button: Button
var _hold_button: Button
var _negate_button: Button
var _boost_button: Button
var _new_button: Button
var _save_button: Button
var _load_button: Button


func _ready() -> void:
	data = GameData.new()
	data.load_all()
	_timer_base = data.param("param_timer_base_sec")
	_build_layout()
	_start_new_gp()


func _process(delta: float) -> void:
	if not _timer_active:
		return
	_timer_remaining = maxf(0.0, _timer_remaining - delta)
	_update_timer_label()
	if _timer_remaining <= 0.0:
		_timer_active = false
		_append_events(engine.timeout())
		_next_turn()


# ── 레이아웃 (코드 구성 — 원격 씬 최소화) ──
func _build_layout() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title_label := Label.new()
	title_label.text = data.strings.text("ui.debug.title")
	root.add_child(title_label)

	# A존: 상태 라인
	_status_label = Label.new()
	root.add_child(_status_label)

	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 16)
	root.add_child(middle)

	# B존: 릴 + 개입
	var reel_zone := VBoxContainer.new()
	reel_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(reel_zone)

	var reel_row := HBoxContainer.new()
	reel_row.add_theme_constant_override("separation", 12)
	reel_zone.add_child(reel_row)
	for i in range(3):
		var column := VBoxContainer.new()
		reel_row.add_child(column)
		var reel_label := Label.new()
		reel_label.text = REEL_PLACEHOLDER
		reel_label.add_theme_font_size_override("font_size", 28)
		column.add_child(reel_label)
		_reel_labels.append(reel_label)
		var hold_toggle := CheckBox.new()
		hold_toggle.text = data.strings.text("ui.debug.holdRespin")
		column.add_child(hold_toggle)
		_hold_toggles.append(hold_toggle)

	_timer_label = Label.new()
	reel_zone.add_child(_timer_label)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	reel_zone.add_child(button_row)
	_spin_button = _make_button(button_row, "ui.debug.spin", _on_spin)
	_confirm_button = _make_button(button_row, "ui.debug.confirm", _on_confirm)
	_hold_button = _make_button(button_row, "ui.debug.holdRespin", _on_hold_respin)
	_negate_button = _make_button(button_row, "ui.debug.negateTrouble", _on_negate)
	_boost_button = _make_button(button_row, "ui.debug.boostPlus", _on_boost)

	var system_row := HBoxContainer.new()
	system_row.add_theme_constant_override("separation", 8)
	reel_zone.add_child(system_row)
	_new_button = _make_button(system_row, "ui.debug.newRace", _start_new_gp)
	_save_button = _make_button(system_row, "ui.debug.saveSnapshot", _on_save)
	_load_button = _make_button(system_row, "ui.debug.loadSnapshot", _on_load)

	# C존: 중계 로그
	_log_label = RichTextLabel.new()
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.scroll_following = true
	_log_label.custom_minimum_size = Vector2(0, 180)
	reel_zone.add_child(_log_label)

	# D존: 순위표
	var standings_zone := VBoxContainer.new()
	standings_zone.custom_minimum_size = Vector2(280, 0)
	middle.add_child(standings_zone)
	var standings_title := Label.new()
	standings_title.text = data.strings.text("ui.debug.standings")
	standings_zone.add_child(standings_title)
	_standings_label = Label.new()
	standings_zone.add_child(_standings_label)


func _make_button(parent: Node, key: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = data.strings.text(key)
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


# ── GP 수명 주기 ──
func _start_new_gp() -> void:
	rng = RngService.new()
	var seeder := RandomNumberGenerator.new()
	seeder.randomize()  # 프로필 생성 시 마스터 시드 (D12 §6.1) — 디버그 프로필
	rng.setup(seeder.randi())
	engine = RaceEngine.new()
	engine.setup(data, rng)
	_log_label.clear()
	_append_events(engine.start_gp())
	_next_turn()


func _next_turn() -> void:
	_timer_active = false
	_revealing = false
	_set_reels_hidden()
	var info := engine.begin_turn()
	if String(info.get("type", "")) == "finished":
		_on_gp_finished()
		return
	_append_events(info.get("events", []))
	_refresh_status(String(info.get("type", "")) == "duel")
	_set_intervention_enabled(false)
	_spin_button.disabled = false
	_update_timer_label()


func _on_gp_finished() -> void:
	_append_events([{
		"phase": "T5", "key": "raceLog.gpFinish01",
		"params": {"rank": engine.result.get("player_rank", 0)},
	}])
	_refresh_status(false)
	_refresh_standings(true)
	_spin_button.disabled = true
	_set_intervention_enabled(false)


func _on_spin() -> void:
	if engine.finished or _revealing:
		return
	_spin_button.disabled = true
	engine.spin()  # T2 커밋 — reel 스트림 소비. 결과는 아직 비노출
	_reveal_sequentially()


# 릴 순차 정지 공개 — 간격 = D13 릴 정지 간격 (봉인: 공개 전 표시 없음)
func _reveal_sequentially() -> void:
	_revealing = true
	var interval := data.param("param_reel_stop_interval_sec")
	var provisional := engine.get_provisional()
	for i in range(3):
		await get_tree().create_timer(interval).timeout
		_reel_labels[i].text = data.strings.text(String(data.symbols[_symbol_index(provisional[i])]["name_key"]))
	_revealing = false
	_append_events([{"phase": "T3", "key": "vane.brief.provisional01", "params": {}}])
	_set_intervention_enabled(true)
	_timer_remaining = _timer_base
	_timer_active = true  # T4 소프트 타임 리미트 (개입 창 한정 — D05 §7.1)
	_refresh_status(engine.current_turn_is_duel)


func _symbol_index(symbol_id: String) -> int:
	for i in range(data.symbols.size()):
		if String(data.symbols[i]["id"]) == symbol_id:
			return i
	return 0


func _on_confirm() -> void:
	if not _timer_active:
		return
	_timer_active = false
	var ratio := _timer_remaining / _timer_base
	_append_events(engine.confirm(ratio))
	_next_turn()


func _on_hold_respin() -> void:
	if not _timer_active:
		return
	var keep: Array = []
	for i in range(3):
		if _hold_toggles[i].button_pressed:
			keep.append(i)
	var outcome := engine.hold_respin(keep)
	if outcome.get("ok", false):
		_append_events(outcome.get("events", []))
		_show_provisional_now()
	_refresh_status(engine.current_turn_is_duel)


func _on_negate() -> void:
	if not _timer_active:
		return
	var outcome := engine.negate_trouble()
	if outcome.get("ok", false):
		_append_events(outcome.get("events", []))
	_refresh_status(engine.current_turn_is_duel)


func _on_boost() -> void:
	if not _timer_active:
		return
	engine.add_duel_boost()
	_refresh_status(true)


# 재정지 결과 즉시 갱신 (리스핀 후 새 잠정 결과 — 이미 개입 창 내이므로 공개 상태)
func _show_provisional_now() -> void:
	var provisional := engine.get_provisional()
	for i in range(3):
		_reel_labels[i].text = data.strings.text(String(data.symbols[_symbol_index(provisional[i])]["name_key"]))


# ── 서스펜드 스냅샷 (D12 §7.2 — 1회성) ──
func _on_save() -> void:
	SaveService.save_to(SNAPSHOT_PATH, engine.serialize())


func _on_load() -> void:
	var loaded := SaveService.load_from(SNAPSHOT_PATH)
	if not loaded["ok"]:
		return
	SaveService.delete_save(SNAPSHOT_PATH)  # 1회성 — 로드 시 소거
	rng = RngService.new()
	engine = RaceEngine.new()
	engine.setup(data, rng)
	engine.restore(loaded["payload"])
	_log_label.clear()
	_timer_active = false
	if engine.finished:
		_on_gp_finished()
		return
	_refresh_status(engine.current_turn_is_duel)
	if engine.turn_phase == RaceTypes.TurnPhase.T4_INTERVENTION:
		_show_provisional_now()
		_set_intervention_enabled(true)
		_spin_button.disabled = true
		_timer_remaining = _timer_base  # 복귀 시 타이머 리셋 (D12 §2.4 계열)
		_timer_active = true
	else:
		_set_reels_hidden()
		_set_intervention_enabled(false)
		_spin_button.disabled = false


# ── 표시 갱신 ──
func _set_reels_hidden() -> void:
	for reel_label in _reel_labels:
		reel_label.text = REEL_PLACEHOLDER
	for hold_toggle in _hold_toggles:
		hold_toggle.button_pressed = false


func _set_intervention_enabled(enabled: bool) -> void:
	_confirm_button.disabled = not enabled
	_hold_button.disabled = not enabled or engine == null or engine.hold_used
	_negate_button.disabled = not enabled
	_boost_button.disabled = not enabled or engine == null or not engine.current_turn_is_duel
	for hold_toggle in _hold_toggles:
		hold_toggle.disabled = not enabled


func _refresh_status(is_duel: bool) -> void:
	var s := data.strings
	var parts: Array[String] = []
	parts.append("%s %d/%d" % [s.text("ui.debug.lap"), engine.lap, data.circuit_int("laps")])
	parts.append("%s %d/%d" % [s.text("ui.debug.sector"), engine.sector, data.circuit_int("sectors_per_lap")])
	parts.append("%s P%d" % [s.text("ui.debug.position"), engine.player_position()])
	parts.append("%s %.0f" % [s.text("ui.debug.chassis"), engine.chassis])
	parts.append("%s %d" % [s.text("ui.debug.charge"), engine.charge])
	parts.append("%s %.0f" % [s.text("ui.debug.frontGauge"), engine.front_gauge])
	parts.append("%s %.0f" % [s.text("ui.debug.rearGauge"), engine.rear_gauge])
	if is_duel:
		parts.append(s.text("vane.brief.duel01"))
	_status_label.text = "  |  ".join(parts)
	_refresh_standings(false)
	_hold_button.disabled = not _timer_active or engine.hold_used
	_boost_button.disabled = not _timer_active or not engine.current_turn_is_duel


func _refresh_standings(final: bool) -> void:
	var order: Array = engine.result["standings"] if final and not engine.result.is_empty() else engine.positions
	var lines: Array[String] = []
	for i in range(order.size()):
		lines.append("P%-3d %s" % [i + 1, _entrant_name(String(order[i]))])
	_standings_label.text = "\n".join(lines)


func _entrant_name(entrant_id: String) -> String:
	var entrant: Dictionary = engine.entrants[entrant_id]
	if bool(entrant["is_filler"]):
		return data.strings.text(String(entrant["name_key"]), {"number": int(entrant["number"])})
	return data.strings.text(String(entrant["name_key"]))


func _update_timer_label() -> void:
	_timer_label.text = "%s %.1f" % [data.strings.text("ui.debug.timer"), _timer_remaining]


# 이벤트 → 중계 로그 (T5 규격 — 텍스트 키 발행을 문면으로 번역, 최대 2줄 스텁)
func _append_events(events: Array) -> void:
	for event in events:
		var params: Dictionary = event.get("params", {}).duplicate()
		for param_name in params:
			var value: Variant = params[param_name]
			if typeof(value) == TYPE_STRING and data.strings.has_key(String(value)):
				params[param_name] = data.strings.text(String(value))
		_log_label.append_text("[%s] %s\n" % [String(event.get("phase", "")), data.strings.text(String(event["key"]), params)])
	_refresh_standings(false)
