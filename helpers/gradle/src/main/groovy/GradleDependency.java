import java.util.Map;

/**
 * @author Lovett Li
 */
public class GradleDependency
{

    private String group;
    private String name;
    private String version;

    public GradleDependency( Map<String, String> dep )
    {
        this.group = dep.get( "group" );
        this.name = dep.get( "name" );
        this.version = dep.get( "version" );
    }

    public GradleDependency( String group, String name, String version )
    {
        this.group = group;
        this.name = name;
        this.version = version;
    }

    public String getGroup()
    {
        return group;
    }

    public String getName()
    {
        return name;
    }

    public String getVersion()
    {
        return version;
    }

}
