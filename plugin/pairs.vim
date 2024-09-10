vim9script

# pairs.vim - Pairs of handy bracket mappings and other toggles.
#
# This is a vim9script port of tpope/vim-unimpaired with additional configuration options
# adapted from additional sources, including:
#
# - phongnh/vim-toggler: conceallevel, showmatch, incsearch, expandtab, showcmd
# - riceissa/vim-more-toggling: syntax

if g:->get('loaded_pairs', false)
  finish
endif

g:loaded_pairs = true

import autoload 'pairs.vim'

# Section: Next and previous mappings.

# Map a family of commands: next, previous, first, and last.
def MapNextFamily(map: string, base_cmd: string, current: string)
  var prefix = $"<Plug>(pairs-{base_cmd}" # <Plug>(pairs-b
  var cmd = $"\" .. (v:count ? v:count : \"\") .. \"{base_cmd}"
  var zv = (base_cmd ==# 'l' || base_cmd ==# 'c' ? 'zv' : '')
  var tail = '<CR>' .. zv

  # <Plug>(pairs-bprevious) => :bprevious
  execute $"nnoremap <silent> {prefix}previous) :<C-U>execute \"{cmd}previous\"{tail}"
  execute $"nnoremap <silent> {prefix}next) :<C-U>execute \"{cmd}next\"{tail}"
  execute $"nnoremap {prefix}first) "
    .. $":<C-U><C-R>=v:count ? v:count .. \"{current}\" : \"{base_cmd}first\"<CR><CR>{zv}"
  execute $"nnoremap {prefix}last) "
    .. $":<C-U><C-R>=v:count ? v:count .. \"{current}\" : \"{base_cmd}last\"<CR><CR>{zv}"

  # <Plug>PairsBPrevious => :bprevious

  execute pairs.Map('n', $"[{map}", $"{prefix}previous)")
  execute pairs.Map('n', $"]{map}", $"{prefix}next)")
  execute pairs.Map('n', $"[{map->toupper()}", $"{prefix}first)")
  execute pairs.Map('n', $"]{map->toupper()}", $"{prefix}last)")

  if base_cmd ==# 'c' || base_cmd == 'l'
    execute $"nnoremap <silent> {prefix}pfile) :<C-U>execute \"{cmd}pfile\"{tail}"
    execute $"nnoremap <silent> {prefix}nfile) :<C-U>execute \"{cmd}nfile\"{tail}"
    execute pairs.Map('n', $"[<C-{map->toupper()}>", $"{prefix}pfile)")
    execute pairs.Map('n', $"]<C-{map->toupper()}>", $"{prefix}nfile)")
  endif

  if base_cmd ==# 't'
    nnoremap <silent> <Plug>(pairs-ptprevious) :<C-U>execute v:count1 .. "ptprevious"<CR>
    nnoremap <silent> <Plug>(pairs-ptnext) :<C-U>execute v:count1 .. "ptnext"<CR>
    execute pairs.Map('n', '[<C-T>', '<Plug>(pairs-ptprevious)')
    execute pairs.Map('n', ']<C-T>', '<Plug>(pairs-ptnext)')
  endif
enddef

MapNextFamily('a', '', 'argument')
MapNextFamily('b', 'b', 'buffer')
MapNextFamily('l', 'l', 'll')
MapNextFamily('q', 'c', 'cc')
MapNextFamily('t', 't', 'trewind')

def Entries(base_path: string): list<string>
  var path = base_path
    ->substitute('[\\/]$', '', '')
    ->substitute('[[$*]', '[&]', 'g')
  var files = glob(path .. '/.*')->split("\n") + glob(path .. '/*')->split("\n")

  files = files
    ->map((_, v) => v->substitute("[\\/]$", "", ""))
    ->filter((_, v) => v !~# "[\\\\/]\\.\\.\\=$")

  var suffixes = &suffixes
    ->escape('~.*$^')
    ->split(',')
    ->filter((_, v) => !v->empty())

  if !suffixes->empty()
    var filter_suffixes = suffixes->join('$\|') .. '$'
    files = files->filter((_, v) => v !~# filter_suffixes)
  endif

  return files->sort()
enddef

def FileByOffset(offset: number): string
  var file = expand('%:p')

  if file->empty()
    file = getcwd() .. '/'
  endif

  var pos = offset

  while pos != 0
    var files = Entries(file->fnamemodify(':h'))

    files = offset < 0
      ? files->filter((_, v) => v <# file)->reverse()
      : files->filter((_, v) => v ># file)

    var temp = files->get(0, '')

    if temp->empty()
      file = file->fnamemodify(':h')
    else
      file = temp
      var found = 1

      while file->isdirectory()
        files = Entries(file)

        if files->empty()
          found = 0
          break
        endif

        file = files[pos > 0 ? 0 : -1]
      endwhile

      pos += (pos > 0 ? -1 : 1) * found
    endif
  endwhile

  return file
enddef

def GetWindow(): dict<any>
  return win_getid()->getwininfo()->get(0, {})
enddef

export def PreviousFileEntry(count: number): string
  var window = GetWindow()

  return window->get('loclist')
    ? 'lolder ' .. count
    : window->get('quickfix')
    ? 'colder ' .. count
    : 'edit ' .. fnameescape(fnamemodify(FileByOffset(-count), ':.'))
enddef

export def NextFileEntry(count: number): string
  var window = GetWindow()


  return window->get('loclist')
    ? 'lnewer ' .. count
    : window->get('quickfix')
    ? 'cnewer ' .. count
    : 'edit ' .. fnameescape(fnamemodify(FileByOffset(count), ':.'))
enddef

nnoremap <silent> <Plug>(pairs-directory-next) <ScriptCmd>execute NextFileEntry(v:count1)<CR>
nnoremap <silent> <Plug>(pairs-directory-previous) <ScriptCmd>execute PreviousFileEntry(v:count1)<CR>
execute pairs.Map('n', ']f', '<Plug>(pairs-directory-next)')
execute pairs.Map('n', '[f', '<Plug>(pairs-directory-previous)')

# Section: Diff / Conflict Context

def Context(reverse: bool): number
  return search('^\(@@ .* @@\|[<=>|]\{7}[<=>|]\@!\)', reverse ? 'bW' : 'W')
enddef

def ContextMotion(reverse: bool)
  if reverse
    normal -
  endif

  search('^@@ .* @@\|^diff \|^[<=>|]\{7}[<=>|]\@!', 'bWc')

  var end: number = 0

  if getline('.') =~# '^diff '
    end = search('^diff ', 'Wn') - 1
    if end < 0
      end = line('$')
    endif
  elseif getline('.') =~# '^@@ '
    end = search('^@@ .* @@\|^diff ', 'Wn') - 1
    if end < 0
      end = line('$')
    endif
  elseif getline('.') =~# '^=\{7\}'
    normal +
    end = search('^>\{7}>\@!', 'Wnc')
  elseif getline('.') =~# '^[<=>|]\{7\}'
    end = search('^[<=>|]\{7}[<=>|]\@!', 'Wn') - 1
  else
    return
  endif

  if end > line('.')
    execute 'normal! V' .. (end - line('.')) .. 'j'
  elseif end == line('.')
    normal! V
  endif
enddef

nnoremap <silent> <Plug>(pairs-context-previous) <ScriptCmd>Context(true)<CR>
nnoremap <silent> <Plug>(pairs-context-next) <ScriptCmd>Context(false)<CR>
vnoremap <silent> <Plug>(pairs-context-previous) <ScriptCmd>execute 'normal! gv'<Bar>call Context(true)<CR>
vnoremap <silent> <Plug>(pairs-context-next) <ScriptCmd>execute 'normal! gv'<Bar>call Context(false)<CR>
onoremap <silent> <Plug>(pairs-context-previous) <ScriptCmd>ContextMotion(true)<CR>
onoremap <silent> <Plug>(pairs-context-next) <ScriptCmd>ContextMotion(false)<CR>

execute pairs.Map('n', '[n', '<Plug>(pairs-context-previous)')
execute pairs.Map('n', ']n', '<Plug>(pairs-context-next)')
execute pairs.Map('x', '[n', '<Plug>(pairs-context-previous)')
execute pairs.Map('x', ']n', '<Plug>(pairs-context-next)')
execute pairs.Map('o', '[n', '<Plug>(pairs-context-previous)')
execute pairs.Map('o', ']n', '<Plug>(pairs-context-next)')

# Section: Line operations

def BlankUp(): string
  var cmd = $"put! =repeat(nr2char(10), v:count1)|silent normal '']+"
  if &modifiable
    cmd ..= $"|silent! call repeat#set(\"<Plug>(pairs-blank-up)\", v:count1)"
  endif
  return cmd
enddef

def BlankDown(): string
  var cmd = $"put =repeat(nr2char(10), v:count1)|silent normal ''[-"
  if &modifiable
    cmd ..= $"|silent! call repeat#set(\"<Plug>(pairs-blank-down)\", v:count1)"
  endif
  return cmd
enddef

nnoremap <silent> <Plug>(pairs-blank-up) <ScriptCmd>execute BlankUp()<CR>
nnoremap <silent> <Plug>(pairs-blank-down) <ScriptCmd>execute BlankDown()<CR>

execute pairs.Map('n', '[<Space>', '<Plug>(pairs-blank-up)')
execute pairs.Map('n', ']<Space>', '<Plug>(pairs-blank-down)')

def ExecCopyMove(cmd: string)
  var old_fdm = &foldmethod

  if old_fdm !=# 'manual'
    setlocal foldmethod=manual
    &foldmethod = 'manual'
  endif

  normal! m`
  # silent! execute cmd
  execute cmd
  normal! ``

  if old_fdm !=# 'manual'
    &foldmethod = old_fdm
  endif
enddef

def CopyMove(action: string, cmd: string, count: any, map: string)
  ExecCopyMove($"{action} {cmd}{count}")
  silent! call repeat#set($"\<Plug>(pairs-{action}-{map})", count)
enddef

def CopyMoveSelectionUp(action: string, count: any)
  ExecCopyMove($"'<,'>{action} '<--{count}")
  silent! call repeat#set($"\<Plug>(pairs-{action}-selection-up)", count)
enddef

def CopyMoveSelectionDown(action: string, count: any)
  ExecCopyMove($"'<,'>{action} '>+{count}")
  silent! call repeat#set("\<Plug>(pairs-{action}-selection-down)", count)
enddef

nnoremap <silent> <Plug>(pairs-move-up) <ScriptCmd>CopyMove('move', '--', v:count1, 'up')<CR>
nnoremap <silent> <Plug>(pairs-move-down) <ScriptCmd>CopyMove('move', '+', v:count1, 'down')<CR>
noremap <silent> <Plug>(pairs-move-selection-up) <ScriptCmd>CopyMoveSelectionUp('move', v:count1)<CR>
noremap <silent> <Plug>(pairs-move-selection-down) <ScriptCmd>CopyMoveSelectionDown('move', v:count1)<CR>

execute pairs.Map('n', '[e', '<Plug>(pairs-move-up)')
execute pairs.Map('n', ']e', '<Plug>(pairs-move-down)')
execute pairs.Map('x', '[e', '<Plug>(pairs-move-selection-up)')
execute pairs.Map('x', ']e', '<Plug>(pairs-move-selection-down)')

nnoremap <silent> <Plug>(pairs-copy-up) <ScriptCmd>CopyMove('copy', '-', v:count1, 'up')<CR>
nnoremap <silent> <Plug>(pairs-copy-down) <ScriptCmd>CopyMove('copy', '', v:count1, 'down')<CR>
noremap <silent> <Plug>(pairs-copy-selection-up) <ScriptCmd>CopyMoveSelectionUp('copy', v:count1)<CR>
noremap <silent> <Plug>(pairs-copy-selection-down) <ScriptCmd>CopyMoveSelectionDown('copy', v:count1)<CR>

execute pairs.Map('n', '[E', '<Plug>(pairs-copy-up)')
execute pairs.Map('n', ']E', '<Plug>(pairs-copy-down)')
execute pairs.Map('x', '[E', '<Plug>(pairs-copy-selection-up)')
execute pairs.Map('x', ']E', '<Plug>(pairs-copy-selection-down)')

# Section: Option toggling

pairs.MapFeature('b', { enable: 'PairsSetBackground(true)',
  disable: 'PairsSetBackground(false)', test: "&background == 'light'" })

pairs.MapFeature('t', { enable: '&l:colorcolumn = PairsColorColumn(false)',
  disable: '&l:colorcolumn = PairsColorColumn(true)',
  test: '!&l:colorcolumn->empty()'
})

# Adapted from phongnh/vim-toggler yoC
pairs.MapFeature('C', { enable: 'setlocal conceallevel=2',
  disable: 'setlocal conceallevel=0', test: '&conceallevel > 0' })

pairs.MapBooleanOption(['c', '-', '_'], 'cursorline', 'setlocal')
pairs.MapBooleanOption(['u', '<Bar>'], 'cursorcolumn', 'setlocal')

pairs.MapFeature('d', { enable: 'diffthis', disable: 'diffoff', test: '&diff' })

pairs.MapBooleanOption('e', 'expandtab', 'setlocal')
pairs.MapBooleanOption('I', 'incsearch', 'setlocal')
pairs.MapBooleanOption('S', 'incsearch', 'set')
pairs.MapBooleanOption('h', 'hlsearch', 'set')
pairs.MapBooleanOption('i', 'ignorecase', 'set')
pairs.MapBooleanOption('l', 'list', 'setlocal')
pairs.MapBooleanOption('n', 'number', 'setlocal')
pairs.MapBooleanOption('r', 'relativenumber', 'setlocal')
pairs.MapBooleanOption(';', 'showcmd', 'set')
pairs.MapBooleanOption('M', 'showmatch', 'set')
pairs.MapBooleanOption('s', 'spell', 'setlocal')
pairs.MapBooleanOption('w', 'wrap', 'setlocal')

pairs.MapFeature('t', { enable: 'setlocal formatoptions+=t',
  disable: 'setlocal formatoptions-=t', test: '&l:formatoptions =~# "t"' })

pairs.MapFeature('v', { enable: 'setlocal virtualedit+=all', disable: 'setlocal virtualedit-=all',
  test: '&l:virtualedit =~# "all"' })

pairs.MapFeature(['x', '+'], { enable: 'setlocal cursorline cursorcolumn',
  disable: 'setlocal nocursorline nocursorcolumn',
  test: '&l:cursorline && &l:cursorcolumn',
  after: 'PairsStatuslineRefresh()'
})

pairs.MapFeature('Y', { enable: 'syntax enable', disable: 'syntax off',
  test: 'exists("g:syntax_on")'
})

pairs.MapFeature('y', { enable: '&l:syntax = "ON"', disable: '&l:syntax = "OFF"',
  test: '&l:syntax !=# "OFF"', after: 'echo &l:syntax'
})

execute pairs.Map('n', 'yo', '<Plug>(pairs-toggle)')
execute pairs.Map('n', '[o', '<Plug>(pairs-enable)')
execute pairs.Map('n', ']o', '<Plug>(pairs-disable)')
execute pairs.Map('n', 'yo<Esc>', '<Nop>')
execute pairs.Map('n', '[o<Esc>', '<Nop>')
execute pairs.Map('n', ']o<Esc>', '<Nop>')
execute pairs.Map('n', '=s', '<Plug>(pairs-toggle)')
execute pairs.Map('n', '<s', '<Plug>(pairs-enable)')
execute pairs.Map('n', '>s', '<Plug>(pairs-disable)')
execute pairs.Map('n', '=s<Esc>', '<Nop>')
execute pairs.Map('n', '<s<Esc>', '<Nop>')
execute pairs.Map('n', '>s<Esc>', '<Nop>')

# Section: Paste

var Spaste: list<any> = null_list

def PairsRestorePaste()
  if Spaste != null_list
    &paste = Spaste[0]
    &mouse = Spaste[1]
    Spaste = null_list
  endif

  autocmd! pairs_paste
enddef

def PairsSetupPaste()
  Spaste = [&paste, &mouse]

  set paste
  set mouse=

  augroup pairs_paste
    autocmd!
    autocmd InsertLeave * <ScriptCmd>PairsRestorePaste()
    if exists('##ModeChanged')
      autocmd ModeChanged *:n <ScriptCmd>PairsRestorePaste()
    else
      autocmd CursorHold,CursorMoved * <ScriptCmd>PairsRestorePaste()
    endif
  augroup END
enddef

nmap <script><silent> <Plug>(pairs-paste) <ScriptCmd>PairsSetupPaste()<CR>

nmap <script><silent> <Plug>(pairs-enable)p <ScriptCmd>PairsSetupPaste()<CR>O
nmap <script><silent> <Plug>(pairs-disable)p <ScriptCmd>PairsSetupPaste()<CR>o
nmap <script><silent> <Plug>(pairs-toggle)p <ScriptCmd>PairsSetupPaste()<CR>0C

# Section: Put

def Putline(how: string, map: string)
  var [body, type] = [getreg(v:register), getregtype(v:register)]
  if type ==# 'V'
    execute 'normal! "' .. v:register .. how
  else
    setreg(v:register, body, 'l')
    execute 'normal! "' .. v:register .. how
    setreg(v:register, body, type)
  endif

  silent! call repeat#set("\<Plug>(pairs-put-" .. map .. ")")
enddef

nnoremap <silent> <Plug>(pairs-put-above) <ScriptCmd>Putline('[p', 'above')<CR>
nnoremap <silent> <Plug>(pairs-put-below) <ScriptCmd>Putline(']p', 'below')<CR>
nnoremap <silent> <Plug>(pairs-put-above-rightward) <ScriptCmd>Putline(v:count1 .. '[p', 'Above')<CR>>']
nnoremap <silent> <Plug>(pairs-put-below-rightward) <ScriptCmd>Putline(v:count1 .. ']p', 'Below')<CR>>']
nnoremap <silent> <Plug>(pairs-put-above-leftward) <ScriptCmd>Putline(v:count1 .. '[p', 'Above')<CR><']
nnoremap <silent> <Plug>(pairs-put-below-leftward) <ScriptCmd>Putline(v:count1 .. ']p', 'Below')<CR><']
nnoremap <silent> <Plug>(pairs-put-above-reformat) <ScriptCmd>Putline(v:count1 .. '[p', 'Above')<CR>=']
nnoremap <silent> <Plug>(pairs-put-below-reformat) <ScriptCmd>Putline(v:count1 .. ']p', 'Below')<CR>=']

execute pairs.Map('n', '[p', '<Plug>(pairs-put-above)')
execute pairs.Map('n', ']p', '<Plug>(pairs-put-below)')
execute pairs.Map('n', '[P', '<Plug>(pairs-put-above)')
execute pairs.Map('n', ']P', '<Plug>(pairs-put-below)')

execute pairs.Map('n', '>P', "<Plug>(pairs-put-above-rightward)")
execute pairs.Map('n', '>p', "<Plug>(pairs-put-below-rightward)")
execute pairs.Map('n', '<P', "<Plug>(pairs-put-above-leftward)")
execute pairs.Map('n', '<p', "<Plug>(pairs-put-below-leftward)")
execute pairs.Map('n', '=P', "<Plug>(pairs-put-above-reformat)")
execute pairs.Map('n', '=p', "<Plug>(pairs-put-below-reformat)")

# Section: Encoding and decoding

pairs.MapTransform('[y', 'String', 'Encode')
pairs.MapTransform(']y', 'String', 'Decode')
pairs.MapTransform('[C', 'String', 'Encode')
pairs.MapTransform(']C', 'String', 'Decode')
pairs.MapTransform('[u', 'Url', 'Encode')
pairs.MapTransform(']u', 'Url', 'Decode')
pairs.MapTransform('[x', 'Xml', 'Encode')
pairs.MapTransform(']x', 'Xml', 'Decode')

# vim:set sw=2 sts=2:
defcompile
