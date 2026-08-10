# RNG 시드 정책 (D12 §6 / 불변규칙 4) — 6스트림 분리, 마스터 시드 파생.
# 전 스트림 시드+내부 상태를 세이브에 직렬화 → 재로드 리롤 무효 (§6.2).
# reel 스트림 소비 시점 = 스핀 커밋(T2) — 소비는 RaceEngine이 수행.
class_name RngService
extends RefCounted

const STREAM_NAMES: Array[String] = ["reel", "shuffle", "resonance", "event", "ai", "reserve"]

var master_seed: int = 0
var _streams: Dictionary = {}


func setup(new_master_seed: int) -> void:
	master_seed = new_master_seed
	_streams.clear()
	for stream_name in STREAM_NAMES:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d:%s" % [new_master_seed, stream_name])
		_streams[stream_name] = rng


func stream(stream_name: String) -> RandomNumberGenerator:
	if not _streams.has(stream_name):
		push_error("RngService: undefined stream '%s'" % stream_name)
		return null
	return _streams[stream_name]


func randf(stream_name: String) -> float:
	return stream(stream_name).randf()


func randf_range(stream_name: String, from_value: float, to_value: float) -> float:
	return stream(stream_name).randf_range(from_value, to_value)


# 가중 추첨 — weights 합 기준 비례 선택, 반환 = 인덱스
func pick_weighted(stream_name: String, weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	var roll := stream(stream_name).randf() * total
	var acc := 0.0
	for i in range(weights.size()):
		acc += float(weights[i])
		if roll < acc:
			return i
	return weights.size() - 1


# 세이브 직렬화 (D12 §6.2 — 시드+내부 상태 전 스트림)
# 시드·상태는 64비트 정수 — JSON double 정밀도 손실 방지를 위해 문자열로 저장
func serialize() -> Dictionary:
	var data := {"master_seed": str(master_seed), "streams": {}}
	for stream_name in STREAM_NAMES:
		var rng: RandomNumberGenerator = _streams[stream_name]
		data["streams"][stream_name] = {"seed": str(rng.seed), "state": str(rng.state)}
	return data


func deserialize(data: Dictionary) -> bool:
	if not data.has("master_seed") or not data.has("streams"):
		push_error("RngService: malformed rng payload")
		return false
	master_seed = String(str(data["master_seed"])).to_int()
	_streams.clear()
	for stream_name in STREAM_NAMES:
		var stream_data: Dictionary = data["streams"].get(stream_name, {})
		if stream_data.is_empty():
			push_error("RngService: missing stream '%s' in payload" % stream_name)
			return false
		var rng := RandomNumberGenerator.new()
		rng.seed = String(str(stream_data["seed"])).to_int()
		rng.state = String(str(stream_data["state"])).to_int()
		_streams[stream_name] = rng
	return true
