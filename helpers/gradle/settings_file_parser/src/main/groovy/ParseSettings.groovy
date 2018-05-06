import java.io.File;
import java.util.List;
import groovy.json.JsonOutput

public class ParseSettings
{
    static void main(String[] args) {
        def dirName = new String(args[0]);
        def inputFile = new File(dirName + "/settings.gradle")
        def settingsParser = new GradleSettingsParser(inputFile)
        def paths = settingsParser.getAllSubprojectPaths()

        def json_output = JsonOutput.toJson([subproject_paths: paths])
        def results_file = new File(dirName + "/result.json")

        results_file.write(json_output)
    }

}
