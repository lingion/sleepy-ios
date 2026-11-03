import SwiftUI

// SleepyMotion — 原版本 ui/component/SleepyMotion.kt → iOS 等价常量.
//
// 原版本 侧: SleepyThumbSpring = spring(dampingRatio=NoBouncy, stiffness=High)
// 官方 MotionScheme.expressive() 已是全局默认(MD3E), 但其空间类 spring 带回弹
// (MediumBouncy) — thumb 类「跟手不弹」交互是用户实测定参 (高硬度+无回弹,
// MediumLow 拖沓不跟手), 官方 motionScheme 无对应档位.
//
// iOS 等价: 线性参数 spring(response:) 的无回弹 = dampingFraction 1.0;
// "High stiffness + 不拖" = 短 response 0.18. 三处使用点共用同一常量 —
// 注释里的「同款」即指此常量; 改参数三处同步生效.
//
// 使用处 (原版本: SegmentedSwitcher thumb / PillNavigationBar 贴底+Dock thumb):
//   • SegmentedSwitcher.swift   (selectedIndex 跟随)
//   • PillNavigationBar.swift   ×2 (thumbCenterX 贴底 + Dock 药丸)
let sleepyThumbSpring = Animation.spring(response: 0.18, dampingFraction: 1.0)
