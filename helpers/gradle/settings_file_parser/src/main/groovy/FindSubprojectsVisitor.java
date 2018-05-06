import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.codehaus.groovy.ast.CodeVisitorSupport;
import org.codehaus.groovy.ast.expr.MethodCallExpression;
import org.codehaus.groovy.ast.expr.ArgumentListExpression;
import org.codehaus.groovy.ast.expr.Expression;

public class FindSubprojectsVisitor extends CodeVisitorSupport
{

    private List<String> subproject_paths = new ArrayList<>();

    @Override
    public void visitMethodCallExpression( MethodCallExpression call )
    {
        if( call.getMethodAsString().equals("include"))
        {
            super.visitMethodCallExpression(call);
        }
    }

    @Override
    public void visitArgumentlistExpression( ArgumentListExpression ale )
    {
        List<Expression> expressions = ale.getExpressions();

        for (Expression arg: expressions) {
            String subproject_path = arg.getText().replace(":", "/");
            subproject_paths.add(subproject_path);
        }

        super.visitArgumentlistExpression(ale);
    }

    public List<String> getSubprojectPaths()
    {
        return subproject_paths;
    }

}
