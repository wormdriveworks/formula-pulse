# D12 §2.2 / §11 — IAdService: 전면/보상형 로드·표시·상태 조회 계약.
# 광고 규칙 층(D16)은 모바일 레이어 전속 — 코어는 본 인터페이스만 안다.
class_name IAdService
extends RefCounted

# D12 §11.3 어댑터 상태
enum AdState { IDLE, LOADING, READY, SHOWING, CLOSED, FAILED_NOFILL, FAILED_NETWORK }

enum AdKind { INTERSTITIAL, REWARDED }

# 상태 변화 통지: (kind: AdKind, state: AdState)
signal ad_state_changed(kind: int, state: int)
# 보상형 결과 통지: (completed: bool) — 미완 = 보상 미지급 (D12 §11.4)
signal rewarded_result(completed: bool)


func load_ad(_kind: int) -> void:
	push_error("IAdService.load_ad is abstract")


func show_ad(_kind: int) -> void:
	push_error("IAdService.show_ad is abstract")


func get_state(_kind: int) -> int:
	push_error("IAdService.get_state is abstract")
	return AdState.IDLE


# 데스크탑 널 구현 판별용 — true면 호출 즉시 '광고 없음' 통과 (D12 §2.2)
func is_null_service() -> bool:
	return false
