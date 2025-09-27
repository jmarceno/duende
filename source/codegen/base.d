module duende.codegen.base;

import duende.ast;

interface CodeGenerator {
    string generate(Program program);
    string generateStatement(Statement stmt);
    string generateExpression(Expression expr);
}