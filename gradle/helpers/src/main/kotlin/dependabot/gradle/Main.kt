package dependabot.gradle

import kotlinx.serialization.*
import kotlinx.serialization.json.*
import java.io.File

@Serializable
data class Input(val function: String, val args: JsonElement)

@Serializable
data class Output<T>(val result: T? = null, val error: String? = null)

fun main() {
    val inputJson = generateSequence(::readLine).joinToString("\n")
    val input = Json.decodeFromString<Input>(inputJson)

    val output = when (input.function) {
        "list_dependencies" -> {
            val projectPath = input.args.jsonObject["projectDir"]?.jsonPrimitive?.content
            if (projectPath == null) {
                Output<List<String>>(error = "Missing required argument: projectDir")
            } else {
                try {
                    val deps = GradleHelper.listDependencies(File(projectPath))
                    Output(result = deps)
                } catch (e: Exception) {
                    Output<List<String>>(error = e.stackTraceToString())
                }
            }
        }
        else -> Output<List<String>>(error = "Unknown function: ${input.function}")
    }

    println(Json.encodeToString(output))
}
