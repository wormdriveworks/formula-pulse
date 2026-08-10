# CSV 테이블 파서 (D12 §4.1 — 수치 테이블 = CSV/TSV · UTF-8 · NFC).
# 첫 행 = 헤더. 따옴표 필드·필드 내 콤마·이스케이프("") 지원.
class_name CsvTable
extends RefCounted


# 파일 → 행 배열 (각 행 = {헤더: 문자열 값}). 실패 시 빈 배열 + push_error.
static func load_rows(path: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CsvTable: cannot open %s" % path)
		return rows
	var text := file.get_as_text()
	file.close()
	var records := parse_records(text)
	if records.is_empty():
		return rows
	var header: Array = records[0]
	for i in range(1, records.size()):
		var record: Array = records[i]
		if record.size() == 1 and String(record[0]).strip_edges() == "":
			continue
		var row := {}
		for c in range(header.size()):
			row[header[c]] = record[c] if c < record.size() else ""
		rows.append(row)
	return rows


# CSV 원문 → 레코드 배열 (RFC 4180 기본형: 따옴표·이중 따옴표·개행 포함 필드)
static func parse_records(text: String) -> Array:
	var records: Array = []
	var field := ""
	var record: Array = []
	var in_quotes := false
	var i := 0
	var n := text.length()
	while i < n:
		var ch := text[i]
		if in_quotes:
			if ch == '"':
				if i + 1 < n and text[i + 1] == '"':
					field += '"'
					i += 1
				else:
					in_quotes = false
			else:
				field += ch
		else:
			match ch:
				'"':
					in_quotes = true
				',':
					record.append(field)
					field = ""
				'\r':
					pass
				'\n':
					record.append(field)
					field = ""
					records.append(record)
					record = []
				_:
					field += ch
		i += 1
	if field != "" or not record.is_empty():
		record.append(field)
		records.append(record)
	return records


static func to_float(value: String, default_value: float = 0.0) -> float:
	var s := value.strip_edges()
	if s == "":
		return default_value
	return s.to_float()


static func to_int(value: String, default_value: int = 0) -> int:
	var s := value.strip_edges()
	if s == "":
		return default_value
	return s.to_int()
