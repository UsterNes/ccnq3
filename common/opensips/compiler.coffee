#!/usr/bin/env coffee
# compiler.coffee -- merge OpenSIPS configuration fragments

fs = require 'fs'
path = require 'path'

macros_cfg = (t,params) ->

  # Evaluate parameters after macro substitution
  t = t.replace /// \b define \s+ (\w+) \b ///g, (str,$1) ->
    params[$1] = 1
    return ''
  t = t.replace /// \b undef \s+ (\w+) \b ///g, (str,$1) ->
    params[$1] = 0
    return ''

  # Since we don't use a real (LR) parser, these are sorted by match order.
  conditionals = ->
    t = t.replace ///
      \b if \s+ not \s+ (\w+) \b
      ([\s\S]*?)
      \b end \s+ if \s+ not \s+ \1 \b
      ///g, (str,$1,$2) -> if not params[$1] then $2 else ''
    t = t.replace ///
      \b if \s+ (\w+) \s+ is \s+ not \s+ (\w+) \b
      ([\s\S]*?)
      \b end \s+ if \s+ \1 \s+ is \s+ not \s+ \2 \b
      ///g, (str,$1,$2,$3) -> if params[$1] isnt $2 then $3 else ''
    t = t.replace ///
      \b if \s+ (\w+) \s+ is \s+ (\w+) \b
      ([\s\S]*?)
      \b end \s+ if \s+ \1 \s+ is \s+ \2 \b
      ///g, (str,$1,$2,$3) -> if params[$1] is $2 then $3 else ''
    t = t.replace ///
      \b if \s+ (\w+) \b
      ([\s\S]*?)
      \b end \s+ if \s+ \1 \b
      ///g, (str,$1,$2) -> if params[$1] then $2 else ''

  do conditionals
  do conditionals

  # Substitute parameters
  t = t.replace /// \$ \{ (\w+) \} ///g, (str,$1) ->
    if params[$1]?
      return params[$1]
    else
      console.log "Undefined #{$1}"
      return str

  return t

do test = ->
  verify = (t,m,p) ->
    (require 'assert').strictEqual t, macros_cfg m, p
  verify 'var is 3', 'var is ${var}', var:3
  verify 'var is this', 'var is ${var}', var:'this'
  verify ' yes ', 'if it yes end if it', it:1
  verify ' yes ', 'if not it yes end if not it', it:0
  verify '', 'if it is 0 yes end if it is 0', it:1
  verify ' yes ', 'if it is bob yes end if it is bob', it:'bob'
  # verify ' yes ', 'if it is 0 yes end if it is 0', it:0 # fails: strings vs number
  verify ' yes ', 'if it is not bob yes end if it is not bob', it:'bar'

### compile_cfg

    Build OpenSIPS configuration from fragments.

###

compile_cfg = (base_dir,params) ->

  recipe = params.recipe

  result =
    """
    #
    # Automatically generated configuration file.
    # #{params.comment}
    #

    """

  for extension in ['variables','modules','cfg']
    for building_block in recipe
      file = path.join base_dir, 'fragments', "#{building_block}.#{extension}"
      try
        fragment  = "\n## ---  Start #{file}  --- ##\n\n"
        fragment += fs.readFileSync file
        fragment += "\n## ---  End #{file}  --- ##\n\n"
        result += fragment
  return macros_cfg result, params

###

  configure_opensips
    Subtitute configuration variables in a complete OpenSIPS configuration file
    (such as one generated by compile_cfg).

###

configure_opensips = (params) ->

  # Handle special parameters specially
  escape_listen = (_) -> "listen=#{_}\n"

  params.listen = params.listen.map(escape_listen).join '' if params.listen?

  cfg_text = compile_cfg params.opensips_base_lib, params

  fs.writeFileSync params.runtime_opensips_cfg, cfg_text

module.exports = configure_opensips
