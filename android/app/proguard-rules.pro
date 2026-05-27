# 保留 FFmpegKit 的 Java/native 绑定。ffmpeg_kit_flutter_new 未正确向宿主工程暴露这些规则，
# release shrink 会移除部分 native 方法，导致插件注册阶段 JNI_OnLoad 失败。
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-dontwarn com.antonkarpenko.ffmpegkit.**

-keepclasseswithmembernames class * {
    native <methods>;
}
