package dependabot.gradle

import org.gradle.tooling.GradleConnector
import org.gradle.tooling.model.idea.IdeaProject
import java.io.File

object GradleHelper {

    /**
     * Lists all dependencies of a given Gradle project by loading its IdeaProject model.
     *
     * @param projectDir The root directory of the Gradle project.
     * @return A flat list of string representations of all dependencies from all modules.
     * @throws IllegalArgumentException If the provided directory does not exist or is not a directory.
     * @throws org.gradle.tooling.GradleConnectionException If there's an error during project connection or model fetching.
     */
    fun listDependencies(projectDir: File): List<String> {
        require(projectDir.exists() && projectDir.isDirectory) {
            "Provided path '${projectDir.absolutePath}' is not a valid project directory."
        }

        // Set up a GradleConnector for the given project directory
        val connector = GradleConnector.newConnector()
            .forProjectDirectory(projectDir)

        // Establish a connection and fetch the IdeaProject model
        connector.connect().use { connection ->
            val model: IdeaProject = connection.getModel(IdeaProject::class.java)

            // Flatten all module dependencies into a single list of strings
            return model.modules.flatMap { module ->
                module.dependencies.map { it.toString() }
            }
        }
    }
}
