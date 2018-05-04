import java.io.File;
import java.util.List;
import groovy.json.JsonOutput

public class ParseDependencies
{
    static void main(String[] args) {
        def dirName = new String(args[0]);
        def inputFile = new File(dirName + "/build.gradle")
        def dependencyParser = new GradleDependencyParser(inputFile)
        def propertyParser = new GradlePropertyParser(inputFile)
        def repositoryParser = new GradleRepositoryParser(inputFile)
        def dependencies = dependencyParser.getAllDependencies()
        def properties = propertyParser.getAllProperties()
        def repositories = repositoryParser.getAllRepositories()

        def json_output = JsonOutput.toJson([dependencies: dependencies, properties: properties, repositories: repositories])
        def results_file = new File(dirName + "/result.json")

        results_file.write(json_output)
    }

}
