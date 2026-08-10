# 헤드리스 로직 테스트 예시 (원격 서버에서 실행)
#   godot --headless --path . --script test/logic_test.gd
# 기대: "LOGIC_TEST_PASS ...", 종료코드 0
extends SceneTree

func _init() -> void:
	# TODO: 실제 게임 로직을 preload 하여 검증하도록 교체
	var sum := 2 + 2
	assert(sum == 4, "math is broken")
	print("LOGIC_TEST_PASS sum=", sum)
	quit()
