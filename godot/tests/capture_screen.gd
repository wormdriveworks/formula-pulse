# 런타임 화면 캡처 도구 (주력 GUI 머신 전속 — 눈 검증 경로).
#
# GDAI MCP 없이 "실행된 화면"을 파일로 얻기 위한 경로다. 헤드리스가 아닌 실행에서
# 지정 씬을 root에 붙이고 N프레임 뒤 뷰포트를 PNG로 저장한다.
#
#   <console.exe> --path godot --script tests/capture_screen.gd -- <씬 경로> <출력 절대경로> [대기 프레임]
#
# `--headless`를 붙이면 렌더 결과가 비므로 붙이지 않는다.
extends SceneTree

const DEFAULT_SCENE := "res://ui/debug_race.tscn"
const DEFAULT_WAIT_FRAMES := 30

var _frames := 0
var _wait_frames := DEFAULT_WAIT_FRAMES
var _out_path := ""
var _scene_path := DEFAULT_SCENE
var _failed := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_scene_path = args[0]
	if args.size() >= 2:
		_out_path = args[1]
	if args.size() >= 3:
		_wait_frames = int(args[2])
	if _out_path.is_empty():
		printerr("CAPTURE_FAIL 출력 경로 미지정")
		_failed = true
		quit(1)
		return
	if not ResourceLoader.exists(_scene_path):
		printerr("CAPTURE_FAIL 씬 없음: %s" % _scene_path)
		_failed = true
		quit(1)
		return
	var packed := load(_scene_path) as PackedScene
	if packed == null:
		printerr("CAPTURE_FAIL 씬 로드 실패: %s" % _scene_path)
		_failed = true
		quit(1)
		return
	root.add_child(packed.instantiate())


func _process(_delta: float) -> bool:
	if _failed:
		return true
	_frames += 1
	if _frames < _wait_frames:
		return false
	var img := root.get_texture().get_image()
	if img == null:
		printerr("CAPTURE_FAIL 뷰포트 이미지 없음 (headless 실행?)")
		quit(1)
		return true
	var err := img.save_png(_out_path)
	if err != OK:
		printerr("CAPTURE_FAIL 저장 실패 err=%d path=%s" % [err, _out_path])
		quit(1)
		return true
	print("CAPTURE_OK %dx%d %s" % [img.get_width(), img.get_height(), _out_path])
	quit(0)
	return true
