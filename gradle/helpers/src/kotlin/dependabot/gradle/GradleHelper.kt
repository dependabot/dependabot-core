package dependabot.gradle

import org.gradle.tooling.GradleConnector
import java.io.File

object GradleHelper {
    fun listDependencies(projectDir: File): List<String> {
        val connector = GradleConnector.newConnector().forProjectDirectory(projectDir)
        connector.connect().use { connection ->
            val model = connection.getModel(org.gradle.tooling.model.idea.IdeaProject::class.java)
            return model.modules.flatMap { module ->
                module.dependencies.map { it.toString() }
            }
        }
    }
}
