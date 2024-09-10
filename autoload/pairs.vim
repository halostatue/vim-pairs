vim9script

# autoload/pairs.vim: Functions used for defining pair definitions. Translated to
# vim9script from tpope/vim-unimpaired.

# Returns the string to define a single mapping `lhs` in `mode` that will execute `rhs`.
#
# If `rhs` does not begin with `<Plug>`, then `<script>` will be added to the `flags`. The
# `flags` values can be any :map-arguments value (<buffer>, <nowait>, <silent>, <special>,
# <script>, <expr>, <unique>).
#
# If `g:<mode>remap` is a dictionary, the `lhs` will be modified based on successive
# lookups in this dictionary. The following replaces `[` and `]` mappings with `<` and `>`
# mappings. The lookup will be performed by removing characters from the end of `lhs` to
# allow for more specific to less specific matches.
#
#     g:nremap = { "[": "<", "]": ">" }
#     g:xremap = { "[": "<", "]": ">" }
#     g:oremap = { "[": "<", "]": ">" }
#
# If the target value is blank or `<skip>`, the mapping will be ignored.
#
# See tpope/vim-unimpaired#145 and tpope/vim-unimpaired@1a4bfc16b625.
export def Map(mode: string, base_lhs: string, rhs: string, flags: string = ''): string
  var skip = false
  var head = base_lhs
  var tail = ''

  var remaps = g:->get(mode .. 'remap', {})

  if type(remaps) == v:t_dict && !remaps->empty()
    while !head->empty()
      if remaps->has_key(head)
        head = remaps[head]

        if head->empty() || head ==? '<skip>'
          skip = true
        endif

        break
      endif

      tail = head->matchstr('<[^<>]*>$\|.$') .. tail
      head = head->substitute('<[^<>]*>$\|.$', '', '')
    endwhile
  endif

  var lhs = head .. tail

  if !skip && maparg(lhs, mode)->empty()
    var dfn = [mode .. 'map']
    var dflags = flags .. (flags !~? '<script>' && rhs =~? '^<Plug>' ? '' : '<script>')

    if !dflags->empty()
      dfn->add(dflags)
    endif

    dfn->extend([lhs, rhs])

    return dfn->join(' ')
  endif

  return ''
enddef

# Define a feature for a given mapset. `mapset` must be a list of strings representing
# multiple characters to map for the same toggle or a single string for a short map.
#
# The feature dictionary must have `enable`, `disable` and either `test` or `toggle` keys.
# If `test` is present, it will be turned into a conditional expression. Otherwise, the
# `toggle` value will be used by itself (for a function call). Because `<ScriptCmd>` is
# used, `<C-R>=` expressions are unavailable in `toggle`.
#
# The feature dictionary may have an `after` key which will be appended to the behaviour.
export def MapFeature(mapset: any, feature: dict<string>)
  var maps = type(mapset) == v:t_list ? mapset : [mapset]
  var tail = feature->get('after', '')
  var toggle = feature->has_key('test')
    ? $"if {feature.test}<Bar>{feature.disable}<Bar>else<Bar>{feature.enable}<Bar>endif"
    : feature.toggle

  if !tail->empty()
    tail = $"<Bar>{tail}"
  endif

  for map in maps
    execute $"nmap <script> <Plug>(pairs-enable){map} <ScriptCmd>{feature.enable}{tail}<CR>"
    execute $"nmap <script> <Plug>(pairs-disable){map} <ScriptCmd>{feature.disable}{tail}<CR>"
    execute $"nmap <script> <Plug>(pairs-toggle){map} <ScriptCmd>{toggle}{tail}<CR>"
  endfor
enddef

# Map the toggles for a boolean option.
export def MapBooleanOption(mapset: any, op: string, mode: string)
  MapFeature(mapset, { enable: $"{mode} {op}", disable: $"{mode} no{op}", test: $"&{op}",
    after: "PairsStatuslineRefresh()" })
enddef

# Define mappings that execute text transformation functions
export def MapTransform(map: string, xtype: string, dir: string)
  var name = $"{xtype}-{dir}"
  var tf = $"Transform('{xtype}', '{dir}')"

  var tfs = $'TransformSetup("{xtype}", "{dir}")'

  execute $"nnoremap <expr> <Plug>(pairs-{name}) {tfs}"
  execute $"xnoremap <expr> <Plug>(pairs-{name}) {tfs}"
  execute $"nnoremap <expr> <Plug>(pairs-{name}-line) {tfs} .. '_'"

  execute Map('n', map, $"<Plug>(pairs-{name})")
  execute Map('x', map, $"<Plug>(pairs-{name})")
  execute Map('n', map .. map[map->strlen() - 1], $"<Plug>(pairs-{name}-line)")
enddef

# Scoped functions

def PairsStatuslineRefresh(): string
  &l:readonly = &l:readonly
  return ''
enddef

def PairsColorColumn(should_clear: bool): string
  if !&colorcolumn->empty()
    w:colorcolumn = &colorcolumn
  endif
  return should_clear ? '' : w:->get('colorcolumn', g:->get('pairs_colorcolumn', '+1'))
enddef

def PairsSetBackground(light: bool)
  var ocn = g:colors_name

  &background = light ? 'light' : 'dark'

  if !exists('g:colors_name') || ocn != g:colors_name
    execute $"colorscheme {ocn}"
    redraw | echo $"Colorscheme {ocn} does not support changing background"
  endif
enddef

def StringEncode(str: string): string
  var map = {"\n": 'n', "\r": 'r', "\t": 't', "\b": 'b', "\f": '\f', '"': '"', '\': '\'}
  return str->substitute(
    "[\001-\033\\\\\"]",
    '\="\\" .. get(map, submatch(0), printf("%03o", char2nr(submatch(0))))',
    'g'
  )
enddef

def StringDecode(value: string): string
  var map = {'n': "\n", 'r': "\r", 't': "\t", 'b': "\b", 'f': "\f", 'e': "\e", 'a': "\001", 'v': "\013", "\n": ''}

  var str = value

  if str =~# '^\s*".\{-\}\\\@<!\%(\\\\\)*"\s*\n\=$'
    str = str->substitute('^\s*\zs"', '', '')->substitute('"\ze\s*\n\=$', '', '')
  endif

  return str->substitute(
    '\\\(\o\{1,3\}\|x\x\{1,2\}\|u\x\{1,4\}\|.\)',
    '\=get(map, submatch(1), submatch(1) =~? "^[0-9xu]" ? nr2char(str2nr("0" .. substitute(submatch(1), "^[Uu]", "x", ""), 16)) : submatch(1))',
    'g'
  )
enddef

def UrlEncode(str: string): string
  # iconv trick to convert utf-8 bytes to 8bits indiviual char.
  return str
    ->iconv('latin1', 'utf-8')
    ->substitute('[^A-Za-z0-9_.~-]', '\="%" .. printf("%02X", char2nr(submatch(0)))', 'g')
enddef

def UrlDecode(value: string): string
  return value
    ->substitute('%0[Aa]\n$', '%0A', '')
    ->substitute('%0[Aa]', '\n', 'g')
    ->substitute('+', ' ', 'g')
    ->substitute('%\(\x\x\)', '\=nr2char(str2nr("0x" .. submatch(1), 16))', 'g')
    ->iconv('utf-8', 'latin1')
enddef

# HTML entities {{{2
g:pairs_html_entities = {
      \ 'nbsp':     160, 'iexcl':    161, 'cent':     162, 'pound':    163,
      \ 'curren':   164, 'yen':      165, 'brvbar':   166, 'sect':     167,
      \ 'uml':      168, 'copy':     169, 'ordf':     170, 'laquo':    171,
      \ 'not':      172, 'shy':      173, 'reg':      174, 'macr':     175,
      \ 'deg':      176, 'plusmn':   177, 'sup2':     178, 'sup3':     179,
      \ 'acute':    180, 'micro':    181, 'para':     182, 'middot':   183,
      \ 'cedil':    184, 'sup1':     185, 'ordm':     186, 'raquo':    187,
      \ 'frac14':   188, 'frac12':   189, 'frac34':   190, 'iquest':   191,
      \ 'Agrave':   192, 'Aacute':   193, 'Acirc':    194, 'Atilde':   195,
      \ 'Auml':     196, 'Aring':    197, 'AElig':    198, 'Ccedil':   199,
      \ 'Egrave':   200, 'Eacute':   201, 'Ecirc':    202, 'Euml':     203,
      \ 'Igrave':   204, 'Iacute':   205, 'Icirc':    206, 'Iuml':     207,
      \ 'ETH':      208, 'Ntilde':   209, 'Ograve':   210, 'Oacute':   211,
      \ 'Ocirc':    212, 'Otilde':   213, 'Ouml':     214, 'times':    215,
      \ 'Oslash':   216, 'Ugrave':   217, 'Uacute':   218, 'Ucirc':    219,
      \ 'Uuml':     220, 'Yacute':   221, 'THORN':    222, 'szlig':    223,
      \ 'agrave':   224, 'aacute':   225, 'acirc':    226, 'atilde':   227,
      \ 'auml':     228, 'aring':    229, 'aelig':    230, 'ccedil':   231,
      \ 'egrave':   232, 'eacute':   233, 'ecirc':    234, 'euml':     235,
      \ 'igrave':   236, 'iacute':   237, 'icirc':    238, 'iuml':     239,
      \ 'eth':      240, 'ntilde':   241, 'ograve':   242, 'oacute':   243,
      \ 'ocirc':    244, 'otilde':   245, 'ouml':     246, 'divide':   247,
      \ 'oslash':   248, 'ugrave':   249, 'uacute':   250, 'ucirc':    251,
      \ 'uuml':     252, 'yacute':   253, 'thorn':    254, 'yuml':     255,
      \ 'OElig':    338, 'oelig':    339, 'Scaron':   352, 'scaron':   353,
      \ 'Yuml':     376, 'circ':     710, 'tilde':    732, 'ensp':    8194,
      \ 'emsp':    8195, 'thinsp':  8201, 'zwnj':    8204, 'zwj':     8205,
      \ 'lrm':     8206, 'rlm':     8207, 'ndash':   8211, 'mdash':   8212,
      \ 'lsquo':   8216, 'rsquo':   8217, 'sbquo':   8218, 'ldquo':   8220,
      \ 'rdquo':   8221, 'bdquo':   8222, 'dagger':  8224, 'Dagger':  8225,
      \ 'permil':  8240, 'lsaquo':  8249, 'rsaquo':  8250, 'euro':    8364,
      \ 'fnof':     402, 'Alpha':    913, 'Beta':     914, 'Gamma':    915,
      \ 'Delta':    916, 'Epsilon':  917, 'Zeta':     918, 'Eta':      919,
      \ 'Theta':    920, 'Iota':     921, 'Kappa':    922, 'Lambda':   923,
      \ 'Mu':       924, 'Nu':       925, 'Xi':       926, 'Omicron':  927,
      \ 'Pi':       928, 'Rho':      929, 'Sigma':    931, 'Tau':      932,
      \ 'Upsilon':  933, 'Phi':      934, 'Chi':      935, 'Psi':      936,
      \ 'Omega':    937, 'alpha':    945, 'beta':     946, 'gamma':    947,
      \ 'delta':    948, 'epsilon':  949, 'zeta':     950, 'eta':      951,
      \ 'theta':    952, 'iota':     953, 'kappa':    954, 'lambda':   955,
      \ 'mu':       956, 'nu':       957, 'xi':       958, 'omicron':  959,
      \ 'pi':       960, 'rho':      961, 'sigmaf':   962, 'sigma':    963,
      \ 'tau':      964, 'upsilon':  965, 'phi':      966, 'chi':      967,
      \ 'psi':      968, 'omega':    969, 'thetasym': 977, 'upsih':    978,
      \ 'piv':      982, 'bull':    8226, 'hellip':  8230, 'prime':   8242,
      \ 'Prime':   8243, 'oline':   8254, 'frasl':   8260, 'weierp':  8472,
      \ 'image':   8465, 'real':    8476, 'trade':   8482, 'alefsym': 8501,
      \ 'larr':    8592, 'uarr':    8593, 'rarr':    8594, 'darr':    8595,
      \ 'harr':    8596, 'crarr':   8629, 'lArr':    8656, 'uArr':    8657,
      \ 'rArr':    8658, 'dArr':    8659, 'hArr':    8660, 'forall':  8704,
      \ 'part':    8706, 'exist':   8707, 'empty':   8709, 'nabla':   8711,
      \ 'isin':    8712, 'notin':   8713, 'ni':      8715, 'prod':    8719,
      \ 'sum':     8721, 'minus':   8722, 'lowast':  8727, 'radic':   8730,
      \ 'prop':    8733, 'infin':   8734, 'ang':     8736, 'and':     8743,
      \ 'or':      8744, 'cap':     8745, 'cup':     8746, 'int':     8747,
      \ 'there4':  8756, 'sim':     8764, 'cong':    8773, 'asymp':   8776,
      \ 'ne':      8800, 'equiv':   8801, 'le':      8804, 'ge':      8805,
      \ 'sub':     8834, 'sup':     8835, 'nsub':    8836, 'sube':    8838,
      \ 'supe':    8839, 'oplus':   8853, 'otimes':  8855, 'perp':    8869,
      \ 'sdot':    8901, 'lceil':   8968, 'rceil':   8969, 'lfloor':  8970,
      \ 'rfloor':  8971, 'lang':    9001, 'rang':    9002, 'loz':     9674,
      \ 'spades':  9824, 'clubs':   9827, 'hearts':  9829, 'diams':   9830,
      \ 'apos':      39}
# }}}2

def XmlEncode(str: string): string
  return str
    ->substitute('&', '\&amp;', 'g')
    ->substitute('<', '\&lt;', 'g')
    ->substitute('>', '\&gt;', 'g')
    ->substitute('"', '\&quot;', 'g')
    ->substitute("'", '\&apos;', 'g')
enddef

def XmlEntityDecode(str: string): string
  return str
    ->substitute('\c&#\%(0*38\|x0*26\);', '&amp;', 'g')
    ->substitute('\c&#\(\d\+\);', '\=nr2char(str2nr(submatch(1)))', 'g')
    ->substitute('\c&#\(x\x\+\);', '\=nr2char(str2nr("0" .. submatch(1), 16))', 'g')
    ->substitute('\c&apos;', "'", 'g')
    ->substitute('\c&quot;', '"', 'g')
    ->substitute('\c&gt;', '>', 'g')
    ->substitute('\c&lt;', '<', 'g')
    ->substitute('\C&\(\%(amp;\)\@!\w*\);', '\=nr2char(get(g:pairs_html_entities, submatch(1), 63))', 'g')
    ->substitute('\c&amp;', '\&', 'g')
enddef

def XmlDecode(str: string): string
  return XmlEntityDecode(
    str->substitute('<\%([[:alnum:]-]\+=\%("[^"]*"\|''[^'']*''\)\|.\)\{-\}>', '', 'g')
  )
enddef

def Transform(xtype: string, dir: string, otype: string = '')
  var algorithm = $"{xtype}{dir}"
  var sel_save = &selection
  var cb_save = &clipboard

  set selection=inclusive clipboard-=unnamed clipboard-=unnamedplus

  var reg_save = getreginfo('@')

  if otype ==# 'line'
    silent execute "normal! '[V']y"
    setreg('@', getreg('@')->substitute("\n$", '', ''))
  elseif otype ==# 'block'
    silent execute "normal! `[\<C-V>`]y"
  else
    silent execute "normal! `[v`]y"
  endif

  setreg('@', call(algorithm, [getreg('@')]))
  normal! gvp

  setreg('@', reg_save)

  &selection = sel_save
  &clipboard = cb_save
enddef

def TransformSetup(xtype: string, dir: string): string
  &operatorfunc = function(Transform, [xtype, dir])
  return 'g@'
enddef

defcompile
