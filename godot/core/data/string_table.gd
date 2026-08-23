# 스트링 테이블 (D12 §8.1 — 키 행 × 언어 열 CSV, 전 표시 문자열 = 키 참조).
# 변수 = 명명 플레이스홀더 {camelCase} (D12 §8.2).
class_name StringTable
extends RefCounted

const KEY_COLUMN := "key"

var _entries: Dictionary = {}
var _language: String = "ko"
var _languages: Array = []


func load_file(path: String, language: String = "ko") -> bool:
	_entries.clear()
	_languages.clear()
	var rows := CsvTable.load_rows(path)
	if rows.is_empty():
		push_error("StringTable: no rows in %s" % path)
		return false
	# 사용 가능한 언어 = 헤더의 `key` 열 밖 전부. **손으로 적은 목록을 두지 않는다** —
	# 목록과 표가 갈리면 "열은 있는데 고를 수 없는 언어" 또는 그 반대가 조용히 생긴다.
	# 순서는 헤더 순서다(선택 인덱스가 그 순서를 타므로 헤더 순서 자체가 계약이다).
	for column in Dictionary(rows[0]).keys():
		if String(column) != KEY_COLUMN:
			_languages.append(String(column))
	if not _languages.has(language):
		push_error("StringTable: unknown language column '%s' in %s" % [language, path])
		return false
	_language = language
	for row in rows:
		var key := String(row.get(KEY_COLUMN, ""))
		if key == "":
			continue
		_entries[key] = String(row.get(language, ""))
	return true


# 헤더에서 읽은 언어 코드 (헤더 순서 유지)
func languages() -> Array:
	return _languages.duplicate()


func language() -> String:
	return _language


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
