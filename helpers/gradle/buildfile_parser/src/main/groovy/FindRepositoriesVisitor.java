import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.codehaus.groovy.ast.CodeVisitorSupport;;
import org.codehaus.groovy.ast.expr.MethodCallExpression;
import org.codehaus.groovy.ast.expr.ArgumentListExpression;
import org.codehaus.groovy.ast.expr.Expression;
import org.codehaus.groovy.ast.stmt.ReturnStatement;


public class FindRepositoriesVisitor extends CodeVisitorSupport
{
    private Boolean inReposBlock = new Boolean(false);
    private Boolean inMavenBlock = new Boolean(false);
    private List<GradleRepository> repositories = new ArrayList<>();

    @Override
    public void visitMethodCallExpression( MethodCallExpression call )
    {
        Boolean setInReposBlock = false;
        if( call.getMethodAsString().equals( "repositories" ) && inReposBlock != true )
        {
            inReposBlock = true;
            setInReposBlock = true;
        }

        if( inReposBlock == true )
        {
            if ( call.getMethodAsString().equals("mavenCentral") )
            {
                repositories.add( new GradleRepository( "https://repo.maven.apache.org/maven2/" ) );
            }
            if( call.getMethodAsString().equals("google") )
            {
                repositories.add( new GradleRepository( "https://maven.google.com/" ) );
            }
            if( call.getMethodAsString().equals("jcenter") )
            {
                repositories.add( new GradleRepository( "https://jcenter.bintray.com/" ) );
            }
            if( inMavenBlock == true && call.getMethodAsString().equals("url") )
            {
                repositories.add( new GradleRepository( call.getArguments().getText().replaceAll("^\\(", "").replaceAll("\\)$", "") ) );
            }
            if( call.getMethodAsString().equals("maven") )
            {
                inMavenBlock = true;
                super.visitMethodCallExpression( call );
                inMavenBlock = false;
            }else {
                super.visitMethodCallExpression( call );
            }
        }else {
            super.visitMethodCallExpression( call );
        }

        if( setInReposBlock == true )
        {
            inReposBlock = false;
        }
    }

    public List<GradleRepository> getRepositories()
    {
        return repositories;
    }

}
