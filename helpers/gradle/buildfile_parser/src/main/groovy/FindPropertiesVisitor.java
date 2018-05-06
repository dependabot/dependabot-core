import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.codehaus.groovy.ast.CodeVisitorSupport;;
import org.codehaus.groovy.ast.expr.MethodCallExpression;
import org.codehaus.groovy.ast.expr.BinaryExpression;


public class FindPropertiesVisitor extends CodeVisitorSupport
{
    private Boolean inExtBlock = new Boolean(false);
    private List<GradleProperty> properties = new ArrayList<>();

    @Override
    public void visitMethodCallExpression( MethodCallExpression call )
    {
        Boolean setInExtBlock = false;
        if( call.getMethodAsString().equals( "ext" ) && inExtBlock != true )
        {
            inExtBlock = true;
            setInExtBlock = true;
        }

        super.visitMethodCallExpression( call );

        if( setInExtBlock == true )
        {
            inExtBlock = false;
        }
    }

    @Override
    public void visitBinaryExpression( BinaryExpression expression )
    {
        if( inExtBlock == true || expression.getLeftExpression().getText().startsWith("ext"))
        {
            String name = expression.getLeftExpression().getText().replace("ext.", "");
            String value = expression.getRightExpression().getText();

            properties.add( new GradleProperty( name, value ) );
        }
    }

    public List<GradleProperty> getProperties()
    {
        return properties;
    }

}
