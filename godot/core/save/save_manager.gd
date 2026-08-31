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

const PROFILE_DIR_NAME_FORMAT := "profile_%d/"
const PROGRESS_FILENAME := "progress.json"
const BACKUP_FILENAME := "progress.bak.json"
const SNAPSHOT_FILENAME := "suspend.json"
const QUARANTINE_FILENAME := "suspend.bad.json"
const OPTIONS_FILENAME := "options.json"   # 기기별 — 프로필 밖 (D12 §7.1 구성 분리)

# ── 저장 루트 (25차 신설 — 차단급) ──
#
# **실피해가 먼저 있었다**: 게이트가 실 프로필의 진행 세이브를 지우고 백업을 덮었다
# (주력 13차 실증 — 슬롯 2 커리어 소실). 원인은 테스트가 실기와 **같은 `user://` 루트**를
# 쓴 것이고, 그것을 막을 자리가 없었다.
#
# **기본값을 두지 않는다.** 안전한 기본값(예: 항상 테스트 루트)은 실기를 망가뜨리고,
# 편한 기본값(항상 `user://`)은 지금의 사고다. 그래서 **미설정 = 경로 없음**으로 두어
# 아무도 부르지 않으면 저장·로드가 **소리내어 실패**한다 — 이 파일이 프로필 개수에
# 이미 쓰고 있는 방식과 같다("미설정 상태의 저장·로드는 실패하게 해 우회를 소리나게 만든다").
const LIVE_ROOT := "user://"
const TEST_ROOT := "user://test_profiles/"

static var _root: String = ""


# 실기 루트 — **부르는 곳은 앱 부팅 한 곳**이다 (`app_root`).
static func use_live_root() -> void:
	# **이미 잡힌 루트를 덮지 않는다.** 하네스가 `app_root.tscn` 을 실제로 세우는 축이 있어
	# (UISCR 단독 부팅·SEAL-E) 그 `_ready()` 가 격리 루트를 실기로 되돌렸다 — 게이트 밖
	# 바이트 대조가 그것을 잡았다(실 프로필 `profile_2` 재변조 실측). 앱은 **아무도 잡지
	# 않았을 때만** 실기 루트를 주장한다.
	if not _root.is_empty():
		return
	_root = LIVE_ROOT


# 격리 루트 — 테스트·캡처 하네스 전속. 디렉토리를 함께 보장한다.
static func use_test_root() -> void:
	if _root == TEST_ROOT:
		return   # 멱등 — `_process` 하네스가 프레임마다 불러도 비용 0
	_root = TEST_ROOT
	var absolute := ProjectSettings.globalize_path(TEST_ROOT)
	if not DirAccess.dir_exists_absolute(absolute):
		DirAccess.make_dir_recursive_absolute(absolute)


static func root() -> String:
	if _root.is_empty():
		push_error("SaveManager: save root unset - call use_live_root() or use_test_root()")
	return _root


static func is_test_root() -> bool:
	return _root == TEST_ROOT


static func options_path() -> String:
	var base := root()
	return "" if base.is_empty() else base + OPTIONS_FILENAME

# 프로필 개수는 데이터 창구(D12 §7.1 '확정 기준값')에서 온다. 정적 층에 붙잡아 두는 이유:
# 범위 강제를 호출부 재량에 맡기면 아무도 부르지 않아(실측: 호출부 0건) 범위 밖 프로필
# 디렉토리가 조용히 생성된다. 미설정 상태의 저장·로드는 실패하게 해 우회를 소리나게 만든다.
static var _profile_count: int = 0


static func configure(data: GameData) -> void:
	_profile_count = data.param_int("param_save_profile_count")


static func profile_dir(profile_index: int) -> String:
	var base := root()
	return "" if base.is_empty() else base + (PROFILE_DIR_NAME_FORMAT % profile_index)


static func progress_path(profile_index: int) -> String:
	return profile_dir(profile_index) + PROGRESS_FILENAME


static func backup_path(profile_index: int) -> String:
	return profile_dir(profile_index) + BACKUP_FILENAME


static func snapshot_path(profile_index: int) -> String:
	return profile_dir(profile_index) + SNAPSHOT_FILENAME


# 스냅샷·진행 세이브·백업은 파일명이 서로 달라야 한다. 겹치면 서스펜드가 정본을 덮는다.
static func paths_are_distinct() -> bool:
	return PROGRESS_FILENAME != SNAPSHOT_FILENAME \
		and PROGRESS_FILENAME != BACKUP_FILENAME \
		and SNAPSHOT_FILENAME != BACKUP_FILENAME \
		and QUARANTINE_FILENAME != SNAPSHOT_FILENAME


static func quarantine_path(profile_index: int) -> String:
	return profile_dir(profile_index) + QUARANTINE_FILENAME


# 프로필 번호 유효성 — 개수는 데이터 창구 경유 (D12 §7.1 '확정 기준값', 조정 창구 D13/D14)
static func is_valid_profile(data: GameData, profile_index: int) -> bool:
	return profile_index >= 1 and profile_index <= data.param_int("param_save_profile_count")


# 설정된 범위 안인가 — configure() 이전이거나 범위 밖이면 false.
static func _in_configured_range(profile_index: int) -> bool:
	return _profile_count > 0 and profile_index >= 1 and profile_index <= _profile_count


static func ensure_profile_dir(profile_index: int) -> bool:
	var dir_path := profile_dir(profile_index)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		return true
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path)) == OK


# ── 정식 저장 (D12 §7.2 = RESULT 종료 시점 · 아웃게임 주요 커밋 직후) ──
# 백업 1세대: 새로 쓰기 전에 현 정본을 백업으로 회전한다. 회전 실패 시 저장을 중단한다 —
# 백업 없이 정본을 덮으면 손상 시 복구 경로(TC-P8)가 사라진다.
static func save_progress(profile_index: int, payload: Dictionary) -> Dictionary:
	var result := {"ok": false, "error": "", "backup_rotated": false, "backup_kept_reason": "", "progress_counter": 0}
	if _profile_count <= 0:
		# 미설정과 범위 밖은 원인이 다르다 — 같은 코드로 보고하면 호출 층이
		# "프로필 번호가 잘못됐다"고 읽고 configure() 누락을 영원히 못 찾는다.
		result["error"] = "not_configured"
		push_error("SaveManager: configure(data) before saving")
		return result
	if not _in_configured_range(profile_index):
		result["error"] = "profile_out_of_range"
		push_error("SaveManager: profile %d out of configured range (count=%d)" % [profile_index, _profile_count])
		return result
	if not ensure_profile_dir(profile_index):
		result["error"] = "profile_dir"
		return result
	var target := progress_path(profile_index)
	if FileAccess.file_exists(target):
		# 회전 전에 현 정본이 성한지 확인한다. 손상본을 백업 슬롯에 올리면
		# 방금 복구에 사용한 유일한 성한 세대가 사라지고 다음 손상은 즉시 복구 불능이 된다
		# (백업 복구 직후의 정상 저장이 정확히 그 경로였다).
		var current := SaveService.load_from(target)
		if bool(current["ok"]):
			if not _copy_file(target, backup_path(profile_index)):
				result["error"] = "backup_rotate_failed"
				return result
			result["backup_rotated"] = true
		else:
			result["backup_kept_reason"] = String(current["error"])
	var stamped := payload.duplicate(true)
	stamped["saved_at"] = int(Time.get_unix_time_from_system())
	# 진행도는 **디스크에 적힌 값** 기준으로 올린다. 인자 payload에서만 파생하면
	# 호출 층이 새 카운터를 돌려받지 못해(인메모리 dict에 없음) 매 저장이 0+1=1이 되고,
	# 클라우드 충돌 정책의 1차 판정축(D12 §7.3 '진행도 비교')이 상수가 되어 무효화된다.
	# **백업까지 본다:** 정본이 손상되면 그 값을 신뢰할 수 없어 0이 되는데, 백업을 보지 않으면
	# 손상 1회로 카운터가 후퇴한다(3 → 1). 후퇴한 카운터는 클라우드 충돌에서 최신 진행을
	# 뒤진 것으로 오판하게 만든다.
	stamped["progress_counter"] = maxi(maxi(_disk_counter(target),
		_disk_counter(backup_path(profile_index))), int(payload.get("progress_counter", 0))) + 1
	if not SaveService.save_to(target, stamped):
		result["error"] = "write_failed"
		return result
	result["ok"] = true
	result["progress_counter"] = int(stamped["progress_counter"])
	result["payload"] = stamped   # 호출 층이 인메모리 상태를 갱신할 수 있도록 돌려준다
	return result


# ── 로드 (D12 §7.1 손상 대응 = 체크섬 실패 시 백업 복원 제안) ──
# 반환: {ok, payload, error, source: "primary"|"backup", migrated_from}
# 백업으로 살아난 경우 source = "backup" — 호출 층이 사용자에게 복원 사실을 알린다.
static func load_progress(profile_index: int) -> Dictionary:
	if _profile_count <= 0:
		return {"ok": false, "payload": {}, "error": "not_configured", "source": "none",
			"migrated_from": -1, "content_checksum": ""}
	if not _in_configured_range(profile_index):
		return {"ok": false, "payload": {}, "error": "profile_out_of_range", "source": "none",
			"migrated_from": -1, "content_checksum": ""}
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
	primary["source"] = "version_too_new" if String(primary["error"]) == "downgrade_refused" else "unrecoverable"
	primary["backup_error"] = backup["error"]
	return primary


static func _load_and_migrate(path: String) -> Dictionary:
	var loaded := SaveService.load_from(path)
	if not bool(loaded["ok"]):
		return {"ok": false, "payload": {}, "error": String(loaded["error"]), "migrated_from": -1, "content_checksum": ""}
	var version := int(loaded["schema_version"])
	var migrated := migrate(Dictionary(loaded["payload"]), version)
	if not bool(migrated["ok"]):
		return {"ok": false, "payload": {}, "error": String(migrated["error"]), "migrated_from": version, "content_checksum": ""}
	return {
		"ok": true,
		"payload": migrated["payload"],
		"error": "",
		"migrated_from": version if version != SCHEMA_VERSION else -1,
		"content_checksum": String(loaded["content_checksum"]),
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
			2:
				current = _migrate_2_to_3(current)
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


# v2 → v3: 레조넌스 추첨의 서킷 축·1회 소진 플래그 신설.
# v2는 섹터 슬롯만 담고 있어 어느 서킷의 오버레이인지 알 수 없다 — 서킷을 특정할 수
# 없는 슬롯은 발동 대상이 아니므로, 부재값(빈 서킷 id)이 곧 "오버레이 없음"이 된다.
static func _migrate_2_to_3(payload: Dictionary) -> Dictionary:
	var migrated := payload.duplicate(true)
	if not migrated.has("resonance_circuit_id"):
		migrated["resonance_circuit_id"] = ""
	if not migrated.has("resonance_consumed"):
		migrated["resonance_consumed"] = false
	return migrated


# ── 프로필 삭제 (개선 2026-09-01 — SYS-02 슬롯 관리) ──
# 진행·백업·스냅샷·격리 4파일 전부를 걷는다 — 진행만 지우면 백업이 '빈 슬롯'을 거짓으로
# 만들지는 않지만(로드는 progress 부재 = not_found), 다음 커리어의 첫 백업 회전이 남의
# 세대를 물려받는다. 확인 UI 는 호출 층 몫이다 — 여기는 실행만 한다.
static func delete_progress(profile_index: int) -> bool:
	if not _in_configured_range(profile_index):
		push_error("SaveManager: profile %d out of configured range" % profile_index)
		return false
	for path in [progress_path(profile_index), backup_path(profile_index),
			snapshot_path(profile_index), quarantine_path(profile_index)]:
		if FileAccess.file_exists(String(path)):
			SaveService.delete_save(String(path))
	return true


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
			# 진행도·시각이 같아도 내용이 같다는 보장은 없다 — 같은 초에 두 기기가 각자
			# 다른 진행을 저장하면 '완전 동률'로 보이고 원격이 조용히 폐기된다.
			# 봉투 체크섬이 이미 있으니 내용 축으로 쓴다. 없거나 같으면 전송 불요.
			var local_checksum := String(local.get("content_checksum", ""))
			var remote_checksum := String(remote.get("content_checksum", ""))
			if local_checksum != "" and remote_checksum != "" and local_checksum != remote_checksum:
				return ConflictChoice.ASK
			return ConflictChoice.LOCAL
		return ConflictChoice.LOCAL if local_time > remote_time else ConflictChoice.REMOTE
	var progress_favors_local := local_progress > remote_progress
	var time_favors_local := local_time > remote_time
	if local_time == remote_time or progress_favors_local == time_favors_local:
		return ConflictChoice.LOCAL if progress_favors_local else ConflictChoice.REMOTE
	return ConflictChoice.ASK


# ── 서스펜드 스냅샷 (D12 §7.2) — 1회성: 로드 시 소거 ──
static func save_snapshot(profile_index: int, payload: Dictionary) -> bool:
	if not _in_configured_range(profile_index):
		push_error("SaveManager: profile %d out of configured range" % profile_index)
		return false
	if not ensure_profile_dir(profile_index):
		return false
	return SaveService.save_to(snapshot_path(profile_index), payload)


# 소거를 호출 층 재량에 맡기지 않는다 — 스냅샷이 남으면 같은 지점을 반복 재개할 수 있고
# 그것이 곧 스커밍 경로가 된다 (D12 §6.2·§7.2).
static func consume_snapshot(profile_index: int) -> Dictionary:
	var path := snapshot_path(profile_index)
	var loaded := _load_and_migrate(path)
	if bool(loaded["ok"]):
		SaveService.delete_save(path)
	elif String(loaded["error"]) != "not_found":
		# 손상 스냅샷은 삭제가 아니라 격리한다 — 지우면 진단 근거가 사라지고,
		# 남겨 두면 재소비가 가능해진다(스커밍 경로). 격리는 둘 다 막는다.
		_copy_file(path, quarantine_path(profile_index))
		SaveService.delete_save(path)
	return loaded


static func has_snapshot(profile_index: int) -> bool:
	return FileAccess.file_exists(snapshot_path(profile_index))


# 디스크의 진행도 카운터 — 읽을 수 없으면 0 (신규·손상). 체크섬 실패본의 값은 신뢰하지 않는다.
static func _disk_counter(path: String) -> int:
	var loaded := SaveService.load_from(path)
	if not bool(loaded["ok"]):
		return 0
	return int(Dictionary(loaded["payload"]).get("progress_counter", 0))


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
