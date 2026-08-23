# 폰트 계열 실측 (D10 §5.7 검증 4항 · D09 §6.6 자수 교차 검증의 재확인).
#
#   <console.exe> --headless --path godot --script tests/measure_log_width.gd
#
# D10 §5.7이 본문 계열을 8/9/10px로 확정한 근거는 **로그 존 폭에 전각 22자가 한 줄로 들어가는가**
# 였다(12px 단일 계열이 이 검증에서 떨어졌다). 폰트 실물이 바뀌면 그 계산의 전제가 바뀌므로
# 원도별로 다시 잰다 — 자수 22자·시각 줄 2는 불변이고(D14 §5.1), 움직일 수 있는 것은
# 폰트 원도와 존 폭(D13 창구)뿐이다.
#
# 검증 ④(D10 §5.7)도 함께 본다: **도트 폰트 반각 = 전각의 정확히 1/2**.
# 이 성질이 깨지면 130% 번역 팽창 전제(D04 §5.6-7)가 성립하지 않는다.
extends SceneTree

const SCENE_PATH := "res://ui/flow/app_root.tscn"
const FONTS := {
	"Galmuri9": ["res://assets/fonts/Galmuri9.ttf", 9],
	"Galmuri11": ["res://assets/fonts/Galmuri11.ttf", 11],
	"Galmuri11-Bold": ["res://assets/fonts/Galmuri11-Bold.ttf", 11],
	"Galmuri14": ["res://assets/fonts/Galmuri14.ttf", 14],
	"GalmuriMono11": ["res://assets/fonts/GalmuriMono11.ttf", 11],
}
const FULL_22 := "가나다라마바사아자차카타파하거너더러머버서어"  # 전각 22자
const LATIN_NARROW := "iiiiiiiiiiiiiiiiiiiiii"                    # 반각 22자 (최협)
const LATIN_WIDE := "WWWWWWWWWWWWWWWWWWWWWW"                      # 반각 22자 (최광)


func _init() -> void:
	SaveManager.use_test_root()   # 저장 격리 — 실 프로필 무접촉 (25차)
	print("MEASURE_FONTS 전각 22자 기준")
	for label in FONTS:
		var entry: Array = FONTS[label]
		var font := load(String(entry[0])) as Font
		if font == null:
			printerr("  %s: 로드 실패" % label)
			continue
		var size := int(entry[1])
		var full := font.get_string_size(FULL_22, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var narrow := font.get_string_size(LATIN_NARROW, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var wide := font.get_string_size(LATIN_WIDE, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		# 반각 = 전각의 1/2 이면 22자 폭도 정확히 절반이어야 한다 (검증 ④)
		var half_ok := is_equal_approx(narrow, full * 0.5) and is_equal_approx(wide, full * 0.5)
		print("  %-14s size=%2d  전각22=%5.1f  반각i=%5.1f  반각W=%5.1f  반각=전각½ %s" % [
			label, size, full, narrow, wide, "OK" if half_ok else "아님(비례폭)",
		])

	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		printerr("MEASURE_FAIL 앱 루트 로드 실패")
		quit(1)
		return
	var app := packed.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	print("MEASURE_OK")
	quit(0)
