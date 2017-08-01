const assert = require('assert')
const path = require('path')
const fs = require('fs')

const esprima = require('esprima')

const estraverse = require('estraverse')
const resolveSync = require('resolve').sync

const util = require('./util')

const coreModules = fs.readdirSync(__dirname + '/../node/lib')
  .map((mod) => mod.replace(/\.js$/, ''))

module.exports = (ast, { readFileSync = fs.readFileSync, foundModules = {}, filename = '', isMain = true, sluginator = null, _doWrap = true, resolve = resolveSync, slug, _recurse = module.exports } = {}) => {
  if (!sluginator) {
    sluginator = util.nameSluginator()
  }

  const dirname = path.dirname(filename)
  const justTheFilename = path.basename(filename)

  let otherModules = []
  findModules(ast, resolve, dirname, (resolvedFilename) => {
    let slug = foundModules[resolvedFilename]
    if (!slug) {
      slug = sluginator(path.basename(resolvedFilename).replace(/\.js$/, ''))
      const ast = esprima.parse(readFileSync(resolvedFilename) + '')
      foundModules[resolvedFilename] = slug
      thisModule = _recurse(ast, {
        readFileSync,
        foundModules,
        filename: resolvedFilename,
        isMain: false,
        sluginator,
        _doWrap,
        resolve,
        slug: slug,
      })
      otherModules = otherModules.concat([thisModule.body])
    }
    return '_require' + slug
  })

  if (
    _doWrap !== false &&
    isMain === false
  ) {
    if (!slug) slug = sluginator(justTheFilename.replace(/\.js$/i, ''))
    ast.body = generateRequirerFunction({ slug, dirname, filename, body: ast.body })
    assert(typeof ast.body.length === 'number')
  }

  ast.body = otherModules
    .reduce(
      (accum, bod) => accum.concat(bod),
      [])
    .concat(ast.body)

  return ast
}

const findModules = (ast, resolve, dirname, getModuleSlug) =>
  estraverse.replace(ast, {
    leave: (node) => {
      // TODO check for things called "require" in the same scope
      if (node.type === 'CallExpression' &&
          node.callee.name === 'require' &&
          node.arguments.length === 1 &&
          node.arguments[0].type === 'Literal') {
        const moduleName = node.arguments[0].value
        let resolved
        if (coreModules.indexOf(moduleName) != -1) {
          resolved = __dirname + `/../node/lib/${moduleName}.js`
        } else {
          resolved = resolve(moduleName, { basedir: dirname })
        }
        const newName = getModuleSlug(resolved, node.arguments[0].value)
        if (newName) {
          return util.call(newName)
        }
      }
    }
  })

const wrapModuleContents = ({ body, filename = '', dirname = '' }) => [
  util.declaration('module', util.object()),
  util.declaration('__filename', util.literal(filename)),
  util.declaration('__dirname', util.literal(dirname)),
  ...body,
  util.return(util.member('module', 'exports'))
]

const generateRequirerFunction = ({ slug, dirname, filename, body }) => [
  util.declaration('_was_module_initialised' + slug, util.literal(false)),
  util.declaration('_module' + slug),
  util.functionDeclaration({
    id: '_initmodule' + slug,
    body: wrapModuleContents({ body, filename, dirname })
  }),
  util.functionDeclaration({
    id: '_require' + slug,
    body: [
      util.if(
        util.identifier('_was_module_initialised' + slug),
        util.return('_module' + slug)
      ),
      util.expressionStatement(
        util.assignment(
          '_module' + slug,
          util.call('_initmodule' + slug)
        )
      ),
      util.return('_module' + slug)
    ]
  })
]
