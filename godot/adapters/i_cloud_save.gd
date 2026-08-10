# D12 §2.2 / §7.3 — ICloudSave: 세이브 동기 상태 계약.
# 데스크탑 = Steam Auto-Cloud (엔진 외부 — 코드 통합 불요, 스텁만).
class_name ICloudSave
extends RefCounted

enum SyncState { DISABLED, IDLE, SYNCING, CONFLICT, ERROR }

signal sync_state_changed(state: int)


func get_sync_state() -> int:
	push_error("ICloudSave.get_sync_state is abstract")
	return SyncState.DISABLED


# 충돌 정책: 최신 진행 우선 → 동률 시 최신 타임스탬프 → 불일치 시 사용자 선택 (D12 §7.3)
func request_sync() -> void:
	push_error("ICloudSave.request_sync is abstract")
