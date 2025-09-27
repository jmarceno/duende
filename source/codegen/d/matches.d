module duende.codegen.d.matches;

import duende.ast;
import std.array;
import std.string;
import std.format;

/**
 * Pattern matching and match expression/statement generation for D code.
 * This module handles match statements, match expressions, and all types
 * of patterns including wildcards, result patterns, and expression patterns.
 */
mixin template DMatchesMixin() {
    /**
     * Generate match statements.
     * These are statements that perform pattern matching with side effects.
     */
    private string generateMatchStatement(MatchStatement m) {
        auto buf = appender!string();
        string subj = format("__du_match_%s", ++matchCounter);
        buf ~= indent() ~ "auto " ~ subj ~ " = " ~ generateExpression(m.subject) ~ ";\n";
        bool first = true;
        foreach (c; m.cases) {
            string prelude;
            string cond = generatePatternCondition(subj, c.pattern, prelude);
            if (c.guard) {
                cond = "(" ~ cond ~ ") && (" ~ generateExpression(c.guard) ~ ")";
            }
            buf ~= indent() ~ (first ? "if (" : "else if (") ~ cond ~ ") {\n";
            indentLevel++;
            if (prelude.length > 0) {
                buf ~= indent() ~ prelude ~ "\n";
            }
            foreach (s; c.body) {
                // In match statement bodies, don't auto-wrap with duende_eval; emit raw expressions
                if (auto exprStmt = cast(ExpressionStatement)s) {
                    buf ~= indent() ~ generateExpression(exprStmt.expression) ~ ";\n";
                } else {
                    buf ~= generateStatement(s);
                }
            }
            indentLevel--;
            buf ~= indent() ~ "}\n";
            first = false;
        }
        return buf.data;
    }

    /**
     * Generate match expressions.
     * These are expressions that perform pattern matching and return values.
     */
    private string generateMatchExpression(MatchExpression m) {
        auto buf = appender!string();
        string subjExpr = generateExpression(m.subject);
        buf ~= "(() {\n";
        indentLevel++;
        string subj = format("__du_match_%s", ++matchCounter);
        buf ~= indent() ~ "auto " ~ subj ~ " = " ~ subjExpr ~ ";\n";
        bool first = true;
        foreach (c; m.cases) {
            string prelude;
            string cond = generatePatternCondition(subj, c.pattern, prelude);
            if (c.guard) {
                cond = "(" ~ cond ~ ") && (" ~ generateExpression(c.guard) ~ ")";
            }
            buf ~= indent() ~ (first ? "if (" : "else if (") ~ cond ~ ") {\n";
            indentLevel++;
            if (prelude.length > 0) {
                buf ~= indent() ~ prelude ~ "\n";
            }
            buf ~= indent() ~ "return " ~ generateExpression(c.value) ~ ";\n";
            indentLevel--;
            buf ~= indent() ~ "}\n";
            first = false;
        }
        // If none matched and no wildcard provided, make it unreachable (non-exhaustive match)
        buf ~= indent() ~ "assert(0);\n";
        indentLevel--;
        buf ~= indent() ~ "})()";
        return buf.data;
    }

    /**
     * Generate pattern matching conditions.
     * This handles all types of patterns and returns the D condition code.
     * 
     * Params:
     *   subj = The variable name containing the subject being matched
     *   pat = The pattern to match against
     *   prelude = Output parameter for any code that needs to run before the condition
     * 
     * Returns: D condition expression as a string
     */
    private string generatePatternCondition(string subj, Pattern pat, out string prelude) {
        prelude = "";
        
        if (cast(WildcardPattern)pat) {
            return "true";
        }
        
        if (auto okp = cast(ResultOkPattern)pat) {
            if (okp.bindName.length > 0) {
                prelude = "auto " ~ okp.bindName ~ " = " ~ subj ~ ".value;";
            }
            return subj ~ ".isOk";
        }
        
        if (auto errp = cast(ResultErrorPattern)pat) {
            if (errp.bindName.length > 0) {
                prelude = "auto " ~ errp.bindName ~ " = " ~ subj ~ ".errorMessage;";
            }
            return "!" ~ subj ~ ".isOk";
        }
        
        if (auto ep = cast(ExpressionPattern)pat) {
            // Special-case regex and enum-like constants
            if (auto rx = cast(RegexLiteralExpression)ep.expr) {
                string rex = generateRegexLiteral(rx);
                return "!matchFirst(" ~ subj ~ ", " ~ rex ~ ").empty";
            }
            
            if (auto call = cast(CallExpression)ep.expr) {
                // If pattern is a date-constructor-like expression, compare as dates
                if (isDateConstructorCall(call)) {
                    string rhs = generateCallExpression(call);
                    return subj ~ " == " ~ rhs;
                }
                if (call.name == "regex") {
                    string rex = generateCallExpression(call);
                    return "!matchFirst(" ~ subj ~ ", " ~ rex ~ ").empty";
                }
            }
            
            if (auto vexpr = cast(VariableExpression)ep.expr) {
                // Comparing against a date variable
                if (isDateVariable(vexpr.name)) {
                    return subj ~ " == " ~ vexpr.name;
                }
            }
            
            if (auto ve = cast(VariableExpression)ep.expr) {
                // Enum-like bare constant: ALLCAPS or CamelCaps?
                bool allCaps = true;
                foreach (dchar ch; ve.name) {
                    import std.uni : isAlphaNum;
                    if (ch == '_' || (ch >= '0' && ch <= '9')) continue;
                    if (ch >= 'A' && ch <= 'Z') continue;
                    allCaps = false; break;
                }
                if (allCaps && ve.name.length > 0 && ve.name != "_" && ve.name[0] >= 'A' && ve.name[0] <= 'Z') {
                    return subj ~ " == typeof(" ~ subj ~ ")." ~ ve.name;
                }
            }
            
            // Fallback to string equality to accommodate heterogeneous types used in examples
            requiredImports["std.conv"] = true;
            return "(" ~ subj ~ ").to!string == (" ~ generateExpression(ep.expr) ~ ").to!string";
        }
        
        // Default case
        return "false";
    }
}