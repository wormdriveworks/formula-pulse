# 플랫폼 서비스 합성 지점 (D12 §2.2 어댑터 대장 7종 · §2.3 빌드 분리).
#
# **플랫폼 선택이 일어나는 유일한 자리다.** 코어(`godot/core/`)는 물론이고 화면 층
# (`godot/ui/`)도 구현체 이름을 알지 못한다 — 위에서는 전부 인터페이스 타입으로만 보인다.
# 그래서 혼입 0(불변규칙 1)이 "지키는 규약"이 아니라 "위반할 자리가 없는 구조"가 된다.
#
# 데스크탑 빌드에는 광고 모듈이 컴파일 자체로 들어오지 않는다(D12 §2.3 · IAdService = 널 구현).
# 모바일 레이어가 서면 여기에 피처 플래그 분기 1개가 늘고, 그 위층은 그대로다.
class_name PlatformServices
extends RefCounted

var ad_service: IAdService
var cloud_save: ICloudSave
var achievement: IAchievement
var presence: IPresence
var lifecycle: ILifecycle
var haptics: IHaptics
var display: IDisplay


# 현 빌드에 맞는 서비스 묶음. 모바일 레이어(`godot/platform/mobile/`)는 미결선이며,
# 유입 시 분기가 여기 한 곳에만 생긴다.
static func create() -> PlatformServices:
	var services := PlatformServices.new()
	var desktop := DesktopServices.new()
	services.ad_service = desktop.ad_service
	services.cloud_save = desktop.cloud_save
	services.achievement = desktop.achievement
	services.presence = desktop.presence
	services.lifecycle = desktop.lifecycle
	services.haptics = desktop.haptics
	services.display = desktop.display
	return services
