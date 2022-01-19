"==============================================================================
"            __ __ ____  ____ ______       ______   ___ ___________ 
"           |  |  |    \|    |      |     |      | /  _] ___/      |
"           |  |  |  _  ||  ||      |_____|      |/  [(   \_|      |
"           |  |  |  |  ||  ||_|  |_|     |_|  |_|    _]__  |_|  |_|
"           |  :  |  |  ||  |  |  | |_____| |  | |   [_/  \ | |  |  
"           |     |  |  ||  |  |  |         |  | |     \    | |  |  
"            \__,_|__|__|____| |__|         |__| |_____|\___| |__|  
"                                                                 
"                                                                 
" Author:       Matthew Bennett
" Version:      0.1.0
" License:      Same as Vim's (see :help license)
"
"
"================================== SETUP =====================================

"{{{---------------------------------------------------------------------------
if exists("g:unit_test") || &cp || v:version < 700
    finish
endif
let g:unit_test = 1
"}}}---------------------------------------------------------------------------
"

"----------------------------- Helper functions -------------------------------
"{{{---------------------------------------------------------------------------
"{{{- string2list -------------------------------------------------------------
function! s:string2list(str)
    " e.g. 'vim' -> ['v', 'i', 'm']
    let str = a:str
    if str ==# '.'
        let str = getline('.')
    endif
    return split(str, '\zs')
endfunction
"}}}---------------------------------------------------------------------------

"{{{- extract_substring -------------------------------------------------------
function! s:extract_substring(str, c1, c2)
    " remove the characters ranging from <c1> to <c2> (inclusive) from <str>
    " returns: the original with characters removed
    "          the removed characters as a string
    let [c1, c2] = [a:c1, a:c2]
    let chars = s:string2list(a:str)
    " convert negative indices to positive
    let removed = remove(chars, c1-1, c2-1)
    return [join(chars, ''), join(removed, '')]
endfunction
"}}}---------------------------------------------------------------------------

"{{{- extract_substrings ------------------------------------------------------
function! s:extract_substrings(str, deletion_ranges)
    let removed = []
    let result = a:str
    let offset = 0
    for [c1, c2] in a:deletion_ranges
        if c1 < 0
            let c1 = len(a:str)-abs(c1)+1
        endif
        if c2 < 0
            let c2 = len(a:str)-abs(c2)+1
        endif
        let [result, rm] = s:extract_substring(result, c1+offset, c2+offset)
        let offset -= len(rm)
        call add(removed, rm)
    endfor
    return [result, removed]
endfunction
"}}}---------------------------------------------------------------------------
"}}}---------------------------------------------------------------------------

"----------------------------- Everything else --------------------------------
function! s:create_results_buffer()
    silent execute 'split results.vim'
    setlocal buftype=nofile
    setlocal bufhidden=hide
    setlocal noswapfile
    setlocal nobuflisted
endfunction

function! s:open_new_test_buffers(path, test_id)
    let suffix = string(a:test_id+1)
    for i in range(2)
        if i == 0
            execute 'edit '.a:path.'/expected_'.suffix
        else
            execute 'edit '.a:path.'/test_'.suffix
        endif
        setlocal buftype=nofile
        setlocal bufhidden=hide
        setlocal noswapfile
        setlocal nobuflisted
    endfor
    return [a:path.'/expected_'.suffix, a:path.'/test_'.suffix]
endfunction

function! s:close_test_buffers(test_buffer, expected_buffer)
    execute 'bwipeout '.a:test_buffer
    execute 'bwipeout '.a:expected_buffer
endfunction

function! s:run_command(str)
    silent execute "normal ".a:str
endfunction

function! s:run_commands(commands)
    for command in a:commands
        if len(command) > 0
            call s:run_command(command)
        endif
    endfor
endfunction

function! s:find_line_diff(b1_line, b2_line)
    let b1 = s:string2list(a:b1_line)
    let b2 = s:string2list(a:b2_line)
    for i in range(min([len(b1), len(b2)]))
        if b1[i] !=# b2[i]
            return i+1
        endif
    endfor
    return min([len(b1), len(b2)])+1
endfunction

function! s:compare_buffers(b1, b2)
    let b1_nlines = getbufinfo(a:b1)['variables']['linecount']
    let b2_nlines = getbufinfo(a:b2)['variables']['linecount']
    if b1_nlines == b2_nlines
        let diff = [0, 0]
        for line in range(1, b1_nlines)
            let b1_line = getbufline(a:b1, line)[0]
            let b2_line = getbufline(a:b2, line)[0]
            if b1_line != b2_line
                let diff[0] = line
                let diff[1] = s:find_line_diff(b1_line, b2_line)
                break
            endif
        endfor
        return diff
    else
        return [-1, -1]
    endif
endfunction

function! s:print_test_results(expected_buffer, test_buffer, position, test_id)
    if a:position[0] == 0 && a:position[1] == 0
        call appendbufline('results.vim', '$', 'Test '.string(a:test_id+1).' Passed!')
    elseif a:position[0] > 0 && a:position[1] > 0
        call appendbufline('results.vim', '$', 'Test '.string(a:test_id+1).' Failed')
        call appendbufline('results.vim', '$', '')
        call appendbufline('results.vim', '$', 'Expected:')
        call appendbufline('results.vim', '$', '')
        for i in range(getbufinfo(a:expected_buffer)['variables']['linecount'])
            call appendbufline('results.vim', '$', getbufline(a:expected_buffer, i+1))
        endfor
        call appendbufline('results.vim', '$', '')
        call appendbufline('results.vim', '$', 'Actual:')
        call appendbufline('results.vim', '$', '')
        for i in range(getbufinfo(a:test_buffer)['variables']['linecount'])
            call appendbufline('results.vim', '$', getbufline(a:test_buffer, i+1))
        endfor
    else
        call appendbufline('results.vim', '$', 'Test '.string(a:test_id+1).' Failed')
        call appendbufline('results.vim', '$', '    Different number of lines')
    endif
    call appendbufline('results.vim', '$', '')
endfunction

function! Run_tests(path)
    if a:path =~ '.*\/$'
        let [_, path] = s:extract_substrings(a:path, [[1, -2]])
        let path = path[0]
    else
        let path = a:path
    endif
    execute 'source '.path.'/tests.vim'
    call s:create_results_buffer()
    for test_id in range(len(g:tests))
        let [expected_buffer, test_buffer] = s:open_new_test_buffers(path, test_id)
        call s:run_commands(g:before)
        call s:run_commands(g:tests[test_id])
        call s:run_commands(g:after)
        let [l, c] = s:compare_buffers(expected_buffer, test_buffer)
        call s:print_test_results(expected_buffer, test_buffer, [l, c], test_id)
        call s:close_test_buffers(test_buffer, expected_buffer)
    endfor
    split results.vim
endfunction

