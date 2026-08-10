# 스트링 테이블 (D12 §8.1 — 키 행 × 언어 열 CSV, 전 표시 문자열 = 키 참조).
# 변수 = 명명 플레이스홀더 {camelCase} (D12 §8.2).
class_name StringTable
extends RefCounted

var _entries: Dictionary = {}
var _language: String = "ko"


func load_file(path: String, language: String = "ko") -> bool:
	_language = language
	_entries.clear()
	var rows := CsvTable.load_rows(path)
	if rows.is_empty():
		push_error("StringTable: no rows in %s" % path)
		return false
	for row in rows:
		var key := String(row.get("key", ""))
		if key == "":
			continue
		_entries[key] = String(row.get(language, ""))
	return true


func has_key(key: String) -> bool:
	return _entries.has(key)


# 키 → 문면. 미등재 키는 키 원문 반환 (디버그 가시화 — 크래시 없이 V2가 사전 차단 담당).
func text(key: String, params: Dictionary = {}) -> String:
	var raw: String = _entries.get(key, key)
	for param_name in params:
		raw = raw.replace("{%s}" % param_name, str(params[param_name]))
	return raw


func keys() -> Array:
	return _entries.keys()
