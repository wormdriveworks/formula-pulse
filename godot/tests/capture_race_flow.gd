# RACE-01 단계별 캡처 (주력 GUI 머신 전속 — 눈 검증 경로).
#
#   <console.exe> --path godot --script tests/capture_race_flow.gd -- <출력 디렉토리>
#
# 릴 국면의 각 시점을 PNG로 남긴다: T1 대기 → 스핀 직후(봉인) → 1릴 정지 → 전 릴 정지(T4 개입 창)
# → 확정 후 차기 T1. 봉인 규칙은 `test_seal_ui.gd`가 기계로 판정하고, 이 스크립트는
# **사람이 봐야 아는 것**(레이아웃·가독·타이머 링 시각 문법)을 위한 것이다.
extends SceneTree

const SCENE_PATH := "res://ui/race/race_screen.tscn"

var _screen: Control
var _out_dir := ""
var _elapsed := 0.0
var _step := 0
var _shots := 0
var _done := false
var _seeded := false

# [단계, 그 단계에 도달한 뒤 기다릴 초, 파일 접미사]
var _plan: Array = [
	[0.35, "01_t1_idle"],
	# E13 은 T1 전속이므로 스핀 전에 사용 결과를 남긴다 (재고 감소·로그 1줄·섀시 회복).
	[0.20, "01b_item_used"],
	[0.05, "02_spin_sealed"],
	[0.45, "03_reel1_stopped"],
	[0.95, "04_intervention_open"],
	# 타이머 3구간 시각 문법(D09 §3.2)을 눈으로 확인하려면 각 구간에서 한 장씩 필요하다.
	# 기본 10초 · 경계 60%/30% → 여유 ~0.6s / 경고 ~5.0s / 임박 ~8.0s 시점.
	[0.60, "05_timer_leeway"],
	[4.40, "06_timer_warning"],
	[3.00, "07_timer_imminent"],
	[0.60, "08_after_confirm"],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("CAPTURE_FAIL 출력 디렉토리 미지정")
		_done = true
		quit(1)
		return
	_out_dir = args[0]
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		printerr("CAPTURE_FAIL 씬 로드 실패")
		_done = true
		quit(1)
		return
	_screen = packed.instantiate()
	root.add_child(_screen)


# E13 재고 주입 — 새 커리어는 소모품 0이라 두 슬롯이 전부 빈다.
# capture_hub_shots 의 '크루 합류·재화 지급 상태로 찍는다'와 같은 성격의 하네스 조작이다.
# **첫 프레임 이후에 넣는다** — `_initialize()` 시점에는 화면의 `_ready()` 가 아직
# 돌지 않아 engine·data 가 null 이다 (주입이 조용히 무시된다 — 실측으로 확인).
func _seed_consumables() -> void:
	if _screen.engine == null:
		return
	var ids: Array = []
	for id in _screen.data.consumables:
		ids.append(String(id))
	if ids.size() < 2:
		return
	_screen.engine.consumables_held = {ids[0]: 1, ids[1]: 1}
	_screen._refresh_resources()
	_screen._refresh_action_enabled()


func _process(delta: float) -> bool:
	if _done:
		return true
	if not _seeded and _screen.engine != null:
		_seed_consumables()
		_seeded = true
	_elapsed += delta
	if _step >= _plan.size():
		print("CAPTURE_FLOW_OK shots=%d" % _shots)
		quit(0)
		return true
	var wait: float = _plan[_step][0]
	if _elapsed < wait:
		return false
	_elapsed = 0.0
	_shot(String(_plan[_step][1]))
	_advance(_step)
	_step += 1
	return false


# 캡처 직후 다음 단계로 넘기는 행동을 넣는다 — 캡처 시점이 곧 그 단계의 상태다.
func _advance(step: int) -> void:
	match step:
		0:
			_screen._on_consumable(0)     # E13 슬롯 1 사용 (T1 전속)
		1:
			_screen._on_primary_action()  # 스핀 (T2 커밋)
		7:
			_screen._on_primary_action()  # 확정 (T4 → T5)


func _shot(suffix: String) -> void:
	var img := root.get_texture().get_image()
	if img == null:
		printerr("CAPTURE_FAIL 뷰포트 이미지 없음")
		_done = true
		quit(1)
		return
	var path := "%s/race01_%s.png" % [_out_dir, suffix]
	if img.save_png(path) != OK:
		printerr("CAPTURE_FAIL 저장 실패 %s" % path)
		_done = true
		quit(1)
		return
	_shots += 1
	print("SHOT %s" % path)
