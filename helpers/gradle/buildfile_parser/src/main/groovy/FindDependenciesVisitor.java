import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.codehaus.groovy.ast.CodeVisitorSupport;
import org.codehaus.groovy.ast.expr.ArgumentListExpression;
import org.codehaus.groovy.ast.expr.ClosureExpression;
import org.codehaus.groovy.ast.expr.Expression;
import org.codehaus.groovy.ast.expr.MapEntryExpression;
import org.codehaus.groovy.ast.expr.MapExpression;
import org.codehaus.groovy.ast.expr.ConstantExpression;
import org.codehaus.groovy.ast.expr.GStringExpression;

/**
 * @author Lovett Li
 */
public class FindDependenciesVisitor extends CodeVisitorSupport
{

    private List<GradleDependency> dependencies = new ArrayList<>();

    @Override
    public void visitArgumentlistExpression( ArgumentListExpression ale )
    {
        List<Expression> expressions = ale.getExpressions();

        if( expressions.size() == 1 || (expressions.size() == 2 && expressions.get( 1 ).getClass() == ClosureExpression.class ) )
        {
            if ( expressions.get( 0 ).getClass() == ConstantExpression.class || expressions.get( 0 ).getClass() == GStringExpression.class)
            {
                String depStr = expressions.get( 0 ).getText();
                String[] deps = depStr.split( ":" );

                if( deps.length == 3 )
                {
                    dependencies.add( new GradleDependency( deps[0], deps[1], deps[2] ) );
                }
            }
        }

        super.visitArgumentlistExpression( ale );
    }

    @Override
    public void visitMapExpression( MapExpression expression )
    {
        List<MapEntryExpression> mapEntryExpressions = expression.getMapEntryExpressions();
        Map<String, String> dependencyMap = new HashMap<String, String>();

        for( MapEntryExpression mapEntryExpression : mapEntryExpressions )
        {
            String key = mapEntryExpression.getKeyExpression().getText();
            String value = mapEntryExpression.getValueExpression().getText();
            dependencyMap.put( key, value );
        }

        if( dependencyMap.get( "name" ) != null )
        {
            dependencies.add( new GradleDependency( dependencyMap ) );
        }

        super.visitMapExpression( expression );
    }

    public List<GradleDependency> getDependencies()
    {
        return dependencies;
    }

}
