# HUB 8종 + COM-01 캡처 (눈 검증 경로 — 세션을 주입해 화면별로 한 장씩).
#
#   <console.exe> --path godot --script tests/capture_hub_shots.gd -- <출력 디렉토리>
#
# 개러지 경유 관통은 capture_flow_walk 가 본다. 여기서는 각 화면을 세션 주입으로 직접 세워
# 표시 요소(공통 바·카드·잠금 표기)를 확인한다. 크루 유무 양 상태를 보기 위해
# 후반 화면은 크루 합류 + 재화 지급 상태로 찍는다.
extends SceneTree

const SHOTS := [
	# [파일명, 라우트, 크루·재화 지급 여부]
	["hub01_garage_start", "res://ui/hub/garage_screen.tscn", false],
	["hub02_repair", "res://ui/hub/repair_bay_screen.tscn", false],
	# 손상 상태 — §A-12 완전 회복 고스트 게이지·총비용은 손상이 있어야 보인다
	["hub02_repair_damaged", "res://ui/hub/repair_bay_screen.tscn", true],
	["hub03_tuning_locked", "res://ui/hub/tuning_bench_screen.tscn", false],
	["hub04_strategy", "res://ui/hub/strategy_screen.tscn", true],
	["hub05_records", "res://ui/hub/records_screen.tscn", false],
	["hub06_sponsor", "res://ui/hub/sponsor_desk_screen.tscn", true],
	["hub07_facility", "res://ui/hub/facility_screen.tscn", true],
	["hub08_overhaul", "res://ui/hub/overhaul_screen.tscn", false],
	["hub01_garage_crewed", "res://ui/hub/garage_screen.tscn", true],
]

var _out_dir := ""
var _session: RunSession
var _rich_session: RunSession
var _index := 0
var _settle := 0
var _current: Control
var _done := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("HUBSHOT_FAIL 출력 디렉토리 미지정")
		_finish(1)
		return
	_out_dir = args[0]
	var data := GameData.new()
	data.load_all()
	_session = RunSession.new()
	_session.setup(data)
	_session.begin_career(1)
	# 크루·재화 상태 — 개방·구매 가능 표기를 눈으로 보기 위한 세션
	_rich_session = RunSession.new()
	_rich_session.setup(data)
	_rich_session.begin_career(2)
	for crew_id in ["crew_theo", "crew_marta", "crew_oscar", "crew_nadia", "crew_sasha"]:
		_rich_session.outgame.crew[crew_id] = true
	_rich_session.outgame.gain_credits(2000)
	_rich_session.outgame.gain_drive_data(500)
	_rich_session.outgame.chassis = 46.0    # 손상 상태 — 정비 카드 활성·게이지 확인용
	_next()


func _next() -> void:
	if _current != null:
		root.remove_child(_current)
		_current.queue_free()
		_current = null
	if _index >= SHOTS.size():
		print("HUBSHOT_OK shots=%d" % _index)
		_finish(0)
		return
	var entry: Array = SHOTS[_index]
	var packed := load(String(entry[1])) as PackedScene
	if packed == null:
		printerr("HUBSHOT_FAIL 씬 로드 실패: %s" % String(entry[1]))
		_finish(1)
		return
	_current = packed.instantiate()
	var session := _rich_session if bool(entry[2]) else _session
	_current.session = session
	root.add_child(_current)
	_current.bind(session, {})
	_settle = 0


func _process(_delta: float) -> bool:
	if _done or _current == null:
		return _done
	_settle += 1
	if _settle < 5:
		return false
	var img := root.get_texture().get_image()
	if img == null:
		printerr("HUBSHOT_FAIL 뷰포트 이미지 없음")
		_finish(1)
		return true
	var path := "%s/%s.png" % [_out_dir, String(SHOTS[_index][0])]
	if img.save_png(path) != OK:
		printerr("HUBSHOT_FAIL 저장 실패 %s" % path)
		_finish(1)
		return true
	print("SHOT %s" % path)
	_index += 1
	_next()
	return false


func _finish(code: int) -> void:
	_done = true
	quit(code)
