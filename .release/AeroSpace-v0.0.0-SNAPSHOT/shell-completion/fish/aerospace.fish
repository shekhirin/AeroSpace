function _aerospace_55
    set 1 $argv[1]
    aerospace list-workspaces --monitor all --empty no
end

function _aerospace_56
    set 1 $argv[1]
    true
end

function _aerospace_44
    set 1 $argv[1]
    aerospace list-apps --format '%{app-pid}%{tab}%{app-name}'
end

function _aerospace_50
    set 1 $argv[1]
    aerospace config --get mode --keys | xargs -I{} aerospace config --get mode.{}.binding --keys
end

function _aerospace_57
    set 1 $argv[1]
    aerospace list-windows --all --format '%{window-id}%{tab}%{app-name} - %{window-title}'
end

function _aerospace_54
    set 1 $argv[1]
    aerospace config --major-keys
end

function _aerospace_18
    set 1 $argv[1]
    aerospace config --get mode --keys
end

function _aerospace_53
    set 1 $argv[1]
    aerospace list-apps --format '%{app-bundle-id}%{tab}%{app-name}'
end

function _aerospace_40
    set 1 $argv[1]
    aerospace list-monitors --format '%{monitor-id}%{tab}%{monitor-name}'
end

function _aerospace_subword_cmd_0
    true
end

function _aerospace_subword_1
    set mode $argv[1]
    set word $argv[2]

    set --local literals "-" "+"

    set --local descriptions

    set --local literal_transitions
    set literal_transitions[1] "set inputs 1 2; set tos 2 2"

    set --local match_anything_transitions_from 1 2
    set --local match_anything_transitions_to 3 3

    set --local state 1
    set --local char_index 1
    set --local matched 0
    while true
        if test $char_index -gt (string length -- "$word")
            set matched 1
            break
        end

        set --local subword (string sub --start=$char_index -- "$word")

        if set --query literal_transitions[$state] && test -n $literal_transitions[$state]
            set --local --erase inputs
            set --local --erase tos
            eval $literal_transitions[$state]

            set --local literal_matched 0
            for literal_id in (seq 1 (count $literals))
                set --local literal $literals[$literal_id]
                set --local literal_len (string length -- "$literal")
                set --local subword_slice (string sub --end=$literal_len -- "$subword")
                if test $subword_slice = $literal
                    set --local index (contains --index -- $literal_id $inputs)
                    set state $tos[$index]
                    set char_index (math $char_index + $literal_len)
                    set literal_matched 1
                    break
                end
            end
            if test $literal_matched -ne 0
                continue
            end
        end

        if set --query match_anything_transitions_from[$state] && test -n $match_anything_transitions_from[$state]
            set --local index (contains --index -- $state $match_anything_transitions_from)
            set state $match_anything_transitions_to[$index]
            set --local matched 1
            break
        end

        break
    end

    if test $mode = matches
        return (math 1 - $matched)
    end


    set --local unmatched_suffix (string sub --start=$char_index -- $word)

    set --local matched_prefix
    if test $char_index -eq 1
        set matched_prefix ""
    else
        set matched_prefix (string sub --end=(math $char_index - 1) -- "$word")
    end
    if set --query literal_transitions[$state] && test -n $literal_transitions[$state]
        set --local --erase inputs
        set --local --erase tos
        eval $literal_transitions[$state]
        for literal_id in $inputs
            set --local unmatched_suffix_len (string length -- $unmatched_suffix)
            if test $unmatched_suffix_len -gt 0
                set --local literal $literals[$literal_id]
                set --local slice (string sub --end=$unmatched_suffix_len -- $literal)
                if test "$slice" != "$unmatched_suffix"
                    continue
                end
            end
            if test -n $descriptions[$literal_id]
                printf '%s%s\t%s\n' $matched_prefix $literals[$literal_id] $descriptions[$literal_id]
            else
                printf '%s%s\n' $matched_prefix $literals[$literal_id]
            end
        end
    end

    set command_states 1 2
    set command_ids 0 0
    if contains $state $command_states
        set --local index (contains --index $state $command_states)
        set --local function_id $command_ids[$index]
        set --local function_name _aerospace_subword_cmd_$function_id
        set --local --erase inputs
        set --local --erase tos
        $function_name "$matched_prefix" | while read --local line
            printf '%s%s\n' $matched_prefix $line
        end
    end

    return 0
end


function _aerospace
    set COMP_LINE (commandline --cut-at-cursor)

    set COMP_WORDS
    echo $COMP_LINE | read --tokenize --array COMP_WORDS
    if string match --quiet --regex '.*\s$' $COMP_LINE
        set COMP_CWORD (math (count $COMP_WORDS) + 1)
    else
        set COMP_CWORD (count $COMP_WORDS)
    end

    set --local literals "move-mouse" "--count" "-v" "smart" "macos-native-fullscreen" "mute-toggle" "height" "toggle" "all-monitors-outer-frame" "h_accordion" "--stdin" "all" "--window-id" "monitor-force-center" "list-apps" "flatten-workspace-tree" "mode" "width" "summon-workspace" "focus-back-and-forth" "list-monitors" "h_tiles" "prev" "window-force-center" "trigger-binding" "-h" "move-node-to-workspace" "wrap-around-the-workspace" "enable" "--ignore-floating" "--visible" "close-all-windows-but-current" "--help" "--macos-native-hidden" "off" "move-workspace-to-monitor" "--boundaries" "set" "workspace-back-and-forth" "--quit-if-last-window" "window-lazy-center" "workspace" "--major-keys" "accordion" "--focused" "tiling" "--app-bundle-id" "--mouse" "balance-sizes" "opposite" "on" "--auto-back-and-forth" "--version" "--json" "join-with" "reload-config" "--workspace" "floating" "--swap-focus" "--mode" "--boundaries-action" "resize" "visible" "close" "--no-stdin" "up" "layout" "--fail-if-noop" "list-exec-env-vars" "fail" "--monitor" "--focus-follows-window" "split" "--pid" "mute-on" "v_tiles" "monitor-lazy-center" "--keys" "wrap-around-all-monitors" "--wrap-around" "horizontal" "create-implicit-container" "config" "--no-outer-gaps" "focused" "mute-off" "--all-keys" "--all" "left" "right" "swap" "--config-path" "--get" "--empty" "tiles" "dfs-next" "--no-gui" "smart-opposite" "--format" "list-modes" "--dry-run" "move-node-to-monitor" "dfs-prev" "move" "focus" "down" "list-workspaces" "volume" "no" "stop" "debug-windows" "macos-native-minimize" "list-windows" "mouse" "next" "--dfs-index" "fullscreen" "focus-monitor" "--current" "v_accordion" "vertical"

    set --local descriptions

    set --local literal_transitions
    set literal_transitions[1] "set inputs 1 3 55 56 36 5 39 62 91 64 100 15 42 67 69 16 102 73 21 17 20 104 105 19 25 26 107 27 108 111 112 113 29 49 83 32 53 117 33 118; set tos 113 11 123 124 125 68 11 89 9 70 126 63 107 127 11 6 128 129 78 46 11 88 74 121 55 11 130 131 99 25 25 18 132 6 10 81 11 133 11 82"
    set literal_transitions[3] "set inputs 31 2 94 99 54 71; set tos 92 3 92 2 3 93"
    set literal_transitions[4] "set inputs 18 4 7 98; set tos 5 5 5 5"
    set literal_transitions[6] "set inputs 57; set tos 7"
    set literal_transitions[9] "set inputs 106 13 96 59 66 89 90 80 103; set tos 80 8 80 9 80 80 80 9 80"
    set literal_transitions[10] "set inputs 87 43 78 54 93 92; set tos 11 11 12 12 13 11"
    set literal_transitions[12] "set inputs 54 93 78; set tos 12 13 12"
    set literal_transitions[14] "set inputs 13 68; set tos 15 11"
    set literal_transitions[16] "set inputs 99 2 54; set tos 17 11 11"
    set literal_transitions[18] "set inputs 74 2 57 99 45 88 47 54 71; set tos 19 20 21 22 16 16 23 20 24"
    set literal_transitions[20] "set inputs 74 2 57 99 45 88 47 54 71; set tos 19 50 21 51 16 16 23 50 24"
    set literal_transitions[21] "set inputs 63 85; set tos 111 111"
    set literal_transitions[24] "set inputs 12 114 85; set tos 106 106 106"
    set literal_transitions[25] "set inputs 13; set tos 15"
    set literal_transitions[26] "set inputs 9 42; set tos 27 27"
    set literal_transitions[27] "set inputs 13 37 61; set tos 28 26 112"
    set literal_transitions[31] "set inputs 65 80 11; set tos 11 11 11"
    set literal_transitions[33] "set inputs 13 84 68; set tos 32 33 33"
    set literal_transitions[34] "set inputs 31 2 109 94 99 54; set tos 34 35 35 34 36 35"
    set literal_transitions[35] "set inputs 31 2 94 99 54; set tos 34 35 34 36 35"
    set literal_transitions[38] "set inputs 84 68 13 51; set tos 38 38 37 33"
    set literal_transitions[39] "set inputs 35 51; set tos 40 40"
    set literal_transitions[40] "set inputs 68; set tos 11"
    set literal_transitions[41] "set inputs 9 42; set tos 42 42"
    set literal_transitions[42] "set inputs 37 61 89 90 106 30 66; set tos 41 104 73 73 73 42 73"
    set literal_transitions[43] "set inputs 13 68; set tos 44 43"
    set literal_transitions[45] "set inputs 60; set tos 46"
    set literal_transitions[48] "set inputs 115 13 23 106 66 89 90 68 80 72; set tos 86 47 86 86 86 86 86 48 48 48"
    set literal_transitions[49] "set inputs 97; set tos 11"
    set literal_transitions[50] "set inputs 74 2 47 57 54 71 99; set tos 19 50 23 21 50 24 51"
    set literal_transitions[52] "set inputs 89 90 106 23 115 66; set tos 54 54 54 54 54 54"
    set literal_transitions[53] "set inputs 80; set tos 11"
    set literal_transitions[54] "set inputs 80; set tos 11"
    set literal_transitions[55] "set inputs 60; set tos 29"
    set literal_transitions[57] "set inputs 84 68 13 51; set tos 57 38 56 33"
    set literal_transitions[58] "set inputs 110 28 70 79; set tos 59 59 59 59"
    set literal_transitions[59] "set inputs 61 30; set tos 58 59"
    set literal_transitions[60] "set inputs 54 78; set tos 60 60"
    set literal_transitions[63] "set inputs 2 99 54 34; set tos 63 62 63 94"
    set literal_transitions[65] "set inputs 81 121 50; set tos 25 25 25"
    set literal_transitions[66] "set inputs 13 68 72; set tos 67 66 66"
    set literal_transitions[68] "set inputs 68 13 35 51; set tos 68 69 43 43"
    set literal_transitions[70] "set inputs 13 40; set tos 71 70"
    set literal_transitions[72] "set inputs 110 28 70 79; set tos 73 73 73 73"
    set literal_transitions[73] "set inputs 37 61 30; set tos 95 72 73"
    set literal_transitions[74] "set inputs 13 96 30 66 37 61 89 90 106 116 103; set tos 15 59 75 73 41 76 73 73 73 17 59"
    set literal_transitions[75] "set inputs 106 96 30 66 37 61 89 90 103; set tos 73 59 75 73 41 76 73 73 59"
    set literal_transitions[76] "set inputs 110 28 70 79; set tos 75 75 75 75"
    set literal_transitions[77] "set inputs 109 2 99 54 48 45; set tos 78 78 79 78 77 77"
    set literal_transitions[78] "set inputs 2 99 54 48 45; set tos 78 79 78 77 77"
    set literal_transitions[80] "set inputs 13 59 80; set tos 98 80 80"
    set literal_transitions[81] "set inputs 40; set tos 11"
    set literal_transitions[82] "set inputs 115 106 23 66 89 90 80; set tos 54 54 54 54 54 54 84"
    set literal_transitions[84] "set inputs 89 90 115 106 23 66; set tos 54 54 54 54 54 54"
    set literal_transitions[86] "set inputs 68 13 80 72; set tos 86 85 86 86"
    set literal_transitions[87] "set inputs 9 42; set tos 88 88"
    set literal_transitions[88] "set inputs 37 61 89 90 13 106 66; set tos 87 102 27 27 103 27 27"
    set literal_transitions[89] "set inputs 18 4 7 13 98; set tos 5 5 5 90 5"
    set literal_transitions[91] "set inputs 2 94 99 45 31 88 54 71; set tos 3 92 2 16 92 16 3 93"
    set literal_transitions[92] "set inputs 31 2 109 94 99 54 71; set tos 92 3 3 92 2 3 93"
    set literal_transitions[93] "set inputs 12 114 85; set tos 122 122 122"
    set literal_transitions[94] "set inputs 109 2 99 54 34; set tos 63 63 62 63 94"
    set literal_transitions[95] "set inputs 9 42; set tos 73 73"
    set literal_transitions[97] "set inputs 89 90 106 66; set tos 11 11 11 11"
    set literal_transitions[99] "set inputs 97 38 66 106 6 75 86; set tos 101 100 49 49 49 49 49"
    set literal_transitions[101] "set inputs 66 38 6 75 106 86; set tos 49 100 49 49 49 49"
    set literal_transitions[102] "set inputs 70 82 110; set tos 88 88 88"
    set literal_transitions[104] "set inputs 110 28 70 79; set tos 42 42 42 42"
    set literal_transitions[105] "set inputs 11 65 80 72; set tos 105 105 105 105"
    set literal_transitions[106] "set inputs 12 2 74 114 57 99 85 47 54 71; set tos 106 50 19 106 21 51 106 23 50 24"
    set literal_transitions[107] "set inputs 11 115 65 23 52 68 80; set tos 108 31 108 31 110 110 108"
    set literal_transitions[108] "set inputs 23 115; set tos 31 31"
    set literal_transitions[109] "set inputs 52 68; set tos 109 109"
    set literal_transitions[110] "set inputs 52 68; set tos 110 110"
    set literal_transitions[111] "set inputs 74 2 63 57 99 47 54 85 71; set tos 19 50 111 21 51 23 50 111 24"
    set literal_transitions[112] "set inputs 70 82 110; set tos 27 27 27"
    set literal_transitions[113] "set inputs 68 41 14 24 77; set tos 114 40 40 40 40"
    set literal_transitions[114] "set inputs 77 41 14 24; set tos 40 40 40 40"
    set literal_transitions[116] "set inputs 10 22 58 81 95 46 76 44 120 121; set tos 136 136 136 136 136 136 136 136 136 136"
    set literal_transitions[118] "set inputs 84 68 13 35 51; set tos 57 38 56 14 33"
    set literal_transitions[120] "set inputs 68 13 72; set tos 120 119 120"
    set literal_transitions[121] "set inputs 68; set tos 61"
    set literal_transitions[122] "set inputs 12 2 114 94 99 31 54 85; set tos 122 35 122 34 36 34 35 122"
    set literal_transitions[123] "set inputs 89 90 13 106 66; set tos 11 11 96 11 11"
    set literal_transitions[124] "set inputs 97 101; set tos 124 124"
    set literal_transitions[125] "set inputs 115 106 23 66 89 90 80; set tos 54 54 54 54 54 54 52"
    set literal_transitions[126] "set inputs 119 2 54; set tos 126 126 126"
    set literal_transitions[127] "set inputs 10 95 13 22 58 81 46 76 44 120 121; set tos 136 136 115 136 136 136 136 136 136 136 136"
    set literal_transitions[128] "set inputs 115 13 23 106 66 89 90 68 80 72; set tos 86 138 86 86 86 86 86 128 48 128"
    set literal_transitions[129] "set inputs 50 13 81 121; set tos 25 64 25 25"
    set literal_transitions[130] "set inputs 2 94 99 45 31 88 54 71; set tos 91 92 139 16 92 16 91 93"
    set literal_transitions[131] "set inputs 11 65 13 23 115 68 80 72; set tos 134 134 119 105 105 120 134 131"
    set literal_transitions[132] "set inputs 68 35 8 51; set tos 39 40 11 40"
    set literal_transitions[133] "set inputs 84 68 13 35 51; set tos 57 135 117 14 33"
    set literal_transitions[134] "set inputs 11 115 65 23 80 72; set tos 134 105 134 105 134 134"
    set literal_transitions[135] "set inputs 84 68 13 35 51; set tos 38 38 37 14 33"
    set literal_transitions[136] "set inputs 10 22 58 81 95 46 76 44 120 121; set tos 136 136 136 136 136 136 136 136 136 136"
    set literal_transitions[137] "set inputs 68 13 72; set tos 66 67 66"

    set --local match_anything_transitions_from 7 24 131 37 128 125 122 44 79 96 47 106 46 85 119 83 21 29 82 36 56 111 28 69 103 139 64 55 53 61 138 137 117 51 2 67 22 52 71 93 120 100 62 19 107 32 98 121 15 30 8 90 23 13 110 17 115
    set --local match_anything_transitions_to 11 106 66 38 137 53 122 43 78 97 48 106 11 86 120 83 111 30 83 35 57 111 27 68 88 91 65 45 53 40 128 137 118 50 3 66 20 53 70 122 66 49 63 50 109 33 80 40 11 11 9 4 50 60 109 11 116
    set subword_transitions[5] "set subword_ids 1; set tos 25"

    set --local state 1
    set --local word_index 2
    while test $word_index -lt $COMP_CWORD
        set --local -- word $COMP_WORDS[$word_index]

        if set --query literal_transitions[$state] && test -n $literal_transitions[$state]
            set --local --erase inputs
            set --local --erase tos
            eval $literal_transitions[$state]

            if contains -- $word $literals
                set --local literal_matched 0
                for literal_id in (seq 1 (count $literals))
                    if test $literals[$literal_id] = $word
                        set --local index (contains --index -- $literal_id $inputs)
                        set state $tos[$index]
                        set word_index (math $word_index + 1)
                        set literal_matched 1
                        break
                    end
                end
                if test $literal_matched -ne 0
                    continue
                end
            end
        end

        if set --query subword_transitions[$state] && test -n $subword_transitions[$state]
            set --local --erase subword_ids
            set --local --erase tos
            eval $subword_transitions[$state]

            set --local subword_matched 0
            for subword_id in $subword_ids
                if _aerospace_subword_$subword_id matches "$word"
                    set subword_matched 1
                    set state $tos[$subword_id]
                    set word_index (math $word_index + 1)
                    break
                end
            end
            if test $subword_matched -ne 0
                continue
            end
        end

        if set --query match_anything_transitions_from[$state] && test -n $match_anything_transitions_from[$state]
            set --local index (contains --index -- $state $match_anything_transitions_from)
            set state $match_anything_transitions_to[$index]
            set word_index (math $word_index + 1)
            continue
        end

        return 1
    end

    if set --query literal_transitions[$state] && test -n $literal_transitions[$state]
        set --local --erase inputs
        set --local --erase tos
        eval $literal_transitions[$state]
        for literal_id in $inputs
            if test -n $descriptions[$literal_id]
                printf '%s\t%s\n' $literals[$literal_id] $descriptions[$literal_id]
            else
                printf '%s\n' $literals[$literal_id]
            end
        end
    end


    if set --query subword_transitions[$state] && test -n $subword_transitions[$state]
        set --local --erase subword_ids
        set --local --erase tos
        eval $subword_transitions[$state]

        for subword_id in $subword_ids
            set --local function_name _aerospace_subword_$subword_id
            $function_name complete "$COMP_WORDS[$COMP_CWORD]"
        end
    end

    set command_states 7 64 55 24 53 61 138 137 117 131 37 51 128 125 2 122 44 79 96 67 47 22 52 71 106 46 85 119 83 93 120 100 21 62 29 19 107 32 82 98 121 15 30 36 90 8 23 56 13 110 111 69 28 17 103 139 115
    set command_ids 55 57 50 40 56 55 57 56 57 55 57 56 56 56 56 40 57 56 57 57 57 56 56 57 40 18 57 57 56 40 55 56 55 56 18 44 55 57 56 57 55 57 50 56 57 57 53 57 54 55 55 57 57 56 57 56 57
    if contains $state $command_states
        set --local index (contains --index $state $command_states)
        set --local function_id $command_ids[$index]
        set --local function_name _aerospace_$function_id
        set --local --erase inputs
        set --local --erase tos
        $function_name "$COMP_WORDS[$COMP_CWORD]"
    end

    return 0
end

complete --command aerospace --no-files --arguments "(_aerospace)"
