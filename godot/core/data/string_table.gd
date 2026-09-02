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


# 한국어 어절 보존 (개선 회차 5 · 2026-09-03). TextServer(ICU)는 한글 음절 사이를 줄바꿈 기회로 보므로
# 자동 줄바꿈 라벨이 '대신 시/선이' 처럼 어절 중간에서 꺾인다 — `language="ko"` 도 `AUTOWRAP_WORD` 도
# 바꾸지 못한다(실측 7변형). 음절 사이에 WORD JOINER(U+2060 · 폭 0 · 무글리프 · UAX #14 LB11 양방향 금지)를
# 넣으면 띄어쓰기에서만 꺾인다. 문면 창구 한 곳에서 처리하므로 랩 라벨 전부가 수혜하고 비랩 라벨에는
# 보이지 않는다. 숫자·라틴과 붙은 음절('13번')도 한 어절로 묶는다. ko 열 한정 — ja 는 음절 단위 꺾임이 관례.
const WORD_JOINER := "\u2060"


# 키 → 문면. 미등재 키는 키 원문 반환 (디버그 가시화 — 크래시 없이 V2가 사전 차단 담당).
func text(key: String, params: Dictionary = {}) -> String:
	var raw: String = _entries.get(key, key)
	for param_name in params:
		raw = raw.replace("{%s}" % param_name, str(params[param_name]))
	if _language == "ko":
		return keep_korean_words(raw)
	return raw


# 어절 내부(한글–한글 · 한글–영숫자 · 영숫자–한글) 경계마다 WORD JOINER 를 끼운다.
# 문장 부호 앞은 UAX #14 가 이미 금지(× CL · × IS)하므로 만지지 않는다.
static func keep_korean_words(source: String) -> String:
	if source.length() < 2:
		return source
	var out := ""
	var prev_kind := 0   # 0 = 그 외 · 1 = 한글 음절 · 2 = 영숫자
	for i in range(source.length()):
		var code := source.unicode_at(i)
		var kind := 0
		if code >= 0xAC00 and code <= 0xD7A3:
			kind = 1
		elif (code >= 0x30 and code <= 0x39) or (code >= 0x41 and code <= 0x5A) \
				or (code >= 0x61 and code <= 0x7A):
			kind = 2
		if kind != 0 and prev_kind != 0 and (kind == 1 or prev_kind == 1):
			out += WORD_JOINER
		out += char(code)
		prev_kind = kind
	return out


func keys() -> Array:
	return _entries.keys()
