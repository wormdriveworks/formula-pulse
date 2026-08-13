# 플로우 관통 캡처 (킥오프 §5-5 "1 GP를 실화면으로 관통" · D09 §2.3 플로우맵 실주행).
#
#   <console.exe> --path godot --script tests/capture_flow_walk.gd -- <출력 디렉토리> [최대초]
#
# 앱 루트를 그대로 띄워 SYS-01 → SYS-02 → RACE-01 → RACE-03 → RUN-01 → … 를 자동 주파하며
# **화면이 바뀔 때마다** 한 장씩 남긴다. 무개입 경로(스핀 → 즉시 확정)로 돈다 —
# 개입 경로는 `test_seal_ui.gd` 가 별도로 본다.
#
# 시간은 `Engine.time_scale` 로 압축한다. 릴 정지 간격·타이머는 실시간 값을 그대로 쓰되
# 벽시계만 빨라지므로 **국면 순서와 봉인 규칙은 그대로 성립**한다.
extends SceneTree

const APP_ROOT := "res://ui/flow/app_root.tscn"
const TIME_SCALE := 20.0
const SETTLE_FRAMES := 4

var _out_dir := ""
var _app: Control
var _seen := ""
var _settle := 0
var _shots := 0
var _elapsed := 0.0
var _max_seconds := 90.0
var _done := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("WALK_FAIL 출력 디렉토리 미지정")
		_finish(1)
		return
	_out_dir = args[0]
	if args.size() >= 2:
		_max_seconds = float(args[1])
	Engine.time_scale = TIME_SCALE
	var packed := load(APP_ROOT) as PackedScene
	if packed == null:
		printerr("WALK_FAIL 앱 루트 로드 실패")
		_finish(1)
		return
	_app = packed.instantiate()
	root.add_child(_app)


func _process(delta: float) -> bool:
	if _done:
		return true
	_elapsed += delta
	if _elapsed > _max_seconds:
		print("WALK_TIMEOUT shots=%d last=%s" % [_shots, _seen])
		_finish(1)
		return true

	var screen := _current_screen()
	if screen == null:
		return false
	var name := screen.name
	if name != _seen:
		_seen = name
		_settle = 0
		return false
	# 전환 직후 몇 프레임은 레이아웃이 잡히는 중이라 그림이 흔들린다
	_settle += 1
	if _settle == SETTLE_FRAMES:
		_shot(name)
	if _settle >= SETTLE_FRAMES:
		_drive(screen)
	return false


func _current_screen() -> Control:
	for child in _app.get_children():
		if child is Control and child.has_method("bind"):
			return child
	return null


# 화면별 자동 진행 — 사람이 누를 것을 대신 누른다. 무개입 경로.
func _drive(screen: Control) -> void:
	match screen.name:
		"TitleScreen":
			screen._on_new_career()
		"SaveSlotScreen":
			screen._on_slot_pressed(1, false)
		"VnScreen":
			# 라인 진행 → 캘린더 공개 → 종료까지 진행 입력 반복 (§A-19/§A-20)
			screen._advance()
		"EventNodeScreen":
			(screen.get_node("%ProceedButton") as Button).pressed.emit()
		"RaceScreen":
			# 스핀 → (정지 연출) → 확정. 잠금 창은 규격대로 두고 지나가길 기다린다.
			if screen._timer_active and screen._confirm_lockout <= 0.0:
				screen._on_primary_action()
			elif not screen._timer_active and not screen._revealing and not screen.engine.finished:
				screen._on_primary_action()
		"GpResultScreen":
			(screen.get_node("%NextButton") as Button).pressed.emit()
		"RunRecapScreen":
			(screen.get_node("%NextButton") as Button).pressed.emit()
		"TourReportScreen":
			(screen.get_node("%NextButton") as Button).pressed.emit()
		"GarageScreen":
			print("WALK_OK shots=%d — 개러지 도달 (SET-01 ⑧ 이행)" % _shots)
			_finish(0)


func _shot(screen_name: String) -> void:
	var img := root.get_texture().get_image()
	if img == null:
		printerr("WALK_FAIL 뷰포트 이미지 없음")
		_finish(1)
		return
	var path := "%s/walk_%02d_%s.png" % [_out_dir, _shots + 1, screen_name]
	if img.save_png(path) != OK:
		printerr("WALK_FAIL 저장 실패 %s" % path)
		_finish(1)
		return
	_shots += 1
	print("SHOT %s" % path)


func _finish(code: int) -> void:
	_done = true
	Engine.time_scale = 1.0
	quit(code)
