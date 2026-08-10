# 데스크탑 플랫폼 서비스 번들 — 어댑터 7종(D12 §2.2)의 데스크탑 구현을 일괄 제공.
# 코어는 인터페이스 타입으로만 접근한다 (혼입 0 — D12 §2.1).
class_name DesktopServices
extends RefCounted

var ad_service: IAdService = DesktopAdService.new()
var cloud_save: ICloudSave = DesktopCloudSave.new()
var achievement: IAchievement = DesktopAchievement.new()
var presence: IPresence = DesktopPresence.new()
var lifecycle: ILifecycle = DesktopLifecycle.new()
var haptics: IHaptics = DesktopHaptics.new()
var display: IDisplay = DesktopDisplay.new()
