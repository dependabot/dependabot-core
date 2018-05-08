import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.List;

import org.apache.commons.io.IOUtils;
import org.codehaus.groovy.ast.ASTNode;
import org.codehaus.groovy.ast.GroovyCodeVisitor;
import org.codehaus.groovy.ast.builder.AstBuilder;
import org.codehaus.groovy.ast.InnerClassNode;
import org.codehaus.groovy.control.MultipleCompilationErrorsException;


public class GradlePropertyParser
{

    private List<ASTNode> nodes;
    private File file;

    public GradlePropertyParser( File inputfile ) throws MultipleCompilationErrorsException, IOException
    {
        this( IOUtils.toString( new FileInputStream( inputfile ), "UTF-8" ) );
        this.file = inputfile;
    }

    public GradlePropertyParser( String scriptContents ) throws MultipleCompilationErrorsException
    {
        AstBuilder builder = new AstBuilder();
        nodes = builder.buildFromString( scriptContents );
    }

    public List<GradleProperty> getAllProperties()
    {
        FindPropertiesVisitor visitor = new FindPropertiesVisitor();
        walkScript( visitor );

        return visitor.getProperties();
    }

    public void walkScript( GroovyCodeVisitor visitor )
    {
        for( ASTNode node : nodes )
        {
            if ( node instanceof InnerClassNode )
            {
                continue;
            }
            node.visit( visitor );
        }
    }

}
