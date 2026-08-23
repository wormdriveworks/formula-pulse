# SEAL-E — UI 조기 공개 검사 (봉인 규칙의 화면 층 · 불변규칙 5 · D12 §6.3 · D14 TC-C11/G-6).
#
# 기존 봉인 검사(TC-C11)는 **엔진의 공개 표면**을 본다. 엔진이 결과를 숨겨도 화면이 먼저
# 그려 버리면 봉인은 깨지는데, 그 경로를 잡는 검사가 없었다(MS-2 인계 §0.4-5 이월분).
# 여기서는 실화면을 실제로 인스턴스화해 **릴 정지 연출이 끝나기 전 UI 표면**을 관찰한다.
#
# 검사 축 3종:
#   ①스핀 커밋 직후 — 3릴 전부 자리표시 (엔진은 결과를 갖고 있다)
#   ②순차 공개 중 — 공개된 릴 외에는 자리표시이며, 공개 수는 되돌아가지 않는다
#   ③스핀이 바꾼 UI 표면 — 릴 외의 어떤 라벨에도 결과·결과 상관 문자열이 실리지 않는다
#      (IMPL-047의 "심볼 id 포함"이 아니라 "표면 변경 자체"로 판정하는 기준을 화면 층에 승계)
#
# 다수 스핀에 걸쳐 본다 — 결과 상관 누출은 희귀 분기(3매치 등)에 숨을 수 있다(IMPL-055 실측).
extends SceneTree

const SCENE_PATH := "res://ui/race/race_screen.tscn"
const SPIN_ROUNDS := 24
const TIME_SCALE := 5.0
# 하네스 탈출 예산 (IMPL-146 — 총괄 인계 ⑤). 이 스위트는 CI 게이트 안에서 돌기 때문에
# 여기서 상주하면 게이트 자체가 멈춘다(LFS 미설치 머신의 에셋 포인터 체크아웃 등 —
# IMPL-091 실측). `Engine.time_scale` 무관한 **실시간**으로 잰다 — delta는 스케일된다.
const WATCHDOG_MSEC := 180000

var _screen: Control
var _data: GameData
var _checks := 0
var _failures := 0
var _round := 0
var _revealed_high_water := 0
var _monotonic_violations := 0
var _partial_leaks := 0
var _pre_spin_surface: Dictionary = {}
var _phase := "idle"
var _settle := 0.0
var _done := false
var _started_msec := 0


func _initialize() -> void:
	SaveManager.use_test_root()   # 저장 격리 — 실 프로필 무접촉 (25차)
	_started_msec = Time.get_ticks_msec()
	Engine.time_scale = TIME_SCALE
	_data = GameData.new()
	_data.load_all()
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("씬 로드 실패: %s" % SCENE_PATH)
		_finish()
		return
	_screen = packed.instantiate()
	root.add_child(_screen)


func _process(delta: float) -> bool:
	if _done:
		return true
	if Time.get_ticks_msec() - _started_msec > WATCHDOG_MSEC:
		_fail("하네스 예산 초과 %dms — 무한 상주 차단 (round=%d phase=%s)"
			% [WATCHDOG_MSEC, _round, _phase])
		_report()
		return true
	# **`_screen == null`은 정상 상태가 아니다** — 인스턴스화가 중단됐다는 뜻이므로 종료한다.
	if _screen == null:
		_fail("화면 인스턴스 부재 — 초기화 중단")
		_report()
		return true
	match _phase:
		"idle":
			# 확정 후 전이 연출(듀얼 결과 프레임 내 표기 — D09 §3.5) 중에는 아직 이전 턴이다.
			# 엔진이 T1 에 도달할 때까지 기다린다 — 연출 중 상태를 T1 로 오인하면
			# 직전 결과가 "대기 중 노출"로 오검출된다 (실측 7건).
			if _screen._revealing or _screen.engine.turn_phase != RaceTypes.TurnPhase.T1_SECTOR_OPEN:
				return false
			# T1 대기 — 이 시점에도 릴은 비어 있어야 한다
			_assert(_hidden_count() == 3, "T1 대기 중 릴 전량 비공개")
			_pre_spin_surface = _surface_snapshot()
			_screen._on_primary_action()
			# 스핀은 T2 커밋이다: 엔진은 결과를 확정했고 UI는 아직 아무것도 몰라야 한다.
			_assert(_screen.engine.get_provisional().size() == 3, "엔진이 잠정 결과를 보유")
			_assert(_hidden_count() == 3, "스핀 커밋 직후 릴 전량 비공개 (라운드 %d)" % _round)
			_assert_surface_unchanged("스핀 커밋 직후")
			_revealed_high_water = 0
			_monotonic_violations = 0
			_partial_leaks = 0
			_phase = "revealing"
		"revealing":
			# 프레임마다 관찰하되 **집계는 라운드당 1회**로 고정한다 — 프레임 수에 따라
			# 검사 수가 흔들리면 검사 수 하한 게이트(IMPL-054)가 성립하지 않는다.
			var shown := 3 - _hidden_count()
			if shown < _revealed_high_water:
				_monotonic_violations += 1
			_revealed_high_water = shown
			if _non_placeholder_count() != shown:
				_partial_leaks += 1
			if shown >= 3:
				_assert(_monotonic_violations == 0, "공개 수 단조 증가 (라운드 %d)" % _round)
				_assert(_partial_leaks == 0, "부분 공개 구간의 미공개 릴 = 자리표시 전량 (라운드 %d)" % _round)
				_phase = "open"
				_settle = 0.0
		"open":
			# 개입 창 진입 확인 후 확정 → 다음 라운드
			_settle += delta
			if _settle < 0.1:
				return false
			_assert(_screen._timer_active, "전 릴 정지 후 개입 창 개시 (라운드 %d)" % _round)
			_screen._confirm_lockout = 0.0
			_screen._on_primary_action()
			_round += 1
			if _round >= SPIN_ROUNDS or _screen.engine.finished:
				_report()
				return true
			_phase = "idle"
	return false


# ── 관찰 ──
# 심볼은 도상이다 — 비공개 = 텍스처 부재. 텍스트가 아니라 **실제 표시물**을 판정한다.
func _hidden_count() -> int:
	var hidden := 0
	for icon in _screen._reel_icons:
		if icon.texture == null:
			hidden += 1
	return hidden


func _non_placeholder_count() -> int:
	return _screen._reel_icons.size() - _hidden_count()


# 화면의 전 라벨 텍스트를 뜬다 — 개별 필드를 열거하지 않으므로 새 표시 요소가
# 자동으로 검사 대상이 된다(IMPL-039의 전수 스캔 방식을 화면 층에 승계).
func _surface_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	_collect_text(_screen, snapshot)
	return snapshot


func _collect_text(node: Node, out: Dictionary) -> void:
	if node is Label:
		out[node.get_path()] = (node as Label).text
	elif node is Button:
		out[node.get_path()] = (node as Button).text
	for child in node.get_children():
		_collect_text(child, out)


func _assert_surface_unchanged(context: String) -> void:
	var now := _surface_snapshot()
	var changed: Array[String] = []
	for path in now:
		if not _pre_spin_surface.has(path) or _pre_spin_surface[path] != now[path]:
			changed.append(String(path))
	_assert(changed.is_empty(), "%s — 릴 외 UI 표면 무변경 (변경: %s)" % [context, ", ".join(changed)])


# ── 판정 ──
func _assert(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  [FAIL] %s" % label)


func _fail(label: String) -> void:
	_checks += 1
	_failures += 1
	print("  [FAIL] %s" % label)


func _report() -> void:
	if _failures == 0:
		print("SEAL_UI_TEST_PASS checks=%d rounds=%d" % [_checks, _round])
		_finish(0)
	else:
		print("SEAL_UI_TEST_FAIL checks=%d failures=%d" % [_checks, _failures])
		_finish(1)


func _finish(code: int = 1) -> void:
	_done = true
	Engine.time_scale = 1.0
	quit(code)
