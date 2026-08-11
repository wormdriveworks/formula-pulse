# 세이브 골격 (D12 §7.1 — JSON + schema_version + 무결성 체크섬).
# 체크섬 목적 = 손상 감지 (변조 방어 비목적). 다운그레이드 = 로드 거부.
# 서스펜드 스냅샷(§7.2)은 1회성 — 로드 시 소거는 호출 층이 delete_save로 수행.
class_name SaveService
extends RefCounted

# 진행 세이브 스키마 판번 (단일 정의 — SaveManager가 이 상수를 승계한다).
# MS-1 = 1 / MS-2 = 2 (레조넌스 오버레이 필드) / 3 (레조넌스 서킷 축·1회성 신설).
const SCHEMA_VERSION := 3


# payload는 문자열로 내장 — 체크섬 검증이 JSON 재직렬화 정밀도에 오염되지 않도록 (손상 감지 정확성)
static func save_to(path: String, payload: Dictionary) -> bool:
	var payload_json := JSON.stringify(payload, "", true)
	var envelope := {
		"schema_version": SCHEMA_VERSION,
		"checksum": payload_json.md5_text(),
		"payload_json": payload_json,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveService: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(envelope, "", true))
	file.close()
	return true


# 반환: {"ok": bool, "payload": Dictionary, "error": String}
static func load_from(path: String) -> Dictionary:
	var result := {"ok": false, "payload": {}, "error": "", "schema_version": -1, "content_checksum": ""}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result["error"] = "not_found"
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		result["error"] = "malformed"
		return result
	var envelope: Dictionary = parsed
	var version := int(envelope.get("schema_version", -1))
	result["schema_version"] = version
	if version > SCHEMA_VERSION:
		result["error"] = "downgrade_refused"
		return result
	var payload_json: Variant = envelope.get("payload_json", null)
	if typeof(payload_json) != TYPE_STRING:
		result["error"] = "malformed"
		return result
	if String(payload_json).md5_text() != String(envelope.get("checksum", "")):
		result["error"] = "checksum_mismatch"
		return result
	var payload: Variant = JSON.parse_string(String(payload_json))
	if typeof(payload) != TYPE_DICTIONARY:
		result["error"] = "malformed"
		return result
	result["ok"] = true
	result["payload"] = payload
	result["content_checksum"] = String(envelope.get("checksum", ""))
	return result


static func delete_save(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
