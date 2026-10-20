package com.goodhub.good_template

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 系统日历平台通道（P2-⑦）：生产通道（McpBinderService）同款注册，勿单方漏挂。
        SystemCalendarChannel.register(flutterEngine, applicationContext)
    }
}
