# 제한 조건 DSL (D12 §5.4·§5.12 확정: **필드 비교 · AND/OR 한정 · 스크립트 임베드 금지**).
# 데이터에 로직이 침투하는 것을 구조로 차단한다 — 표현식은 비교와 논리 결합만 담을 수 있다.
#
# 형태:
#   {"field": "player_rank", "op": "<=", "value": 3}
#   {"all": [<expr>, ...]}   {"any": [<expr>, ...]}   {"not": <expr>}
#
# 미지 필드·미지 연산자는 **거짓이 아니라 오류**다. false로 흘리면 조건이 조용히 성립하지 않고
# 변형이 영구히 발동하지 않는 상태가 데이터 오타 하나로 만들어진다.
class_name ConditionDsl
extends RefCounted

const OPERATORS := ["==", "!=", "<", "<=", ">", ">=", "in"]

var errors: Array = []


func is_ok() -> bool:
	return errors.is_empty()


# 빈 표현식({})은 "조건 없음 = 항상 성립"으로 읽는다 (변형 태그가 무조건 활성인 경우).
func evaluate(expression: Variant, context: Dictionary) -> bool:
	if typeof(expression) != TYPE_DICTIONARY:
		_error("expression is not an object: %s" % str(expression))
		return false
	var expr: Dictionary = expression
	if expr.is_empty():
		return true
	if expr.has("all"):
		return _evaluate_group(expr["all"], context, true)
	if expr.has("any"):
		return _evaluate_group(expr["any"], context, false)
	if expr.has("not"):
		return not evaluate(expr["not"], context)
	if expr.has("field"):
		return _evaluate_comparison(expr, context)
	_error("unknown expression shape: %s" % str(expr.keys()))
	return false


func _evaluate_group(items: Variant, context: Dictionary, require_all: bool) -> bool:
	if typeof(items) != TYPE_ARRAY:
		_error("all/any expects an array")
		return false
	var list: Array = items
	if list.is_empty():
		_error("all/any with empty array")
		return false
	for item in list:
		var result := evaluate(item, context)
		if require_all and not result:
			return false
		if not require_all and result:
			return true
	return require_all


func _evaluate_comparison(expr: Dictionary, context: Dictionary) -> bool:
	var field := String(expr["field"])
	if not context.has(field):
		_error("unknown field '%s' (context keys: %s)" % [field, str(context.keys())])
		return false
	var operator := String(expr.get("op", "=="))
	if not OPERATORS.has(operator):
		_error("unknown operator '%s'" % operator)
		return false
	var left: Variant = context[field]
	var right: Variant = expr.get("value", null)
	match operator:
		"==":
			return _equals(left, right)
		"!=":
			return not _equals(left, right)
		"in":
			if typeof(right) != TYPE_ARRAY:
				_error("'in' expects an array value")
				return false
			for candidate in Array(right):
				if _equals(left, candidate):
					return true
			return false
	# 순서 비교는 수치 전용 — 문자열 순서 비교는 로케일 의존이라 조건식에 두지 않는다.
	if not _is_number(left) or not _is_number(right):
		_error("operator '%s' needs numbers (got %s, %s)" % [operator, str(left), str(right)])
		return false
	var a := float(left)
	var b := float(right)
	match operator:
		"<":
			return a < b
		"<=":
			return a <= b
		">":
			return a > b
		">=":
			return a >= b
	return false


func _equals(left: Variant, right: Variant) -> bool:
	if _is_number(left) and _is_number(right):
		return absf(float(left) - float(right)) < 0.0001
	return String(left) == String(right)


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _error(message: String) -> void:
	errors.append(message)
	push_error("ConditionDsl: %s" % message)
