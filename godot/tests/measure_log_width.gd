# 로그 존 자수 실측 (D09 §6.6 자수 교차 검증 · D10 §5.7 폰트 계열 판정의 근거).
#
#   <console.exe> --headless --path godot --script tests/measure_log_width.gd
#
# D10 §5.7은 로그 존 폭에 **전각 22자가 한 줄로** 들어가는지를 기준으로 본문 폰트 계열을
# 8/9/10px로 확정했다(12px 단일 계열이 이 검증에서 떨어졌다). 폰트 실물이 바뀌면 그 계산의
# 전제가 바뀌므로 실측으로 다시 확인한다 — 자수 22자·시각 줄 2는 불변이고(D14 §5.1),
# 움직일 수 있는 것은 폰트 원도와 존 폭뿐이다.
extends SceneTree

const FONT_PATH := "res://assets/fonts/GalmuriMono11.ttf"
const SCENE_PATH := "res://ui/race/race_screen.tscn"
const FULL_WIDTH_22 := "가나다라마바사아자차카타파하거너더러머버"  # 전각 20자
const SAMPLE_SIZES := [8, 9, 10, 11, 12, 14, 16, 22]


func _init() -> void:
	var font := load(FONT_PATH) as Font
	if font == null:
		printerr("MEASURE_FAIL 폰트 로드 실패: %s" % FONT_PATH)
		quit(1)
		return

	# 전각 22자 문자열을 만든다 (반각 혼입 없이)
	var sample := ""
	for i in range(22):
		sample += "가"

	print("MEASURE font=%s" % FONT_PATH)
	for size in SAMPLE_SIZES:
		var width := font.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		print("  size=%2d  전각22자 폭 = %6.1f px (원도 좌표)" % [size, width])

	# 실화면의 로그 슬롯 가용 폭을 잰다 — 계산이 아니라 실제 레이아웃에서.
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		printerr("MEASURE_FAIL 씬 로드 실패")
		quit(1)
		return
	var screen := packed.instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame

	var feed: Control = screen.get_node("%E10LogFeed")
	print("  로그 존 실폭 = %.1f px" % feed.size.x)
	if feed.get_child_count() > 0:
		var slot: Control = feed.get_child(0)
		var body: Control = slot.get_child(1)
		print("  슬롯 본문 가용 폭 = %.1f px (화자 표지 제외분)" % body.size.x)
	print("MEASURE_OK")
	quit(0)
