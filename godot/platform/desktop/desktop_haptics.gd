# IHaptics 데스크탑 구현 — 패드 진동 (D12 §2.2). 연결 패드 전체에 발화.
class_name DesktopHaptics
extends IHaptics


func vibrate(strength: float, duration_sec: float) -> void:
	for device_id in Input.get_connected_joypads():
		Input.start_joy_vibration(device_id, strength, strength, duration_sec)
