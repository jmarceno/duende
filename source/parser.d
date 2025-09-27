module duende.parser;

import duende.lexer;
import duende.ast;
import std.range;
import std.conv;
import std.string;
import std.exception;

class ParseError : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

class Parser {
    private Token[] tokens;
    private size_t current;

    this(Token[] tokens) {
        this.tokens = tokens;
        this.current = 0;
    }

    Program parse() {
        Statement[] statements;

        while (!atEnd()) {
            consumeNewlines();
            if (!atEnd()) {
                statements ~= statement();
            }
        }

        return new Program(statements);
    }

    private Statement statement() {
        return statementWithContext(false); // false = not inside function/frame/struct
    }

    private Statement statementWithContext(bool isInLocalScope) {
        if (check(TokenType.IMPORT) || check(TokenType.PUBLIC) || check(TokenType.PRIVATE)) {
            return importDeclaration();
        }
        if (match(TokenType.LET, TokenType.VAR)) {
            return variableDeclarationWithContext(isInLocalScope);
        }
        if (check(TokenType.INT_TYPE, TokenType.FLOAT_TYPE, TokenType.STRING_TYPE,
                 TokenType.BOOL_TYPE, TokenType.BYTES_TYPE, TokenType.VOID_TYPE,
                 TokenType.LIST_TYPE, TokenType.DICT_TYPE, TokenType.AUTO_TYPE,
                 TokenType.RESULT, TokenType.MAYBE)) {
            return functionDeclaration();
        }
        if (match(TokenType.PROTOCOL)) {
            return protocolDeclaration();
        }
        if (match(TokenType.AT)) {
            return annotatedDeclaration();
        }
        if (match(TokenType.STRUCT)) {
            return structDeclaration();
        }
        if (match(TokenType.FRAME)) {
            return frameDeclaration();
        }
        if (match(TokenType.ENUM)) {
            return enumDeclaration();
        }
        if (match(TokenType.IF)) {
            return ifStatement(isInLocalScope);
        }
        if (match(TokenType.MATCH)) {
            return matchStatement(isInLocalScope);
        }
        if (match(TokenType.FOR)) {
            return forStatement(isInLocalScope);
        }
        if (match(TokenType.WHILE)) {
            return whileStatement(isInLocalScope);
        }
        if (match(TokenType.BREAK)) {
            auto stmt = new BreakStatement();
            // Set position from the BREAK token (previous() gives us the token we just consumed)
            auto token = previous();
            stmt.position = SourcePosition(token.line, token.column);
            return stmt;
        }
        if (match(TokenType.CONTINUE)) {
            auto stmt = new ContinueStatement();
            // Set position from the CONTINUE token
            auto token = previous();
            stmt.position = SourcePosition(token.line, token.column);
            return stmt;
        }
        if (match(TokenType.RETURN)) {
            return returnStatement(isInLocalScope);
        }
        if (match(TokenType.DEFER)) {
            return deferStatement(isInLocalScope);
        }

        return expressionStatement();
    }

    private Statement importDeclaration() {
        bool isPublic = false;
        if (match(TokenType.PUBLIC)) {
            isPublic = true;
            consume(TokenType.IMPORT, "Expected 'import' after 'public'");
        } else if (match(TokenType.PRIVATE)) {
            // explicit private
            consume(TokenType.IMPORT, "Expected 'import' after 'private'");
        } else {
            consume(TokenType.IMPORT, "Expected 'import'");
        }

        // Parse dotted module path like a.b.c
        string[] modulePath;
        consume(TokenType.IDENTIFIER, "Expected module name after import");
        modulePath ~= previous().value;
        // Consume additional dotted segments, but stop if we see a wildcard '.*'
        while (check(TokenType.DOT)) {
            // If the next token is '*' we are at a wildcard import (module.*),
            // so do not consume it as part of the module path; let the wildcard
            // branch handle it below.
            if (current + 1 < tokens.length && tokens[current + 1].type == TokenType.MULTIPLY) {
                break;
            }
            // Otherwise this must be a regular dotted identifier segment
            advance(); // consume '.'
            consume(TokenType.IDENTIFIER, "Expected identifier after '.' in module path");
            modulePath ~= previous().value;
        }

        // Optional alias: 'as Name'
        string moduleAlias;
        if (match(TokenType.AS)) {
            consume(TokenType.IDENTIFIER, "Expected alias name after 'as'");
            moduleAlias = previous().value;
        }

        bool isWildcard = false;
        ImportItemSpec[] items;
        // Optional selective list: { a, b as c }
        if (match(TokenType.LEFT_BRACE)) {
            if (!check(TokenType.RIGHT_BRACE)) {
                do {
                    consume(TokenType.IDENTIFIER, "Expected symbol name in import list");
                    string itemName = previous().value;
                    string itemAlias;
                    if (match(TokenType.AS)) {
                        consume(TokenType.IDENTIFIER, "Expected alias name after 'as'");
                        itemAlias = previous().value;
                    }
                    items ~= ImportItemSpec(itemName, itemAlias);
                } while (match(TokenType.COMMA));
            }
            consume(TokenType.RIGHT_BRACE, "Expected '}' after import list");
        } else if (match(TokenType.DOT)) {
            // wildcard: module.*
            consume(TokenType.MULTIPLY, "Expected '*' for wildcard import");
            isWildcard = true;
        }

        // Consume trailing newlines to keep parser consistent
        consumeNewlines();
        return new ImportDeclaration(modulePath, moduleAlias, isPublic, isWildcard, items);
    }

    private Statement variableDeclaration() {
        return variableDeclarationWithContext(true); // Default to local scope for backward compatibility
    }

    private Statement variableDeclarationWithContext(bool isInLocalScope) {
        bool isMutable = previous().type == TokenType.VAR;

    string customTypeName;
    DuendeType innerType;
    string innerCustomTypeName;
    DuendeType type = parseType(customTypeName, innerType, innerCustomTypeName);
        consume(TokenType.IDENTIFIER, "Expected variable name");
        string name = previous().value;

        consume(TokenType.ASSIGN, "Expected '=' in variable declaration");
        Expression initializer = expression();
        // Semantic check: lists must always be typed (list<T>); disallow bare 'list'
        if (type == DuendeType.LIST) {
            bool noInnerSpecified = (innerType == DuendeType.VOID) &&
                                    (!(innerCustomTypeName !is null && innerCustomTypeName.length)) &&
                                    (!(customTypeName !is null && customTypeName.length));
            if (noInnerSpecified) {
                throw new ParseError("Lists must be typed: use list<T>");
            }
        }

    return new VariableDeclaration(name, type, initializer, isMutable, customTypeName, innerType, innerCustomTypeName, !isInLocalScope);
    }

    private Statement functionDeclaration() {
    string customTypeName;
    DuendeType returnInnerType;
    string returnInnerCustomTypeName;
    DuendeType returnType = parseType(customTypeName, returnInnerType, returnInnerCustomTypeName);
        consume(TokenType.IDENTIFIER, "Expected function name");
        string name = previous().value;

        consume(TokenType.LEFT_PAREN, "Expected '(' after function name");
        Parameter[] parameters;

        if (!check(TokenType.RIGHT_PAREN)) {
            do {
                string paramCustomTypeName;
                DuendeType paramInnerType;
                string paramInnerCustomTypeName;
                DuendeType paramType = parseType(paramCustomTypeName, paramInnerType, paramInnerCustomTypeName);
                bool isNamed = false;
                // Enforce 'type name' only; ':' is not allowed in parameter declarations
                if (check(TokenType.COLON)) {
                    throw new ParseError(": is not allowed in parameter declarations; use 'type name'");
                }

                consume(TokenType.IDENTIFIER, "Expected parameter name");
                string paramName = previous().value;
                // Optional default value: '= expr'
                Expression defVal = null;
                if (match(TokenType.ASSIGN)) {
                    defVal = expression();
                }
                parameters ~= Parameter(paramName, paramType, paramCustomTypeName, paramInnerType, isNamed, defVal);
            } while (match(TokenType.COMMA));
        }

        consume(TokenType.RIGHT_PAREN, "Expected ')' after parameters");
        consume(TokenType.DO, "Expected 'do' after function signature");

        Statement[] body;
        consumeNewlines();

        while (!check(TokenType.END) && !atEnd()) {
            body ~= statementWithContext(true); // Inside function - local scope
            consumeNewlines();
        }

        consume(TokenType.END, "Expected 'end' after function body");

    return new FunctionDeclaration(name, returnType, parameters, body, returnInnerType, returnInnerCustomTypeName);
    }

    private Statement ifStatement() {
        return ifStatement(true); // Default to local scope for backward compatibility
    }

    private Statement ifStatement(bool isInLocalScope) {
        Expression condition = expression();
        consume(TokenType.DO, "Expected 'do' after if condition");

        Statement[] thenBranch;
        consumeNewlines();

        while (!check(TokenType.ELIF) && !check(TokenType.ELSE) && !check(TokenType.END) && !atEnd()) {
            thenBranch ~= statementWithContext(isInLocalScope);
            consumeNewlines();
        }

        // Parse elif clauses
        ElifClause[] elifClauses;
        while (match(TokenType.ELIF)) {
            Expression elifCondition = expression();
            consume(TokenType.DO, "Expected 'do' after elif condition");
            
            Statement[] elifBody;
            consumeNewlines();
            
            while (!check(TokenType.ELIF) && !check(TokenType.ELSE) && !check(TokenType.END) && !atEnd()) {
                elifBody ~= statementWithContext(isInLocalScope);
                consumeNewlines();
            }
            
            elifClauses ~= ElifClause(elifCondition, elifBody);
        }

        Statement[] elseBranch;
        if (match(TokenType.ELSE)) {
            consumeNewlines();
            while (!check(TokenType.END) && !atEnd()) {
                elseBranch ~= statementWithContext(isInLocalScope);
                consumeNewlines();
            }
        }

        consume(TokenType.END, "Expected 'end' after if statement");

        return new IfStatement(condition, thenBranch, elifClauses, elseBranch);
    }

    private Statement forStatement() {
        return forStatement(true); // Default to local scope for backward compatibility
    }

    private Statement forStatement(bool isInLocalScope) {
        consume(TokenType.IDENTIFIER, "Expected variable name in for loop");
        string variable = previous().value;

        consume(TokenType.IN, "Expected 'in' in for loop");
        Expression expr = expression();

        if (match(TokenType.RANGE)) {
            Expression end = expression();
            consume(TokenType.DO, "Expected 'do' after for range");

            Statement[] body;
            consumeNewlines();

            while (!check(TokenType.END) && !atEnd()) {
                body ~= statementWithContext(isInLocalScope);
                consumeNewlines();
            }

            consume(TokenType.END, "Expected 'end' after for body");

            return new ForStatement(variable, expr, end, body);
        } else {
            consume(TokenType.DO, "Expected 'do' after for iterable");

            Statement[] body;
            consumeNewlines();

            while (!check(TokenType.END) && !atEnd()) {
                body ~= statementWithContext(isInLocalScope);
                consumeNewlines();
            }

            consume(TokenType.END, "Expected 'end' after for body");

            return new ForInStatement(variable, expr, body);
        }
    }

    private Statement whileStatement() {
        return whileStatement(true); // Default to local scope for backward compatibility
    }

    private Statement whileStatement(bool isInLocalScope) {
        Expression condition = expression();
        consume(TokenType.DO, "Expected 'do' after while condition");

        Statement[] body;
        consumeNewlines();

        while (!check(TokenType.END) && !atEnd()) {
            body ~= statementWithContext(isInLocalScope);
            consumeNewlines();
        }

        consume(TokenType.END, "Expected 'end' after while body");

        return new WhileStatement(condition, body);
    }

    private Statement returnStatement() {
        return returnStatement(true); // Default to local scope for backward compatibility
    }

    private Statement returnStatement(bool isInLocalScope) {
        Expression value = null;
        if (!check(TokenType.NEWLINE) && !atEnd()) {
            value = expression();
        }
        return new ReturnStatement(value);
    }

    private Statement deferStatement() {
        return deferStatement(true); // Default to local scope for backward compatibility
    }

    private Statement deferStatement(bool isInLocalScope) {
        Expression call = expression();
        return new DeferStatement(call);
    }

    private Statement expressionStatement() {
        Expression expr = expression();
        // If expression starts with 'match', it could be a MatchExpression already from primary
        return new ExpressionStatement(expr);
    }

    private Expression expression() {
        return assignment();
    }

    private Expression assignment() {
        Expression expr = unwrap();

        if (match(TokenType.ASSIGN)) {
            Expression value = assignment();
            if (auto var = cast(VariableExpression)expr) {
                return new AssignmentExpression(var.name, value);
            } else if (auto prop = cast(PropertyExpression)expr) {
                return new PropertyAssignmentExpression(prop.object, prop.property, value);
            }
            throw new ParseError("Invalid assignment target");
        }

        return expr;
    }

    private Expression unwrap() {
        Expression expr = logicalOr();

        if (match(TokenType.QUESTION)) {
            consume(TokenType.ELSE, "Expected 'else' after '?' in unwrap expression");
            Expression defaultValue = logicalOr();
            return new UnwrapExpression(expr, defaultValue);
        }

        return expr;
    }

    private Expression logicalOr() {
        Expression expr = logicalAnd();

        while (match(TokenType.LOGICAL_OR)) {
            string operator = previous().value;
            Expression right = logicalAnd();
            expr = new BinaryExpression(expr, operator, right);
        }

        return expr;
    }

    private Expression logicalAnd() {
        Expression expr = equality();

        while (match(TokenType.LOGICAL_AND)) {
            string operator = previous().value;
            Expression right = equality();
            expr = new BinaryExpression(expr, operator, right);
        }

        return expr;
    }

    private Expression equality() {
        Expression expr = comparison();

        while (match(TokenType.EQUAL, TokenType.NOT_EQUAL)) {
            string operator = previous().value;
            Expression right = comparison();
            expr = new BinaryExpression(expr, operator, right);
        }

        return expr;
    }

    private Expression comparison() {
        Expression expr = term();

        while (match(TokenType.GREATER, TokenType.GREATER_EQUAL, TokenType.LESS, TokenType.LESS_EQUAL)) {
            string operator = previous().value;
            Expression right = term();
            expr = new BinaryExpression(expr, operator, right);
        }

        return expr;
    }

    private Expression term() {
        Expression expr = factor();

        while (match(TokenType.MINUS, TokenType.PLUS)) {
            string operator = previous().value;
            Expression right = factor();
            expr = new BinaryExpression(expr, operator, right);
        }

        return expr;
    }

    private Expression factor() {
        Expression expr = unary();

        while (match(TokenType.DIVIDE, TokenType.MULTIPLY, TokenType.MODULO)) {
            string operator = previous().value;
            Expression right = unary();
            expr = new BinaryExpression(expr, operator, right);
        }

        return expr;
    }

    private Expression unary() {
        if (match(TokenType.LOGICAL_NOT, TokenType.MINUS)) {
            string operator = previous().value;
            Expression right = unary();
            return new UnaryExpression(operator, right);
        }

        return postfix();
    }

    private Expression postfix() {
        Expression expr = primary();

        while (true) {
            if (match(TokenType.LEFT_BRACKET)) {
                // Support index and slice syntax: obj[expr] or obj[start:end]
                Expression first = expression();
                if (match(TokenType.COLON)) {
                    Expression second = expression();
                    consume(TokenType.RIGHT_BRACKET, "Expected ']' after slice");
                    expr = new MethodCallExpression(expr, "slice", [ first, second ]);
                } else {
                    consume(TokenType.RIGHT_BRACKET, "Expected ']' after array index");
                    expr = new IndexExpression(expr, first);
                }
            } else if (match(TokenType.DOT)) {
                consume(TokenType.IDENTIFIER, "Expected property name after '.'");
                string property = previous().value;

                // Check if this is a method call (has parentheses after)
                if (check(TokenType.LEFT_PAREN)) {
                    consume(TokenType.LEFT_PAREN, "Expected '(' for method call");
                    Expression[] arguments;
                    string[] argNames;
                    if (!check(TokenType.RIGHT_PAREN)) {
                        do {
                            // Support named args: name: expr
                            if (check(TokenType.IDENTIFIER) && current + 1 < tokens.length && tokens[current + 1].type == TokenType.COLON) {
                                // Lookahead but don't consume identifier yet; we need to keep position for expression parse if mispredicted
                                consume(TokenType.IDENTIFIER, "Expected argument name before ':'");
                                string an = previous().value;
                                consume(TokenType.COLON, "Expected ':' after argument name");
                                auto ex = expression();
                                argNames ~= an;
                                arguments ~= ex;
                            } else {
                                argNames ~= "";
                                arguments ~= expression();
                            }
                        } while (match(TokenType.COMMA));
                    }
                    consume(TokenType.RIGHT_PAREN, "Expected ')' after method arguments");
                    expr = new MethodCallExpression(expr, property, arguments, argNames);
                } else {
                    // It's a property access
                    expr = new PropertyExpression(expr, property);
                }
            } else if (match(TokenType.LEFT_PAREN)) {
                Expression[] arguments;
                string[] argNames;
                if (!check(TokenType.RIGHT_PAREN)) {
                    do {
                        if (check(TokenType.IDENTIFIER) && current + 1 < tokens.length && tokens[current + 1].type == TokenType.COLON) {
                            consume(TokenType.IDENTIFIER, "Expected argument name before ':'");
                            string an = previous().value;
                            consume(TokenType.COLON, "Expected ':' after argument name");
                            auto ex = expression();
                            argNames ~= an;
                            arguments ~= ex;
                        } else {
                            argNames ~= "";
                            arguments ~= expression();
                        }
                    } while (match(TokenType.COMMA));
                }
                consume(TokenType.RIGHT_PAREN, "Expected ')' after arguments");

                if (auto var = cast(VariableExpression)expr) {
                    // Check if this could be a constructor call (capitalized name)
                    if (var.name.length > 0 && var.name[0] >= 'A' && var.name[0] <= 'Z') {
                        expr = new ConstructorCallExpression(var.name, arguments, argNames);
                    } else {
                        expr = new CallExpression(var.name, arguments, argNames);
                    }
                } else {
                    throw new ParseError("Invalid function call");
                }
            } else {
                break;
            }
        }

        return expr;
    }

    private Expression primary() {
        if (match(TokenType.MATCH)) {
            return matchExpression();
        }
        if (match(TokenType.INTEGER)) {
            int value = to!int(previous().value);
            return new LiteralExpression(value);
        }

        if (match(TokenType.FLOAT)) {
            double value = to!double(previous().value);
            return new LiteralExpression(value);
        }

        if (match(TokenType.BOOLEAN)) {
            bool value = previous().value == "true";
            return new LiteralExpression(value);
        }

        if (match(TokenType.STRING)) {
            return parseStringWithInterpolation(previous().value);
        }

        if (match(TokenType.BYTES)) {
            // Convert bytes literal content (string of chars) into int[] of byte values
            string s = previous().value;
            int[] vals;
            foreach (dchar ch; s) {
                int v = cast(int)ch;
                if (v < 0) v = 0; if (v > 255) v = v & 0xFF;
                vals ~= v;
            }
            return new BytesLiteralExpression(vals);
        }

        if (match(TokenType.LEFT_BRACKET)) {
            Expression[] elements;
            if (!check(TokenType.RIGHT_BRACKET)) {
                do {
                    elements ~= expression();
                } while (match(TokenType.COMMA));
            }
            consume(TokenType.RIGHT_BRACKET, "Expected ']' after list literal");
            return new ListLiteralExpression(elements);
        }

        if (match(TokenType.LEFT_BRACE)) {
            // Check if this is a lambda or dictionary
            size_t savedPos = current;
            bool isLambda = false;

            // Look ahead to see if we have lambda syntax (parameters -> body)
            if (!check(TokenType.RIGHT_BRACE)) {
                // Skip any identifiers that could be parameters
                while (check(TokenType.IDENTIFIER)) {
                    advance();
                    if (match(TokenType.COMMA)) {
                        continue;
                    } else {
                        break;
                    }
                }

                // Check if we found an arrow
                if (check(TokenType.ARROW)) {
                    isLambda = true;
                }
            }

            // Reset to saved position
            current = savedPos;

            if (isLambda) {
                return parseLambda();
            } else {
                // Parse as dictionary
                Expression[] keys;
                Expression[] values;
                if (!check(TokenType.RIGHT_BRACE)) {
                    do {
                        Expression key = expression();
                        consume(TokenType.COLON, "Expected ':' after dictionary key");
                        Expression value = expression();
                        keys ~= key;
                        values ~= value;
                    } while (match(TokenType.COMMA));
                }
                consume(TokenType.RIGHT_BRACE, "Expected '}' after dict literal");
                return new DictLiteralExpression(keys, values);
            }
        }

        if (match(TokenType.THIS)) {
            return new VariableExpression("this");
        }

        // Handle error handling constructors
        if (match(TokenType.OK)) {
            consume(TokenType.LEFT_PAREN, "Expected '(' after Ok");
            Expression value = expression();
            consume(TokenType.RIGHT_PAREN, "Expected ')' after Ok value");
            return new ResultConstructorExpression(true, value);
        }

        if (match(TokenType.ERROR)) {
            consume(TokenType.LEFT_PAREN, "Expected '(' after Error");
            Expression value = expression();
            consume(TokenType.RIGHT_PAREN, "Expected ')' after Error value");
            return new ResultConstructorExpression(false, value);
        }

        if (match(TokenType.SOME)) {
            consume(TokenType.LEFT_PAREN, "Expected '(' after Some");
            Expression value = expression();
            consume(TokenType.RIGHT_PAREN, "Expected ')' after Some value");
            return new MaybeConstructorExpression(true, value);
        }

        if (match(TokenType.NONE)) {
            return new MaybeConstructorExpression(false, null);
        }

        if (match(TokenType.TRY)) {
            consume(TokenType.DO, "Expected 'do' after try");
            Statement[] statements;
            consumeNewlines();

            while (!check(TokenType.END) && !atEnd()) {
                statements ~= statement();
                consumeNewlines();
            }

            consume(TokenType.END, "Expected 'end' after try block");
            return new TryBlockExpression(statements);
        }

        if (match(TokenType.PANIC)) {
            consume(TokenType.LEFT_PAREN, "Expected '(' after panic");
            Expression message = expression();
            consume(TokenType.RIGHT_PAREN, "Expected ')' after panic message");
            return new PanicExpression(message);
        }

        // Support type literal expressions (for APIs like safeCast(int, x))
        if (check(TokenType.INT_TYPE) || check(TokenType.FLOAT_TYPE) || check(TokenType.STRING_TYPE) || check(TokenType.BOOL_TYPE) || check(TokenType.BYTES_TYPE)) {
            auto tyTok = advance();
            DuendeType t;
            switch (tyTok.type) {
                case TokenType.INT_TYPE: t = DuendeType.INT; break;
                case TokenType.FLOAT_TYPE: t = DuendeType.FLOAT; break;
                case TokenType.STRING_TYPE: t = DuendeType.STRING; break;
                case TokenType.BOOL_TYPE: t = DuendeType.BOOL; break;
                case TokenType.BYTES_TYPE: t = DuendeType.BYTES; break;
                default: t = DuendeType.AUTO; break;
            }
            // If followed by '(', this may be a cast; otherwise treat as a type literal value
            if (!check(TokenType.LEFT_PAREN)) {
                return new TypeLiteralExpression(t);
            }
            // Else, continue to cast path below
            current--; // rewind so the cast branch consumes token appropriately
        }

        // Support type-cast syntax when lexer classifies type names as keywords
        // e.g., int(expr), float(expr), string(expr)
        if ((check(TokenType.INT_TYPE) || check(TokenType.FLOAT_TYPE) || check(TokenType.STRING_TYPE))
            && current + 1 < tokens.length && tokens[current + 1].type == TokenType.LEFT_PAREN) {
            auto tyTok = advance(); // consume type token
            consume(TokenType.LEFT_PAREN, "Expected '(' after type name in cast");
            Expression inner = expression();
            consume(TokenType.RIGHT_PAREN, "Expected ')' after cast expression");
            DuendeType target;
            switch (tyTok.type) {
                case TokenType.INT_TYPE:   target = DuendeType.INT; break;
                case TokenType.FLOAT_TYPE: target = DuendeType.FLOAT; break;
                case TokenType.STRING_TYPE: target = DuendeType.STRING; break;
                default: throw new ParseError("Invalid cast target");
            }
            return new CastExpression(target, inner);
        }

        if (match(TokenType.IDENTIFIER)) {
            string name = previous().value;
            // Type cast syntax: int(expr), float(expr), string(expr)
            if ((name == "int" || name == "float" || name == "string") && check(TokenType.LEFT_PAREN)) {
                // Parse cast: name '(' expr ')'
                advance(); // consume '('
                Expression inner = expression();
                consume(TokenType.RIGHT_PAREN, "Expected ')' after cast expression");
                DuendeType target = (name == "int") ? DuendeType.INT : (name == "float" ? DuendeType.FLOAT : DuendeType.STRING);
                return new CastExpression(target, inner);
            }
            // Check if this is a regex function call
            if (name == "regex" && check(TokenType.LEFT_PAREN)) {
                consume(TokenType.LEFT_PAREN, "Expected '(' after regex");
                consume(TokenType.STRING, "Expected string literal for regex pattern");
                string pattern = previous().value;
                consume(TokenType.RIGHT_PAREN, "Expected ')' after regex pattern");
                return new RegexLiteralExpression(pattern);
            }
            // Check if this might be a constructor call
            if (check(TokenType.LEFT_PAREN)) {
                return new VariableExpression(name); // Will be handled by postfix
            }
            return new VariableExpression(name);
        }

        if (match(TokenType.LEFT_PAREN)) {
            Expression expr = expression();
            consume(TokenType.RIGHT_PAREN, "Expected ')' after expression");
            return expr;
        }

        throw new ParseError("Unexpected token: " ~ peek().value);
    }

    private Statement matchStatement() {
        return matchStatement(true); // Default to local scope for backward compatibility
    }

    private Statement matchStatement(bool isInLocalScope) {
        // already consumed 'match'
        Expression subject = expression();
        consume(TokenType.DO, "Expected 'do' after match subject");
        consumeNewlines();

        MatchStmtCase[] cases;
        while (!check(TokenType.END) && !atEnd()) {
            auto pat = parsePattern();
            Expression guard = null;
            if (match(TokenType.IF)) {
                guard = expression();
            }
            consume(TokenType.ARROW, "Expected '->' after match pattern");
            // Parse a single statement (supports 'return', assignment, function call, etc.)
            Statement one = statementForMatchArm(isInLocalScope);
            Statement[] body = [ one ];
            consumeNewlines();
            cases ~= new MatchStmtCase(pat, guard, body);
        }

        consume(TokenType.END, "Expected 'end' after match statement");
        return new MatchStatement(subject, cases);
    }

    private Statement statementForMatchArm() {
        return statementForMatchArm(true); // Default to local scope for backward compatibility
    }

    private Statement statementForMatchArm(bool isInLocalScope) {
        // Minimal single-statement parser for use after '->' in match arms
        if (match(TokenType.BREAK)) {
            auto stmt = new BreakStatement();
            auto token = previous();
            stmt.position = SourcePosition(token.line, token.column);
            return stmt;
        }
        if (match(TokenType.CONTINUE)) {
            auto stmt = new ContinueStatement();
            auto token = previous();
            stmt.position = SourcePosition(token.line, token.column);
            return stmt;
        }
        if (match(TokenType.RETURN)) {
            // reuse returnStatement but we already consumed RETURN, so craft it here
            Expression value = null;
            if (!check(TokenType.NEWLINE) && !check(TokenType.END)) {
                value = expression();
            }
            return new ReturnStatement(value);
        }
        // Fallback: parse an expression and wrap as statement
        Expression expr = expression();
        return new ExpressionStatement(expr);
    }

    private Expression matchExpression() {
        // already consumed 'match'
        Expression subject = expression();
        consume(TokenType.DO, "Expected 'do' after match subject");
        consumeNewlines();

        MatchExprCase[] cases;
        while (!check(TokenType.END) && !atEnd()) {
            auto pat = parsePattern();
            Expression guard = null;
            if (match(TokenType.IF)) {
                guard = expression();
            }
            consume(TokenType.ARROW, "Expected '->' after match pattern");
            Expression value = expression();
            consumeNewlines();
            cases ~= new MatchExprCase(pat, guard, value);
        }

        consume(TokenType.END, "Expected 'end' after match expression");
        return new MatchExpression(subject, cases);
    }

    private Pattern parsePattern() {
        // Wildcard '_'
        if (check(TokenType.IDENTIFIER) && peek().value == "_") {
            advance();
            return new WildcardPattern();
        }

        // Ok(x) / Error(msg) destructuring pattern for Result
        if (check(TokenType.OK) || check(TokenType.ERROR)) {
            bool isOk = check(TokenType.OK);
            advance(); // consume Ok or Error
            consume(TokenType.LEFT_PAREN, "Expected '(' after Ok/Error in pattern");
            string bindName = "";
            if (check(TokenType.IDENTIFIER)) {
                consume(TokenType.IDENTIFIER, "Expected identifier inside Ok/Error pattern");
                bindName = previous().value;
            }
            consume(TokenType.RIGHT_PAREN, "Expected ')' after Ok/Error pattern");
            if (isOk) return new ResultOkPattern(bindName);
            else return new ResultErrorPattern(bindName);
        }

        // Otherwise, parse an expression pattern (literal, identifier, call like regex("..."), property/index)
        Expression lhs = assignment(); // allow full expression on LHS like numbers[0]
        return new ExpressionPattern(lhs);
    }

    private Expression parseLambda() {
        string[] parameters;

        // Parse parameters
        if (!check(TokenType.RIGHT_BRACE)) {
            do {
                consume(TokenType.IDENTIFIER, "Expected parameter name in lambda");
                parameters ~= previous().value;
            } while (match(TokenType.COMMA));
        }

        consume(TokenType.ARROW, "Expected '->' in lambda expression");
        Expression body = expression();
        consume(TokenType.RIGHT_BRACE, "Expected '}' after lambda body");

        return new LambdaExpression(parameters, body);
    }

    private Expression parseStringWithInterpolation(string str) {
        // ESC_INTERP sentinel inserted by lexer to mark escaped interpolation tokens
        enum dchar ESC_INTERP = cast(dchar)0x1D; // Group Separator

        // Quick path: if no interpolation marker present (considering sentinel-protected), return literal
        if (str.indexOf("${") == -1) {
            // Remove interpolation escape sentinels from plain strings
            auto buf = appender!string();
            foreach (dchar ch; str) {
                if (ch == ESC_INTERP) continue;
                buf ~= ch;
            }
            return new LiteralExpression(buf.data);
        }

        string[] parts;
        Expression[] expressions;
        string[] formats;
        string buffer = "";
        size_t i = 0;

        while (i < str.length) {
            // If we see ESC_INTERP followed by '{' or '}', treat both as literal characters
            if (str[i] == ESC_INTERP) {
                if (i + 1 < str.length && (str[i + 1] == '{' || str[i + 1] == '}')) {
                    buffer ~= str[i + 1];
                    i += 2;
                    continue;
                }
                // Otherwise, keep it as-is (should not normally occur)
                i++;
                continue;
            }

            if (i + 1 < str.length && str[i] == '$' && str[i + 1] == '{') {
                parts ~= buffer;
                buffer = "";
                i += 2;

                string exprStr = "";
                string fmtStr = null;
                int braceCount = 1;
                while (i < str.length && braceCount > 0) {
                    if (str[i] == ESC_INTERP) {
                        // literal next char
                        if (i + 1 < str.length) {
                            if (braceCount > 0) exprStr ~= str[i + 1];
                            i += 2;
                            continue;
                        } else { i++; continue; }
                    }
                    if (str[i] == '{') {
                        braceCount++;
                        if (braceCount > 0) exprStr ~= str[i];
                        i++;
                        continue;
                    } else if (str[i] == '}') {
                        braceCount--;
                        if (braceCount > 0) {
                            exprStr ~= str[i];
                        }
                        i++;
                        continue;
                    }
                    // Allow optional format separator: '|' not nested inside braces
                    if (braceCount == 1 && str[i] == '|') {
                        // Collect format starting after '|', up to closing '}'
                        i++; // skip '|'
                        auto fmtStart = i;
                        while (i < str.length && str[i] != '}') {
                            fmtStr ~= str[i];
                            i++;
                        }
                        // The loop will consume '}' on next iteration
                        continue;
                    }
                    if (braceCount > 0) {
                        exprStr ~= str[i];
                    }
                    i++;
                }

                auto lexer = new Lexer(exprStr);
                auto tokens = lexer.tokenize();
                auto parser = new Parser(tokens);
                expressions ~= parser.expression();
                formats ~= fmtStr;
            } else {
                buffer ~= str[i];
                i++;
            }
        }

        parts ~= buffer;
        return new StringInterpolationExpression(parts, expressions, formats);
    }

    private Statement structDeclaration() {
        consume(TokenType.IDENTIFIER, "Expected struct name");
        string name = previous().value;

        consume(TokenType.LEFT_PAREN, "Expected '(' after struct name");
        consume(TokenType.RIGHT_PAREN, "Expected ')' after struct name");
        consume(TokenType.DO, "Expected 'do' after struct signature");

        Parameter[] fields;
        MethodDeclaration[] methods;
        consumeNewlines();

        while (!check(TokenType.END) && !atEnd()) {
            if (match(TokenType.LET)) {
                string customTypeName;
                DuendeType fieldType = parseType(customTypeName);
                consume(TokenType.IDENTIFIER, "Expected field name");
                string fieldName = previous().value;
                consume(TokenType.ASSIGN, "Expected '=' in field declaration");

                // Skip the initializer for now - structs have default values
                expression();

                fields ~= Parameter(fieldName, fieldType, customTypeName, DuendeType.VOID, false);
            } else if (check(TokenType.INT_TYPE, TokenType.FLOAT_TYPE, TokenType.STRING_TYPE,
                          TokenType.BOOL_TYPE, TokenType.BYTES_TYPE, TokenType.VOID_TYPE,
                          TokenType.LIST_TYPE, TokenType.DICT_TYPE, TokenType.AUTO_TYPE,
                          TokenType.IDENTIFIER)) {
                methods ~= cast(MethodDeclaration)methodDeclaration();
            }
            consumeNewlines();
        }

        consume(TokenType.END, "Expected 'end' after struct body");
        return new StructDeclaration(name, fields, methods);
    }

    private Statement frameDeclaration() {
        consume(TokenType.IDENTIFIER, "Expected frame name");
        string name = previous().value;

        consume(TokenType.LEFT_PAREN, "Expected '(' after frame name");
        consume(TokenType.RIGHT_PAREN, "Expected ')' after frame name");
        consume(TokenType.DO, "Expected 'do' after frame signature");

        VariableDeclaration[] fields;
        MethodDeclaration[] methods;
        consumeNewlines();

        while (!check(TokenType.END) && !atEnd()) {
            if (match(TokenType.VAR, TokenType.LET)) {
                bool isMutable = previous().type == TokenType.VAR;
                string customTypeName;
                DuendeType fieldType = parseType(customTypeName);
                consume(TokenType.IDENTIFIER, "Expected field name");
                string fieldName = previous().value;
                consume(TokenType.ASSIGN, "Expected '=' in field declaration");
                Expression initializer = expression();

                fields ~= new VariableDeclaration(fieldName, fieldType, initializer, isMutable, customTypeName, DuendeType.VOID, null, false);
            } else if (check(TokenType.INT_TYPE, TokenType.FLOAT_TYPE, TokenType.STRING_TYPE,
                          TokenType.BOOL_TYPE, TokenType.BYTES_TYPE, TokenType.VOID_TYPE,
                          TokenType.LIST_TYPE, TokenType.DICT_TYPE, TokenType.AUTO_TYPE,
                          TokenType.IDENTIFIER)) {
                methods ~= cast(MethodDeclaration)methodDeclaration();
            }
            consumeNewlines();
        }

        consume(TokenType.END, "Expected 'end' after frame body");
        return new FrameDeclaration(name, fields, methods);
    }

    private Statement enumDeclaration() {
        consume(TokenType.IDENTIFIER, "Expected enum name");
        string name = previous().value;
        consume(TokenType.DO, "Expected 'do' after enum name");

        string[] values;
        consumeNewlines();

        // Parse enum values
        while (!check(TokenType.END) && !atEnd()) {
            if (check(TokenType.IDENTIFIER)) {
                consume(TokenType.IDENTIFIER, "Expected enum value");
                values ~= previous().value;

                // Optional comma - can have trailing comma
                if (match(TokenType.COMMA)) {
                    // Comma consumed, continue
                }
            }

            consumeNewlines(); // Skip any newlines between enum values
        }

        consume(TokenType.END, "Expected 'end' after enum body");
        return new EnumDeclaration(name, values);
    }

    private Statement methodDeclaration() {
        DuendeType returnType = parseType();
        consume(TokenType.IDENTIFIER, "Expected method name");
        string name = previous().value;

        consume(TokenType.LEFT_PAREN, "Expected '(' after method name");
        Parameter[] parameters;

        if (!check(TokenType.RIGHT_PAREN)) {
            do {
                string paramName;
                string customTypeName;
                DuendeType paramType;
                bool isNamed = false;

                // Disallow 'name: type' syntax in parameter declarations
                if (check(TokenType.IDENTIFIER) && current + 1 < tokens.length && tokens[current + 1].type == TokenType.COLON) {
                    throw new ParseError(": is not allowed in parameter declarations; use 'type name'");
                }

                // Regular 'type name' syntax only; ':' is invalid
                paramType = parseType(customTypeName);
                if (check(TokenType.COLON)) {
                    throw new ParseError(": is not allowed in parameter declarations; use 'type name'");
                }

                consume(TokenType.IDENTIFIER, "Expected parameter name");
                paramName = previous().value;

                // Optional default for method params
                Expression defVal = null;
                if (match(TokenType.ASSIGN)) {
                    defVal = expression();
                }

                parameters ~= Parameter(paramName, paramType, customTypeName, DuendeType.VOID, isNamed, defVal);
            } while (match(TokenType.COMMA));
        }

        consume(TokenType.RIGHT_PAREN, "Expected ')' after parameters");
        consume(TokenType.DO, "Expected 'do' after method signature");

        Statement[] body;
        consumeNewlines();

        while (!check(TokenType.END) && !atEnd()) {
            body ~= statementWithContext(true); // Method bodies are in local scope
            consumeNewlines();
        }

        consume(TokenType.END, "Expected 'end' after method body");
        return new MethodDeclaration(name, returnType, parameters, body);
    }

    private DuendeType parseType(out string customTypeName, out DuendeType innerType, out string innerCustomTypeName) {
        innerType = DuendeType.VOID; // Default inner type
        innerCustomTypeName = null;
        
        if (match(TokenType.INT_TYPE)) return DuendeType.INT;
        if (match(TokenType.FLOAT_TYPE)) return DuendeType.FLOAT;
        if (match(TokenType.STRING_TYPE)) return DuendeType.STRING;
        if (match(TokenType.BOOL_TYPE)) return DuendeType.BOOL;
        if (match(TokenType.BYTES_TYPE)) return DuendeType.BYTES;
        if (match(TokenType.VOID_TYPE)) return DuendeType.VOID;
        if (match(TokenType.LIST_TYPE)) {
            // Support generic list<T>
            if (match(TokenType.LESS)) {
                string innerNameLocal;
                DuendeType innerInnerType;
                string innerCustomLocal;
                innerType = parseType(innerNameLocal, innerInnerType, innerCustomLocal);
                if (innerType == DuendeType.CUSTOM) {
                    innerCustomTypeName = innerNameLocal;
                    customTypeName = innerNameLocal; // expose inner custom for downstream convenience
                } else {
                    innerCustomTypeName = innerCustomLocal;
                }
                consume(TokenType.GREATER, "Expected '>' after list inner type");
            }
            return DuendeType.LIST;
        }
        if (match(TokenType.DICT_TYPE)) return DuendeType.DICT;
        if (match(TokenType.AUTO_TYPE)) return DuendeType.AUTO;

        // Handle Result<T> and Maybe<T>
        if (match(TokenType.RESULT)) {
            consume(TokenType.LESS, "Expected '<' after Result");
            string innerNameLocal;
            DuendeType innerInnerType;
            string innerCustomLocal;
            innerType = parseType(innerNameLocal, innerInnerType, innerCustomLocal);
            if (innerType == DuendeType.CUSTOM) {
                innerCustomTypeName = innerNameLocal;
                customTypeName = innerNameLocal; // also expose via outer customTypeName for codegen convenience
            } else {
                innerCustomTypeName = innerCustomLocal;
            }
            consume(TokenType.GREATER, "Expected '>' after Result inner type");
            return DuendeType.RESULT;
        }

        if (match(TokenType.MAYBE)) {
            consume(TokenType.LESS, "Expected '<' after Maybe");
            string innerNameLocal;
            DuendeType innerInnerType;
            string innerCustomLocal;
            innerType = parseType(innerNameLocal, innerInnerType, innerCustomLocal);
            if (innerType == DuendeType.CUSTOM) {
                innerCustomTypeName = innerNameLocal;
                customTypeName = innerNameLocal;
            } else {
                innerCustomTypeName = innerCustomLocal;
            }
            consume(TokenType.GREATER, "Expected '>' after Maybe inner type");
            return DuendeType.MAYBE;
        }

        // Check for custom type (struct, frame, enum names)
        if (match(TokenType.IDENTIFIER)) {
            customTypeName = previous().value;
            // Explicitly reject non-Duende primitive names accidentally used as types.
            // Duende built-ins are handled above; anything else here is a custom type
            // name (struct/frame/enum) and is allowed. But we blacklist common D
            // primitive names to avoid leakage (e.g., 'long').
            immutable disallowed = [
                "long", "ulong", "uint", "ushort", "short", "byte", "ubyte",
                "char", "wchar", "dchar", "size_t", "ptrdiff_t", "double", "real"
            ];
            foreach (d; disallowed) {
                if (customTypeName == d) {
                    throw new ParseError("Unknown type '" ~ customTypeName ~ "'. Use Duende types (int, float, string, bool, bytes, void) or a user-defined Struct/Frame/Enum.");
                }
            }
            return DuendeType.CUSTOM;
        }

        throw new ParseError("Expected type");
    }

    private DuendeType parseType(out string customTypeName) {
        DuendeType innerType; string innerCustom;
        return parseType(customTypeName, innerType, innerCustom);
    }

    private DuendeType parseType() {
        string unused; DuendeType innerType; string innerCustom;
        return parseType(unused, innerType, innerCustom);
    }

    private void consumeNewlines() {
        while (match(TokenType.NEWLINE)) {
            // consume newlines
        }
    }

    private bool match(TokenType[] types...) {
        foreach (type; types) {
            if (check(type)) {
                advance();
                return true;
            }
        }
        return false;
    }

    private Token consume(TokenType type, string message) {
        if (check(type)) return advance();
        throw new ParseError(message ~ ". Got: " ~ peek().value);
    }

    private bool check(TokenType[] types...) {
        if (atEnd()) return false;
        foreach (type; types) {
            if (peek().type == type) return true;
        }
        return false;
    }

    private Token advance() {
        if (!atEnd()) current++;
        return previous();
    }

    private bool atEnd() {
        return peek().type == TokenType.EOF;
    }

    private Token peek() {
        return tokens[current];
    }

    private Token previous() {
        return tokens[current - 1];
    }

    private Statement protocolDeclaration() {
        consume(TokenType.IDENTIFIER, "Expected protocol name");
        string name = previous().value;

        consume(TokenType.DO, "Expected 'do' after protocol name");
        consumeNewlines();

        MethodSignature[] methods;

        while (!check(TokenType.END) && !atEnd()) {
            methods ~= parseMethodSignature();
            consumeNewlines();
        }

        consume(TokenType.END, "Expected 'end' after protocol body");

        return new ProtocolDeclaration(name, methods);
    }

    private MethodSignature parseMethodSignature() {
        string customTypeName;
        DuendeType returnType = parseType(customTypeName);

        consume(TokenType.IDENTIFIER, "Expected method name");
        string name = previous().value;

        consume(TokenType.LEFT_PAREN, "Expected '(' after method name");
        Parameter[] parameters;

        if (!check(TokenType.RIGHT_PAREN)) {
            do {
                string paramCustomTypeName;
                DuendeType paramType = parseType(paramCustomTypeName);
                bool isNamed = false;
                // Enforce 'type name' only; ':' is not allowed in parameter declarations
                if (check(TokenType.COLON)) {
                    throw new ParseError(": is not allowed in parameter declarations; use 'type name'");
                }

                consume(TokenType.IDENTIFIER, "Expected parameter name");
                string paramName = previous().value;
                Expression defVal = null;
                if (match(TokenType.ASSIGN)) {
                    defVal = expression();
                }
                parameters ~= Parameter(paramName, paramType, paramCustomTypeName, DuendeType.VOID, isNamed, defVal);
            } while (match(TokenType.COMMA));
        }

        consume(TokenType.RIGHT_PAREN, "Expected ')' after parameters");

        Statement[] defaultBody;
        bool hasDefaultImplementation = false;

        if (match(TokenType.DO)) {
            hasDefaultImplementation = true;
            consumeNewlines();

            while (!check(TokenType.END) && !check(TokenType.INT_TYPE) && !check(TokenType.FLOAT_TYPE) &&
                   !check(TokenType.STRING_TYPE) && !check(TokenType.BOOL_TYPE) && !check(TokenType.BYTES_TYPE) &&
                   !check(TokenType.VOID_TYPE) && !check(TokenType.LIST_TYPE) && !check(TokenType.DICT_TYPE) &&
                   !check(TokenType.AUTO_TYPE) && !atEnd()) {
                defaultBody ~= statement();
                consumeNewlines();
            }

            consume(TokenType.END, "Expected 'end' after method body");
        }

        return MethodSignature(name, returnType, parameters, defaultBody, hasDefaultImplementation);
    }

    private Statement annotatedDeclaration() {
        Annotation[] annotations;

        // Back up to parse the '@' again
        current--;

        // Parse all annotations
        while (match(TokenType.AT)) {
            consume(TokenType.IDENTIFIER, "Expected annotation name");
            string annotationName = previous().value;

            string[] args;
            if (match(TokenType.LEFT_PAREN)) {
                if (!check(TokenType.RIGHT_PAREN)) {
                    do {
                        consume(TokenType.IDENTIFIER, "Expected annotation argument");
                        args ~= previous().value;
                    } while (match(TokenType.COMMA));
                }
                consume(TokenType.RIGHT_PAREN, "Expected ')' after annotation arguments");
            }

            annotations ~= Annotation(annotationName, args);
            consumeNewlines();
        }

        // Now parse the actual declaration with annotations
        if (match(TokenType.STRUCT)) {
            return annotatedStructDeclaration(annotations);
        }
        if (match(TokenType.FRAME)) {
            return annotatedFrameDeclaration(annotations);
        }

        throw new ParseError("Expected struct or frame after annotation");
    }

    private Statement annotatedStructDeclaration(Annotation[] annotations) {
        consume(TokenType.IDENTIFIER, "Expected struct name");
        string name = previous().value;

        // Check if there are parentheses
        if (match(TokenType.LEFT_PAREN)) {
            consume(TokenType.RIGHT_PAREN, "Expected ')' after struct name");
        }

        consume(TokenType.DO, "Expected 'do' after struct signature");
        consumeNewlines();

        Parameter[] fields;
        MethodDeclaration[] methods;

        while (!check(TokenType.END) && !atEnd()) {
            if (check(TokenType.INT_TYPE, TokenType.FLOAT_TYPE, TokenType.STRING_TYPE,
                     TokenType.BOOL_TYPE, TokenType.BYTES_TYPE, TokenType.VOID_TYPE,
                     TokenType.LIST_TYPE, TokenType.DICT_TYPE, TokenType.AUTO_TYPE) ||
                check(TokenType.IDENTIFIER)) {

                if (isMethodDeclaration()) {
                    methods ~= cast(MethodDeclaration)methodDeclaration();
                } else {
                    string customTypeName;
                    DuendeType fieldType = parseType(customTypeName);
                    consume(TokenType.IDENTIFIER, "Expected field name");
                    string fieldName = previous().value;
                    fields ~= Parameter(fieldName, fieldType, customTypeName, DuendeType.VOID, false, null);
                }
            }
            consumeNewlines();
        }

        consume(TokenType.END, "Expected 'end' after struct body");

        return new StructDeclaration(name, fields, methods, annotations);
    }

    private Statement annotatedFrameDeclaration(Annotation[] annotations) {
        consume(TokenType.IDENTIFIER, "Expected frame name");
        string name = previous().value;

        // Check if there are parentheses
        if (match(TokenType.LEFT_PAREN)) {
            consume(TokenType.RIGHT_PAREN, "Expected ')' after frame name");
        }

        consume(TokenType.DO, "Expected 'do' after frame signature");
        consumeNewlines();

        VariableDeclaration[] fields;
        MethodDeclaration[] methods;

        while (!check(TokenType.END) && !atEnd()) {
            if (check(TokenType.LET, TokenType.VAR)) {
                fields ~= cast(VariableDeclaration)variableDeclarationWithContext(true); // Frame fields are local scope
            } else if (check(TokenType.INT_TYPE, TokenType.FLOAT_TYPE, TokenType.STRING_TYPE,
                            TokenType.BOOL_TYPE, TokenType.BYTES_TYPE, TokenType.VOID_TYPE,
                            TokenType.LIST_TYPE, TokenType.DICT_TYPE, TokenType.AUTO_TYPE) ||
                      check(TokenType.IDENTIFIER)) {

                if (isMethodDeclaration()) {
                    methods ~= cast(MethodDeclaration)methodDeclaration();
                } else {
                    string customTypeName;
                    DuendeType fieldType = parseType(customTypeName);
                    consume(TokenType.IDENTIFIER, "Expected field name");
                    string fieldName = previous().value;
                    consume(TokenType.ASSIGN, "Expected '=' in field declaration");
                    Expression initializer = expression();
                    fields ~= new VariableDeclaration(fieldName, fieldType, initializer, false, customTypeName, DuendeType.VOID, null, false);
                }
            }
            consumeNewlines();
        }

        consume(TokenType.END, "Expected 'end' after frame body");

        return new FrameDeclaration(name, fields, methods, annotations);
    }

    private bool isMethodDeclaration() {
        // Look ahead to see if this is a method declaration
        // Method: type identifier(
        // Field: type identifier (no parentheses)
        size_t saved = current;

        // Skip type
        if (check(TokenType.INT_TYPE, TokenType.FLOAT_TYPE, TokenType.STRING_TYPE,
                 TokenType.BOOL_TYPE, TokenType.BYTES_TYPE, TokenType.VOID_TYPE,
                 TokenType.LIST_TYPE, TokenType.DICT_TYPE, TokenType.AUTO_TYPE) ||
            check(TokenType.IDENTIFIER)) {
            advance();
        }

        // Skip identifier
        if (check(TokenType.IDENTIFIER)) {
            advance();
        }

        // Check if followed by '('
        bool isMethod = check(TokenType.LEFT_PAREN);

        // Restore position
        current = saved;
        return isMethod;
    }
}