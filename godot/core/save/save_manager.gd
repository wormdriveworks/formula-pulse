# 세이브 관리 (D12 §7.1~§7.3) — 프로필 분리 · 백업 1세대 · 마이그레이션 체인 · 충돌 정책.
# SaveService(봉투 I/O·체크섬)는 그대로 두고, 그 위의 정책 층을 여기서 담당한다.
#
# 저장 모델은 자동 저장 단일 — 수동 슬롯 없음(스커밍 벡터 차단, D12 §7.1).
# 구성 분리: 게임 진행 = 프로필별 / 옵션·설정 = 기기별(클라우드 비동기).
class_name SaveManager
extends RefCounted

# 판번은 SaveService 단일 정의를 승계한다 — 두 곳에 두면 봉투에 적히는 값과
# 마이그레이션 기준이 갈라져, 새로 쓴 세이브가 매 로드마다 구버전으로 취급된다.
const SCHEMA_VERSION := SaveService.SCHEMA_VERSION

const PROFILE_DIR_FORMAT := "user://profile_%d/"
const PROGRESS_FILENAME := "progress.json"
const BACKUP_FILENAME := "progress.bak.json"
const SNAPSHOT_FILENAME := "suspend.json"
const OPTIONS_PATH := "user://options.json"   # 기기별 — 프로필 밖 (D12 §7.1 구성 분리)


static func profile_dir(profile_index: int) -> String:
	return PROFILE_DIR_FORMAT % profile_index


static func progress_path(profile_index: int) -> String:
	return profile_dir(profile_index) + PROGRESS_FILENAME


static func backup_path(profile_index: int) -> String:
	return profile_dir(profile_index) + BACKUP_FILENAME


static func snapshot_path(profile_index: int) -> String:
	return profile_dir(profile_index) + SNAPSHOT_FILENAME


# 프로필 번호 유효성 — 개수는 데이터 창구 경유 (D12 §7.1 '확정 기준값', 조정 창구 D13/D14)
static func is_valid_profile(data: GameData, profile_index: int) -> bool:
	return profile_index >= 1 and profile_index <= data.param_int("param_save_profile_count")


static func ensure_profile_dir(profile_index: int) -> bool:
	var dir_path := profile_dir(profile_index)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		return true
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path)) == OK


# ── 정식 저장 (D12 §7.2 = RESULT 종료 시점 · 아웃게임 주요 커밋 직후) ──
# 백업 1세대: 새로 쓰기 전에 현 정본을 백업으로 회전한다. 회전 실패 시 저장을 중단한다 —
# 백업 없이 정본을 덮으면 손상 시 복구 경로(TC-P8)가 사라진다.
static func save_progress(profile_index: int, payload: Dictionary) -> Dictionary:
	var result := {"ok": false, "error": "", "backup_rotated": false}
	if not ensure_profile_dir(profile_index):
		result["error"] = "profile_dir"
		return result
	var target := progress_path(profile_index)
	if FileAccess.file_exists(target):
		if not _copy_file(target, backup_path(profile_index)):
			result["error"] = "backup_rotate_failed"
			return result
		result["backup_rotated"] = true
	var stamped := payload.duplicate(true)
	stamped["saved_at"] = int(Time.get_unix_time_from_system())
	stamped["progress_counter"] = int(payload.get("progress_counter", 0)) + 1
	if not SaveService.save_to(target, stamped):
		result["error"] = "write_failed"
		return result
	result["ok"] = true
	return result


# ── 로드 (D12 §7.1 손상 대응 = 체크섬 실패 시 백업 복원 제안) ──
# 반환: {ok, payload, error, source: "primary"|"backup", migrated_from}
# 백업으로 살아난 경우 source = "backup" — 호출 층이 사용자에게 복원 사실을 알린다.
static func load_progress(profile_index: int) -> Dictionary:
	var primary := _load_and_migrate(progress_path(profile_index))
	if bool(primary["ok"]):
		primary["source"] = "primary"
		return primary
	if String(primary["error"]) == "not_found":
		primary["source"] = "none"
		return primary
	# 정본이 손상됐다 — 백업 1세대로 복구를 시도한다
	var backup := _load_and_migrate(backup_path(profile_index))
	if bool(backup["ok"]):
		backup["source"] = "backup"
		backup["primary_error"] = primary["error"]
		return backup
	primary["source"] = "unrecoverable"
	primary["backup_error"] = backup["error"]
	return primary


static func _load_and_migrate(path: String) -> Dictionary:
	var loaded := SaveService.load_from(path)
	if not bool(loaded["ok"]):
		return {"ok": false, "payload": {}, "error": String(loaded["error"]), "migrated_from": -1}
	var version := int(loaded["schema_version"])
	var migrated := migrate(Dictionary(loaded["payload"]), version)
	if not bool(migrated["ok"]):
		return {"ok": false, "payload": {}, "error": String(migrated["error"]), "migrated_from": version}
	return {
		"ok": true,
		"payload": migrated["payload"],
		"error": "",
		"migrated_from": version if version != SCHEMA_VERSION else -1,
	}


# ── 마이그레이션 체인 (D12 §7.1) — 버전 상향 시 순차 적용, 다운그레이드 비지원 ──
# 각 단계는 "직전 판번 → 다음 판번" 단일 격차만 처리한다. 격차를 건너뛰는 변환을 두지 않는다:
# 중간 단계가 늘어날 때 조합 폭발이 나고, 어느 경로를 탔는지 재현할 수 없게 된다.
static func migrate(payload: Dictionary, from_version: int) -> Dictionary:
	if from_version > SCHEMA_VERSION:
		return {"ok": false, "payload": {}, "error": "downgrade_refused"}
	if from_version < 1:
		return {"ok": false, "payload": {}, "error": "unknown_version"}
	var current := payload.duplicate(true)
	var version := from_version
	while version < SCHEMA_VERSION:
		match version:
			1:
				current = _migrate_1_to_2(current)
			_:
				return {"ok": false, "payload": {}, "error": "no_migrator_%d" % version}
		version += 1
	return {"ok": true, "payload": current, "error": ""}


# v1 → v2: 레조넌스 오버레이 필드 신설 (MS-2). MS-1 세이브에는 이 필드가 없다.
# 채우는 값은 임의 수치가 아니라 **구조적 부재값**이다 — slot 0 = "이 서킷에 오버레이 없음",
# 공표 안 됨, 보정 0. D13 값을 대체하는 기본값이 아니므로 불변규칙 2와 무접촉.
static func _migrate_1_to_2(payload: Dictionary) -> Dictionary:
	var migrated := payload.duplicate(true)
	if not migrated.has("resonance_sector_slot"):
		migrated["resonance_sector_slot"] = 0
	if not migrated.has("resonance_announced"):
		migrated["resonance_announced"] = false
	if not migrated.has("resonance_duel_bonus"):
		migrated["resonance_duel_bonus"] = 0.0
	return migrated


# ── 클라우드 충돌 정책 (D12 §7.3) ──
# "최신 진행 우선(진행도 비교 → 동률 시 최신 타임스탬프) + 불일치 시 사용자 선택"
# [가안] '불일치'의 판정: 진행도와 타임스탬프의 순서가 서로 어긋나는 경우로 읽는다.
# (진행도는 앞서는데 타임스탬프는 뒤진 쪽 = 어느 쪽이 최신인지 정본이 결정하지 않는 상태)
# 한쪽이 두 축 모두에서 앞서거나, 진행도만으로 결판나면 자동 선택한다. impl_log 등재.
enum ConflictChoice { LOCAL, REMOTE, ASK }


static func resolve_cloud_conflict(local: Dictionary, remote: Dictionary) -> int:
	var local_progress := int(local.get("progress_counter", 0))
	var remote_progress := int(remote.get("progress_counter", 0))
	var local_time := int(local.get("saved_at", 0))
	var remote_time := int(remote.get("saved_at", 0))
	if local_progress == remote_progress:
		if local_time == remote_time:
			return ConflictChoice.LOCAL      # 완전 동률 — 전송 불요
		return ConflictChoice.LOCAL if local_time > remote_time else ConflictChoice.REMOTE
	var progress_favors_local := local_progress > remote_progress
	var time_favors_local := local_time > remote_time
	if local_time == remote_time or progress_favors_local == time_favors_local:
		return ConflictChoice.LOCAL if progress_favors_local else ConflictChoice.REMOTE
	return ConflictChoice.ASK


# ── 서스펜드 스냅샷 (D12 §7.2) — 1회성: 로드 시 소거 ──
static func save_snapshot(profile_index: int, payload: Dictionary) -> bool:
	if not ensure_profile_dir(profile_index):
		return false
	return SaveService.save_to(snapshot_path(profile_index), payload)


# 소거를 호출 층 재량에 맡기지 않는다 — 스냅샷이 남으면 같은 지점을 반복 재개할 수 있고
# 그것이 곧 스커밍 경로가 된다 (D12 §6.2·§7.2).
static func consume_snapshot(profile_index: int) -> Dictionary:
	var loaded := _load_and_migrate(snapshot_path(profile_index))
	SaveService.delete_save(snapshot_path(profile_index))
	return loaded


static func has_snapshot(profile_index: int) -> bool:
	return FileAccess.file_exists(snapshot_path(profile_index))


static func _copy_file(from_path: String, to_path: String) -> bool:
	var source := FileAccess.open(from_path, FileAccess.READ)
	if source == null:
		return false
	var text := source.get_as_text()
	source.close()
	var target := FileAccess.open(to_path, FileAccess.WRITE)
	if target == null:
		return false
	target.store_string(text)
	target.close()
	return true
