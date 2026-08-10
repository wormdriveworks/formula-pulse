# ICloudSave 데스크탑 구현 — Steam Auto-Cloud는 엔진 외부(세이브 디렉토리 지정)라
# 코드 통합이 불요하다 (D12 §7.3 확정). 본 구현은 상태 조회 스텁만 제공.
class_name DesktopCloudSave
extends ICloudSave


func get_sync_state() -> int:
	return SyncState.DISABLED


func request_sync() -> void:
	pass
