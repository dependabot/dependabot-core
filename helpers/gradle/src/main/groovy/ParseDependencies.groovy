import java.io.File;
import java.util.List;
import groovy.json.JsonOutput

public class ParseDependencies
{
    static void main(String[] args) {
        def inputFile = new File( "target/build.gradle" )
        def parser = new GradleDependencyParser( inputFile )
        def allDependencies = parser.getAllDependencies()

        def json_output = JsonOutput.toJson([dependencies: allDependencies])
        def results_file = new File("target/output.json")

        results_file.write(json_output)
    }

}
