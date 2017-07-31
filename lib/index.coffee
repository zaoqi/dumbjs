fs = require 'fs'
assert = require 'assert'
escope = require 'escope'
esprima = require 'esprima'
escodegen = require 'escodegen'
estraverse = require 'estraverse'
child_process = require 'child_process'

astValidator = require 'ast-validator'

requireObliteratinator = require './require-obliteratinator'
typeConversions = require './type-conversions'
topmost = require './topmost'
declosurify = require './declosurify'
bindify = require './bindify'
mainify = require './mainify'
thatter = require './thatter'
depropinator = require './depropinator'
deregexenise = require './deregexenise'
ownfunction = require './ownfunction'
util = require './util'

clean_ast = (ast) ->
  estraverse.traverse(ast, {
    leave: (node) ->
      delete node.scope
      delete node.objType
  })

dumbifyAST = (ast, opt = {}) ->
  if opt.deregexenise isnt false
    ast = deregexenise ast
    clean_ast ast
  if opt.requireObliteratinator isnt false
    ast = requireObliteratinator ast, { filename: opt.filename or '' }
    clean_ast ast
  if opt.typeConversions isnt false
    typeConversions(ast, opt.typeConversions or {})
    clean_ast ast
  if opt.mainify isnt false
    mainify(ast, opt.mainify or {})
    clean_ast ast
  if opt.thatter isnt false
    thatter ast
    clean_ast ast
  if opt.depropinator isnt false
    depropinator ast
    clean_ast ast
  if opt.declosurify isnt false  # this one is not really a pass, it's a pre-declosurify operation
    ownfunction ast
    clean_ast ast
    declosurify ast
    clean_ast ast
  if opt.topmost isnt false
    topmost ast
    clean_ast ast
  if opt.bindify isnt false
    bindify ast  # mutate ast
    clean_ast ast
  ret = estraverse.replace ast, enter: (node) ->
    if node.type is 'ExpressionStatement'
      if node.expression.type is 'Literal'
        return estraverse.VisitorOption.Remove
      return node  # TODO check what we get first
    else if node.type in ['FunctionDeclaration']
      return node
    else if node.type is 'Literal'
      return node
    else if node.type in ['Program', 'BlockStatement']
      declarations_to_declarators = (decls, kind) ->
        return decls.map (decl) -> {
          type: 'VariableDeclaration',
          declarations: [ decl ],
          kind: kind,
        }
      node.body = node.body
        .map (node) ->
          if node.type is 'VariableDeclaration' and node.declarations.length isnt 1
            return declarations_to_declarators(node.declarations, node.kind)
          if node.type is 'ForStatement' and node.init?.type is 'VariableDeclaration' and node.init.declarations.length isnt 1
            init = node.init
            node.init = null
            return declarations_to_declarators(init.declarations, init.kind).concat([node])
          else
            return [node]
        .reduce(
          (accum, b) -> accum.concat(b),
          []
        )
      return node
    else if node.type in ['Program', 'Identifier', 'CallExpression', 'BlockStatement', 'FunctionExpression', 'VariableDeclaration', 'VariableDeclarator', 'IfStatement', 'UnaryExpression', 'MemberExpression', 'LogicalExpression', 'BinaryExpression', 'ContinueStatement', 'TryStatement', 'CatchClause', 'ReturnStatement', 'NewExpression', 'ThrowStatement', 'SequenceExpression', 'AssignmentExpression', 'ObjectExpression', 'Property', 'ConditionalExpression', 'ForStatement', 'ForInStatement', 'UpdateExpression', 'ArrayExpression', 'ThisExpression', 'SwitchStatement', 'SwitchCase', 'BreakStatement', 'WhileStatement', 'DoWhileStatement', 'EmptyStatement']
      return node
    else
      throw new Error('Unknown node type ' + node.type + ' in ' + node)
  isValid = astValidator ret
  if isValid != true
    throw isValid
  return ret

esprimaOpts = {
  sourceType: 'module',
  ecmaVersion: 6,
  allowReturnOutsideFunction: true,
  allowHashBang: true,
  locations: true,
  attachComment: true,
}

dumbify = (js, opt = {}) ->
  mayContainRequire = /require\s*?\(/m.test js
  ast = esprima.parse(js, esprimaOpts)
  if mayContainRequire is false
    opt.requireObliteratinator = false
  ast = dumbifyAST ast, opt
  return escodegen.generate ast, { comment: true }

module.exports = dumbify
module.exports.dumbify = dumbify
module.exports.dumbifyAST = dumbifyAST
module.exports.enableTestMode = util.enableTestMode
