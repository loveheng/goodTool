allprojects {
    repositories {
        google()
        mavenCentral()
        // 插件接入契约 SDK（goodhub-mcp-sdk）：本机已 publishToMavenLocal 时走这里；
        // 免认证的离线分发件目录可用 -PmcpSdkDist=<dir> 覆盖
        // （默认取 sibling 仓的 dist/maven-repo，由 SDK 仓 scripts/dist.sh 产出）。
        mavenLocal()
        maven {
            val dist = findProperty("mcpSdkDist")?.toString()
                ?: rootProject.file("../../goodhub-mcp-sdk/dist/maven-repo").absolutePath
            url = uri(dist)
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
