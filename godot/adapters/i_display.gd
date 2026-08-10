# D12 §2.2 / §9.7 — IDisplay: 주사율·화면 잠금·프레임 상한 계약.
# 데스크탑 = 미사용(스텁) / 모바일 = O-M2·keep-screen-on.
class_name IDisplay
extends RefCounted


func set_frame_cap(_max_fps: int) -> void:
	push_error("IDisplay.set_frame_cap is abstract")


# keep-screen-on = 개입 창(T4)·듀얼 개입 창 한정 (D12 §2.4)
func set_keep_screen_on(_enabled: bool) -> void:
	push_error("IDisplay.set_keep_screen_on is abstract")
