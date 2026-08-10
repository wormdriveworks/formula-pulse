# IAdService 데스크탑 널 구현 — 호출 즉시 '광고 없음' 통과 (D12 §2.2, F2 종결 구조 준수).
# 데스크탑 빌드에는 광고 SDK 심볼이 존재하지 않는다 (D12 §2.3).
class_name DesktopAdService
extends IAdService


func load_ad(kind: int) -> void:
	ad_state_changed.emit(kind, AdState.CLOSED)


func show_ad(kind: int) -> void:
	ad_state_changed.emit(kind, AdState.CLOSED)
	if kind == AdKind.REWARDED:
		rewarded_result.emit(false)


func get_state(_kind: int) -> int:
	return AdState.IDLE


func is_null_service() -> bool:
	return true
