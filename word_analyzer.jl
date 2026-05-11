#! /bin/env julial

# This program processes a word frequency file.
# It supports filtering, prefix tree analysis, prefix-free extraction,
# weighted random sampling, and an interactive word game.

using Printf
using Crayons
using HTTP
using JSON

"""
    TrieNode
"""
mutable struct TrieNode
    children::Dict{Char, TrieNode}
    weight::Int128
    w_prefix_free::Int128
    f_prefix_free_leaf::Bool
    char::Char

    TrieNode(c::Char='\0') = new(Dict{Char, TrieNode}(), 0, 0, false, c)
end

function insert!(root::TrieNode, word::AbstractString, weight::Int128)
    node = root
    for char in word
        if !haskey(node.children, char)
            node.children[char] = TrieNode(char)
        end
        node = node.children[char]
    end
    node.weight = weight
end

function compute_prefix_free!(node::TrieNode)
    if isempty(node.children)
        node.w_prefix_free = node.weight
        node.f_prefix_free_leaf = true 
        return node.w_prefix_free
    end
    children_sum = sum(compute_prefix_free!(child) for child in values(node.children); init=Int128(0))
    if node.weight >= children_sum
        node.w_prefix_free = node.weight
        node.f_prefix_free_leaf = true
    else
        node.w_prefix_free = children_sum
        node.f_prefix_free_leaf = false
    end
    return node.w_prefix_free
end

function extract_words!(node::TrieNode, current_prefix::String, words_list::Vector{Tuple{String, Int128}})
    new_prefix = node.char == '\0' ? "" : current_prefix * node.char
    if node.f_prefix_free_leaf
        node.weight > 0 && push!(words_list, (new_prefix, node.weight))
        return
    end
    for char in sort(collect(keys(node.children)))
        extract_words!(node.children[char], new_prefix, words_list)
    end
end

function get_total_frequency(file_path::String)
    total = Int128(0)
    if !isfile(file_path) return total end
    for line in eachline(file_path)
        parts = split(line)
        length(parts) >= 2 && try total += parse(Int128, parts[2]) catch end
    end
    return total
end

function prefix_free_analysis(input_file::String)
    root = TrieNode()
    if !isfile(input_file); println(stderr, Crayon(foreground=:red)("Error: Filtered file missing.")); return 1; end
    println("Building trie..."); for line in eachline(input_file); p = split(line); insert!(root, p[1], parse(Int128, p[2])); end
    println("Processing..."); compute_prefix_free!(root)
    pf_words = Tuple{String, Int128}[]; extract_words!(root, "", pf_words)
    mkpath("output")
    sort!(pf_words, by=x->x[1]); open(f->(for (w,c) in pf_words; println(f,w,"\t",c) end), joinpath("output","prefix_free_words.txt"), "w")
    sort!(pf_words, by=x->x[2], rev=true); open(f->(for (w,c) in pf_words; println(f,w,"\t",c) end), joinpath("output","prefix_free_words_count.txt"), "w")
    println("Totals: Original: $(get_total_frequency("count_1w.txt")) | Preprocessed: $(get_total_frequency(input_file)) | Prefix-Free: $(sum(x->x[2], pf_words; init=Int128(0)))")
    return 0
end

function random_word(file_path::String)
    target = get_random_target(file_path)
    target !== nothing && println("Randomly selected word: ", Crayon(bold=true, foreground=:green)(target))
    return 0
end

function get_random_target(file_path::String)
    if !isfile(file_path) return nothing end
    words = String[]; freqs = Int128[]; total = Int128(0)
    for line in eachline(file_path); p = split(line); length(p)>=2 && (push!(words,p[1]); f=parse(Int128,p[2]); push!(freqs,f); total+=f) end
    r = rand() * Float64(total); cum = 0.0; for i in 1:length(words); cum += Float64(freqs[i]); r <= cum && return words[i] end
    return words[end]
end

"""
    play_game(input_file, pf_file)

Runs the interactive word guessing game using basic input.
"""
function play_game(pf_file::String)
    valid_json = "output/valid_words.json"
    target = get_random_target(pf_file)
    if target === nothing
        println(stderr, Crayon(foreground=:red)("Error: Prefix-free list not found. Run 'prefix_free' first."))
        return 1
    end

    if !isfile(valid_json)
        println(stderr, Crayon(foreground=:red)("Error: $valid_json not found. Run 'valid_words' first."))
        return 1
    end

    println("Loading dictionary for validation...")
    dict = Set(JSON.parsefile(valid_json))
    println("Dictionary loaded ($(length(dict)) words).")

    bold = Crayon(bold=true)
    cyan = Crayon(foreground=:cyan)
    green_cr = Crayon(foreground=:green)
    yellow_cr = Crayon(foreground=:yellow)
    
    println(bold(cyan("\n=== Welcome to Word Analyzer Play! ===")))
    println("I have chosen a word. Try to guess it!\n")

    history = Vector{Vector{Tuple{Char, Symbol}}}() # Display history
    target_chars = collect(target)
    target_len = length(target_chars)
    
    try
        while true
            print("Enter your guess: ")
            flush(stdout)
            raw_guess = readline()
            
            # EOF (Ctrl-D) returns empty string if no input
            if isempty(raw_guess) && eof(stdin)
                println("\nGame exited.")
                break
            end
            
            guess = lowercase(strip(raw_guess))
            if isempty(guess) continue end
            
            if !(guess in dict)
                println(Crayon(foreground=:red)("Word not in dictionary. Try again."))
                continue
            end
            
            # Calculate feedback
            guess_chars = collect(guess)
            guess_len = length(guess_chars)
            feedback = fill(:none, guess_len)
            target_used = fill(false, target_len)
            
            # 1st pass: Matches (Green)
            for i in 1:min(guess_len, target_len)
                if guess_chars[i] == target_chars[i]
                    feedback[i] = :match
                    target_used[i] = true
                end
            end
            
            # 2nd pass: Partial Matches (Yellow)
            for i in 1:guess_len
                if feedback[i] != :match
                    for j in 1:target_len
                        if !target_used[j] && guess_chars[i] == target_chars[j]
                            feedback[i] = :partial
                            target_used[j] = true
                            break
                        end
                    end
                end
            end

            push!(history, [(guess_chars[i], feedback[i]) for i in 1:guess_len])
            
            println("\nGuesses so far:")
            for h in history
                for (char, status) in h
                    char_str = string(char)
                    if status == :match
                        print(green_cr(char_str))
                    elseif status == :partial
                        print(yellow_cr(char_str))
                    else
                        print(char_str)
                    end
                end
                println()
            end
            println()
            flush(stdout)

            if guess == target
                println(bold(green_cr("Congratulations! You guessed it!")))
                break
            end
        end
    catch e
        if e isa InterruptException
            println("\nGame exited.")
        else
            rethrow(e)
        end
    end
    return 0
end

function web_play_game(pf_file::String)
    valid_json = "output/valid_words.json"
    target_ref = Ref{String}(get_random_target(pf_file))
    if target_ref[] === nothing
        println(stderr, Crayon(foreground=:red)("Error: Prefix-free list not found. Run 'prefix_free' first."))
        return 1
    end

    if !isfile(valid_json)
        println(stderr, Crayon(foreground=:red)("Error: $valid_json not found. Run 'valid_words' first."))
        return 1
    end

    println("Loading dictionary for validation...")
    dict = Set(JSON.parsefile(valid_json))
    println("Dictionary loaded ($(length(dict)) words).")

    host = "127.0.0.1"
    port = 8080
    
    html_content = read("index.html", String) # Load from file directly

    history = Vector{Vector{Any}}()
    useless_letters = Set{Char}()
    router = HTTP.Router()
    
    HTTP.register!(router, "GET", "/", req -> HTTP.Response(200, ["Content-Type" => "text/html"], body=html_content))
    
    HTTP.register!(router, "POST", "/guess", req -> begin
        data = JSON.parse(String(req.body))
        guess = lowercase(strip(get(data, "guess", "")))
        if !(guess in dict)
            return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(Dict("error" => "Word not in dictionary")))
        end
        
        target = target_ref[]
        t_chars = collect(target); t_len = length(t_chars)
        g_chars = collect(guess); g_len = length(g_chars)
        fb = fill("none", g_len); used = fill(false, t_len)
        
        for i in 1:min(g_len, t_len)
            if g_chars[i] == t_chars[i]; fb[i] = "match"; used[i] = true end
        end
        for i in 1:g_len
            if fb[i] != "match"
                found = false
                for j in 1:t_len
                    if !used[j] && g_chars[i] == t_chars[j]
                        fb[i] = "partial"; used[j] = true; found = true; break
                    end
                end
                !found && !(g_chars[i] in t_chars) && push!(useless_letters, g_chars[i])
            end
        end
        push!(history, [Dict("char" => string(g_chars[i]), "status" => fb[i]) for i in 1:g_len])
        return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(Dict("history" => history, "victory" => (guess == target), "useless" => collect(useless_letters))))
    end)
    
    HTTP.register!(router, "POST", "/reveal", req -> HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(Dict("target" => target_ref[]))))
    
    HTTP.register!(router, "POST", "/restart", req -> (target_ref[] = get_random_target(pf_file); empty!(history); empty!(useless_letters); HTTP.Response(200, body="OK")))

    println("Web interface running at: ", Crayon(bold=true, foreground=:cyan)("http://$host:$port"))
    try HTTP.serve(router, host, port) catch e; e isa InterruptException ? println("\nStopping...") : rethrow(e) end
    return 0
end


function web_play_game(pf_file::String)
    valid_json = "output/valid_words.json"
    target_ref = Ref{String}(get_random_target(pf_file))
    if target_ref[] === nothing
        println(stderr, Crayon(foreground=:red)("Error: Prefix-free list not found. Run 'prefix_free' first."))
        return 1
    end

    if !isfile(valid_json)
        println(stderr, Crayon(foreground=:red)("Error: $valid_json not found. Run 'valid_words' first."))
        return 1
    end

    println("Loading dictionary for validation...")
    dict = Set(JSON.parsefile(valid_json))
    println("Dictionary loaded ($(length(dict)) words).")

    host = "127.0.0.1"
    port = 8080
    
    html_content = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Word Analyzer - Web Play</title>
        <style>
            body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; display: flex; flex-direction: column; align-items: center; background-color: #121213; color: white; margin: 0; padding: 20px; }
            h1 { margin-bottom: 20px; color: #56a5d9; }
            .game-container { max-width: 500px; width: 100%; display: flex; flex-direction: column; gap: 10px; }
            .history { display: flex; flex-direction: column; gap: 5px; margin-bottom: 20px; }
            .row { display: flex; gap: 5px; justify-content: flex-start; flex-wrap: nowrap; }
            .tile { width: 40px; height: 40px; border: 2px solid #3a3a3c; display: flex; align-items: center; justify-content: center; font-size: 1.5rem; font-weight: bold; text-transform: uppercase; border-radius: 4px; font-family: monospace; flex-shrink: 0; }
            .match { background-color: #538d4e; border-color: #538d4e; }
            .partial { background-color: #b59f3b; border-color: #b59f3b; }
            .none { background-color: #3a3a3c; border-color: #3a3a3c; }
            .input-area { display: flex; gap: 10px; justify-content: center; margin-top: 20px; }
            input { padding: 10px; font-size: 1.2rem; border-radius: 4px; border: none; width: 250px; text-transform: lowercase; background: #272729; color: white; font-family: monospace; }
            button { padding: 10px 20px; font-size: 1.1rem; border-radius: 4px; border: none; cursor: pointer; background-color: #56a5d9; color: white; font-weight: bold; }
            button:hover { background-color: #4a8dbd; }
            .message { margin-top: 15px; font-weight: bold; min-height: 1.5em; text-align: center; }
            .error { color: #ff5e5e; }
            .success { color: #538d4e; font-size: 1.5rem; }
            .alphabet-container { margin-top: 20px; font-family: monospace; font-size: 1.2rem; letter-spacing: 5px; color: #818384; text-align: center; max-width: 500px; line-height: 1.5; }
        </style>
    </head>
    <body>
        <h1>Word Analyzer Play</h1>
        <div class="game-container">
            <div id="history" class="history"></div>
            <div class="input-area">
                <input type="text" id="guessInput" placeholder="Type a word..." autofocus>
                <button onclick="submitGuess()">Guess</button>
            </div>
            <div id="message" class="message"></div>
            <div id="alphabet" class="alphabet-container"></div>
            <div style="text-align:center; margin-top: 30px; display: flex; gap: 10px; justify-content: center;">
                <button id="giveUpBtn" style="background-color: #7a3a3a;" onclick="giveUp()">I give up</button>
                <button style="background-color: #3a3a3c;" onclick="restartGame()">New Game</button>
            </div>
        </div>

        <script>
            const guessInput = document.getElementById('guessInput');
            const historyDiv = document.getElementById('history');
            const messageDiv = document.getElementById('message');
            const alphabetDiv = document.getElementById('alphabet');
            const giveUpBtn = document.getElementById('giveUpBtn');

            guessInput.addEventListener('keypress', (e) => {
                if (e.key === 'Enter') submitGuess();
            });

            async function submitGuess() {
                const guess = guessInput.value.trim().toLowerCase();
                if (!guess) return;
                messageDiv.textContent = 'Processing...';
                try {
                    const response = await fetch('/guess', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ guess })
                    });
                    const data = await response.json();
                    if (data.error) {
                        messageDiv.textContent = data.error;
                        messageDiv.className = 'message error';
                    } else {
                        messageDiv.textContent = '';
                        updateHistory(data.history);
                        updateAlphabet(data.useless);
                        guessInput.value = '';
                        if (data.victory) {
                            messageDiv.textContent = 'Congratulations! You guessed it!';
                            messageDiv.className = 'message success';
                            guessInput.disabled = true;
                            giveUpBtn.disabled = true;
                        }
                    }
                } catch (err) { messageDiv.textContent = 'Server error.'; }
            }

            async function giveUp() {
                try {
                    const response = await fetch('/reveal', { method: 'POST' });
                    const data = await response.json();
                    messageDiv.innerHTML = 'The word was: <span style="color: #ff5e5e; font-size: 1.5rem;">' + data.target + '</span>';
                    guessInput.disabled = true;
                    giveUpBtn.disabled = true;
                } catch (err) { messageDiv.textContent = 'Server error.'; }
            }

            async function restartGame() {
                await fetch('/restart', { method: 'POST' });
                historyDiv.innerHTML = '';
                messageDiv.textContent = 'New target selected!';
                messageDiv.className = 'message';
                guessInput.disabled = false;
                giveUpBtn.disabled = false;
                guessInput.value = '';
                guessInput.focus();
                updateAlphabet([]);
            }

            function updateHistory(history) {
                historyDiv.innerHTML = '';
                history.forEach(entry => {
                    const row = document.createElement('div');
                    row.className = 'row';
                    entry.forEach(tile => {
                        const tileDiv = document.createElement('div');
                        tileDiv.className = 'tile ' + tile.status;
                        tileDiv.textContent = tile.char;
                        row.appendChild(tileDiv);
                    });
                    historyDiv.appendChild(row);
                });
            }

            function updateAlphabet(useless) {
                const full = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("");
                const remaining = full.filter(char => !useless.includes(char.toLowerCase()));
                alphabetDiv.textContent = remaining.join(" ");
            }

            updateAlphabet([]);
        </script>
    </body>
    </html>
    """

    history = Vector{Vector{Any}}()
    useless_letters = Set{Char}()
    router = HTTP.Router()
    
    HTTP.register!(router, "GET", "/", req -> HTTP.Response(200, ["Content-Type" => "text/html"], body=html_content))
    
    HTTP.register!(router, "POST", "/guess", req -> begin
        data = JSON.parse(String(req.body))
        guess = lowercase(strip(get(data, "guess", "")))
        if !(guess in dict)
            return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(Dict("error" => "Word not in dictionary")))
        end
        
        target = target_ref[]
        t_chars = collect(target); t_len = length(t_chars)
        g_chars = collect(guess); g_len = length(g_chars)
        fb = fill("none", g_len); used = fill(false, t_len)
        
        for i in 1:min(g_len, t_len)
            if g_chars[i] == t_chars[i]; fb[i] = "match"; used[i] = true end
        end
        for i in 1:g_len
            if fb[i] != "match"
                found = false
                for j in 1:t_len
                    if !used[j] && g_chars[i] == t_chars[j]
                        fb[i] = "partial"; used[j] = true; found = true; break
                    end
                end
                !found && !(g_chars[i] in t_chars) && push!(useless_letters, g_chars[i])
            end
        end
        push!(history, [Dict("char" => string(g_chars[i]), "status" => fb[i]) for i in 1:g_len])
        return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(Dict("history" => history, "victory" => (guess == target), "useless" => collect(useless_letters))))
    end)
    
    HTTP.register!(router, "POST", "/reveal", req -> HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(Dict("target" => target_ref[]))))
    
    HTTP.register!(router, "POST", "/restart", req -> (target_ref[] = get_random_target(pf_file); empty!(history); empty!(useless_letters); HTTP.Response(200, body="OK")))

    println("Web interface running at: ", Crayon(bold=true, foreground=:cyan)("http://$host:$port"))
    try HTTP.serve(router, host, port) catch e; e isa InterruptException ? println("\nStopping...") : rethrow(e) end
    return 0
end

function preprocess(input_file::String, output_file::String)
    # 1. Ensure English word list
    mkpath("data")
    english_words_file = "data/words_alpha.txt"
    if !isfile(english_words_file)
        url = "https://github.com/dwyl/english-words/raw/master/words_alpha.txt"
        println("Downloading English word list from $url...")
        try
            r = HTTP.get(url)
            write(english_words_file, r.body)
            println("Download complete.")
        catch e
            println(stderr, Crayon(foreground=:red)("Error downloading word list: $e"))
            return 1
        end
    end

    # 2. Load English word list
    println("Loading English word list...")
    english_set = Set{String}()
    for line in eachline(english_words_file)
        w = lowercase(strip(line))
        !isempty(w) && push!(english_set, w)
    end
    println("Loaded $(length(english_set)) English words.")

    # 2.5 Load Wikipedia word list
    wiki_file = "data/wikipedia_counts.txt"
    wiki_set = Set{String}()
    if isfile(wiki_file)
        println("Loading Wikipedia word list...")
        for line in eachline(wiki_file)
            p = split(line)
            if !isempty(p)
                w = lowercase(strip(p[1]))
                !isempty(w) && push!(wiki_set, w)
            end
        end
        println("Loaded $(length(wiki_set)) Wikipedia words.")
    else
        println(Crayon(foreground=:yellow)("Warning: Wikipedia data file not found ($wiki_file). Run 'wdownload' first for better filtering."))
    end

    # 3. Load source words
    println("Loading words from $input_file...")
    all_data = Tuple{String, Int128}[]
    for line in eachline(input_file)
        p = split(line)
        length(p) >= 2 && push!(all_data, (lowercase(p[1]), parse(Int128, p[2])))
    end
    total_orig = length(all_data)

    # 4. Identify top 100 and bottom 20%
    sort!(all_data, by=x->x[2], rev=true)
    top100_set = Set(all_data[1:min(100, total_orig)] .|> x->x[1])
    cutoff_idx = total_orig - floor(Int, total_orig * 0.2)
    
    # 5. Multi-stage filtering with statistics
    # Stage 1: Bottom 20%
    del_bottom = total_orig - cutoff_idx
    after_bottom = all_data[1:cutoff_idx]
    
    # Stage 2: Top 100
    del_top = 0
    after_top = Tuple{String, Int128}[]
    for (w, c) in after_bottom
        if w in top100_set
            del_top += 1
        else
            push!(after_top, (w, c))
        end
    end
    
    # Stage 3: Length Filters
    del_len_short = 0
    del_len_long = 0
    after_len = Tuple{String, Int128}[]
    for (w, c) in after_top
        if length(w) <= 2
            del_len_short += 1
        elseif length(w) > 15
            del_len_long += 1
        else
            push!(after_len, (w, c))
        end
    end
    
    # Stage 4: Dictionary & Wiki Validation
    del_valid = 0
    final_kept = Tuple{String, Int128}[]
    deleted_invalid_top100 = Tuple{String, Int128}[]
    for (w, c) in after_len
        # Keep if in either set
        if !(w in english_set) && !(w in wiki_set)
            del_valid += 1
            if length(deleted_invalid_top100) < 100
                push!(deleted_invalid_top100, (w, c))
            end
        else
            push!(final_kept, (w, c))
        end
    end

    # 6. Save results
    mkpath("output")
    open(output_file, "w") do f
        for (w, c) in final_kept
            println(f, w, "\t", c)
        end
    end

    # 7. Print statistics
    C = (B=Crayon(bold=true), G=Crayon(foreground=:green), Y=Crayon(foreground=:yellow), CY=Crayon(foreground=:cyan), W=Crayon(foreground=:white))
    println("\n", C.B(C.CY("Preprocessing Statistics:")))
    println(@sprintf("%-30s: %d", "Total words processed", total_orig))
    println(Crayon(foreground=:red)(@sprintf("%-30s: %d", "Deleted (Bottom 20%)", del_bottom)))
    println(Crayon(foreground=:red)(@sprintf("%-30s: %d", "Deleted (Top 100)", del_top)))
    println(Crayon(foreground=:red)(@sprintf("%-30s: %d", "Deleted (Length <= 2)", del_len_short)))
    println(Crayon(foreground=:red)(@sprintf("%-30s: %d", "Deleted (Length > 15)", del_len_long)))
    println(Crayon(foreground=:red)(@sprintf("%-30s: %d", "Deleted (Not in Dict or Wiki)", del_valid)))
    println(C.B(C.G(@sprintf("%-30s: %d", "Final words remaining", length(final_kept)))))
    
    if !isempty(deleted_invalid_top100)
        println("\n", C.B(C.Y("Top 100 frequent words deleted (not in English dictionary or Wikipedia):")))
        for i in 1:length(deleted_invalid_top100)
            w, c = deleted_invalid_top100[i]
            @printf("%-20s (%d)%s", w, c, i % 3 == 0 ? "\n" : " | ")
        end
        println()
    end
    
    return 0
end

function analyze_prefix(input_file::String)
    root = TrieNode(); for line in eachline(input_file); p = split(line); insert!(root, p[1], parse(Int128, p[2])) end
    dw = Dict{Int, Int128}(); 
    trav(n, d) = (dw[d] = get(dw, d, 0) + n.weight; for c in values(n.children) trav(c, d+1) end); trav(root, 0)
    for d in sort(collect(keys(dw))); println(@sprintf("%-10d | %-25d", d, dw[d])) end
end

function top_words(input_file::String, l::Int, k::Int)
    c = sort([ (p[1], parse(Int128, p[2])) for p in (split(l) for l in eachline(input_file)) if length(p)>=2 && length(p[1])==l ], by=x->x[2], rev=true)
    for i in 1:min(k, length(c)); println(@sprintf("%-20s | %-20d", c[i]...)) end
end

function top_k_words(input_file::String, k::Int)
    c = sort([ (p[1], parse(Int128, p[2])) for p in (split(l) for l in eachline(input_file)) if length(p)>=2 ], by=x->x[2], rev=true)
    for i in 1:min(k, length(c)); println(@sprintf("%-20s | %-20d", c[i]...)) end
end

function longest_words(file_path::String, k::Int)
    if !isfile(file_path)
        println(stderr, Crayon(foreground=:red)("Error: File $file_path not found."))
        return 1
    end
    data = Tuple{String, Int}[]
    for line in eachline(file_path)
        parts = split(line)
        if !isempty(parts)
            word = parts[1]
            push!(data, (word, length(word)))
        end
    end
    sort!(data, by=x -> x[2], rev=true)
    for i in 1:min(k, length(data))
        word, len = data[i]
        println(@sprintf("%-30s | %d", word, len))
    end
    return 0
end

"""
    web_export(input_file, pf_file, out_file)

Creates a single optimized JSON file for web deployment.
"""
function web_export(input_file::String, pf_file::String, out_file::String)
    if !isfile(input_file) || !isfile(pf_file)
        println(stderr, Crayon(foreground=:red)("Error: Input files missing. Run preprocess and prefix_free first."))
        return 1
    end

    println("Exporting dictionary (words only)...")
    dict_words = String[]
    for line in eachline(input_file)
        parts = split(line)
        if !isempty(parts) push!(dict_words, parts[1]) end
    end

    println("Exporting targets...")
    targets = Any[]
    for line in eachline(pf_file)
        parts = split(line)
        if length(parts) >= 2
            push!(targets, Dict("w" => parts[1], "f" => parse(Int128, parts[2])))
        end
    end

    data = Dict(
        "dict" => dict_words,
        "targets" => targets
    )

    open(out_file, "w") do f
        JSON.print(f, data)
    end

    println(Crayon(bold=true, foreground=:green)("Success! Created web data bundle: $out_file"))
    println("Original size: ~7.5MB")
    println("New bundle size: ", round(filesize(out_file)/1024/1024, digits=2), " MB")
    println("Note: Once hosted, Gzip/Brotli will likely reduce this to < 1.5MB automatically.")
    return 0
end

function download_wikipedia_data()
    mkpath("data")
    output_file = "data/wikipedia_counts.txt"
    # Using a reputable source for Wikipedia word frequencies (IWillFail/wikipedia-word-frequency-list or similar)
    # A common large one is from the 'hermitdave/FrequencyWords' repo or similar research corpora.
    # Let's use the 1-gram data from a stable source.
    url = "https://raw.githubusercontent.com/IWillFail/wikipedia-word-frequency-list/master/enwiki-latest-all-titles-category-redone.txt"
    # Actually, a better/cleaner frequency list is from:
    url = "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_full.txt"
    
    println("Downloading Wikipedia word frequency list from $url...")
    try
        r = HTTP.get(url)
        write(output_file, r.body)
        println(Crayon(foreground=:green)("Download complete: $output_file"))
        println("Size: ", round(filesize(output_file)/1024/1024, digits=2), " MB")
    catch e
        println(stderr, Crayon(foreground=:red)("Error downloading Wikipedia data: $e"))
        return 1
    end
    return 0
end

function create_deploy_zip()
    output_zip = "deploy.zip"
    html_file = "index.html"
    data_file = "output/web_data.json"
    valid_file = "output/valid_words.json"
    
    # Files needed for wexport logic
    filtered = "output/count_1w_3.txt"
    pf_count = "output/prefix_free_words_count.txt"
    
    if !isfile(html_file)
        println(stderr, Crayon(foreground=:red)("Error: $html_file not found."))
        return 1
    end
    
    println("Running 'wexport' to ensure web data is up-to-date...")
    export_res = web_export(filtered, pf_count, data_file)
    if export_res != 0
        println(stderr, Crayon(foreground=:red)("Error: 'wexport' failed. Cannot create zip."))
        return 1
    end

    if !isfile(valid_file)
        println(stderr, Crayon(foreground=:red)("Error: $valid_file not found. Run 'valid_words' first."))
        return 1
    end

    # Create gzipped versions for deployment
    println("Compressing deployment files...")
    for f in [data_file, valid_file]
        try
            run(`gzip -k -f $f`)
        catch e
            println(stderr, Crayon(foreground=:yellow)("Warning: Could not create .gz for $f automatically."))
        end
    end

    println("Creating $output_zip...")
    try
        # Using shell zip for simplicity
        # -j junk paths (store files in root of zip)
        files_to_zip = [html_file, data_file, valid_file]
        # Include gzipped versions if they exist
        for f in [data_file, valid_file]
            gz = f * ".gz"
            if isfile(gz); push!(files_to_zip, gz); end
        end
        
        # Remove old zip to ensure clean start
        isfile(output_zip) && rm(output_zip)
        
        run(`zip -j $output_zip $files_to_zip`)
        println(Crayon(bold=true, foreground=:green)("Success! Created $output_zip"))
        println("Included files:")
        for f in files_to_zip; println("  - $f") end
    catch e
        println(stderr, Crayon(foreground=:red)("Error creating zip: $e"))
        return 1
    end
    return 0
end

function create_valid_words_json(input_file::String, output_json::String)
    # 1. Ensure English word list
    english_words_file = "data/words_alpha.txt"
    if !isfile(english_words_file)
        println(stderr, Crayon(foreground=:red)("Error: $english_words_file not found. Run 'preprocess' first."))
        return 1
    end

    # 2. Load English word list
    println("Loading English word list...")
    valid_set = Set{String}()
    for line in eachline(english_words_file)
        w = lowercase(strip(line))
        !isempty(w) && push!(valid_set, w)
    end

    # 3. Load Wikipedia word list
    wiki_file = "data/wikipedia_counts.txt"
    if isfile(wiki_file)
        println("Loading Wikipedia word list...")
        for line in eachline(wiki_file)
            p = split(line)
            if !isempty(p)
                w = lowercase(strip(p[1]))
                !isempty(w) && push!(valid_set, w)
            end
        end
    end
    println("Total validation vocabulary: $(length(valid_set)) words.")

    # 4. Filter input file
    println("Filtering $input_file...")
    if !isfile(input_file)
        println(stderr, Crayon(foreground=:red)("Error: $input_file not found."))
        return 1
    end

    final_words = String[]
    total_input = 0
    del_long = 0
    for line in eachline(input_file)
        p = split(line)
        if !isempty(p)
            total_input += 1
            word = lowercase(strip(p[1]))
            if word in valid_set
                if length(word) <= 15
                    push!(final_words, word)
                else
                    del_long += 1
                end
            end
        end
    end

    # 5. Save to JSON
    mkpath("output")
    open(output_json, "w") do f
        JSON.print(f, final_words)
    end

    C = (B=Crayon(bold=true), G=Crayon(foreground=:green), CY=Crayon(foreground=:cyan), R=Crayon(foreground=:red))
    println("\n", C.B(C.CY("Valid Words Statistics:")))
    println("Total words in source : $total_input")
    println(C.R("Deleted (Length > 15) : $del_long"))
    println(C.B(C.G("Valid words retained  : $(length(final_words))")))
    println("Saved to: $output_json")
    
    return 0
end

function deploy_pipeline(input::String, filtered::String)
    C = (B=Crayon(bold=true), G=Crayon(foreground=:green), CY=Crayon(foreground=:cyan), Y=Crayon(foreground=:yellow))
    println(C.B(C.CY("Starting Full Deployment Pipeline...")), "\n")
    
    # 1. Preprocess
    println(C.B("Step 1: Preprocessing..."))
    if preprocess(input, filtered) != 0
        println(stderr, Crayon(foreground=:red)("Deployment failed at Preprocessing step."))
        return 1
    end
    println()

    # 2. Prefix-Free Analysis
    println(C.B("Step 2: Prefix-Free Analysis..."))
    if prefix_free_analysis(filtered) != 0
        println(stderr, Crayon(foreground=:red)("Deployment failed at Prefix-Free Analysis step."))
        return 1
    end
    println()

    # 3. Valid Words Generation
    println(C.B("Step 3: Generating Valid Words JSON..."))
    if create_valid_words_json(input, "output/valid_words.json") != 0
        println(stderr, Crayon(foreground=:red)("Deployment failed at Valid Words step."))
        return 1
    end
    println()

    # 4. Zip (which calls wexport)
    println(C.B("Step 4: Exporting and Packaging..."))
    if create_deploy_zip() != 0
        println(stderr, Crayon(foreground=:red)("Deployment failed at Packaging step."))
        return 1
    end
    
    println("\n", C.B(C.G("=== Deployment Pipeline Successful ===")))
    println("Your package is ready: ", C.B(C.Y("deploy.zip")))
    return 0
end

function vlongest_words(file_path::String, k::Int)
    if !isfile(file_path)
        println(stderr, Crayon(foreground=:red)("Error: File $file_path not found. Run 'valid_words' first."))
        return 1
    end
    words = JSON.parsefile(file_path)
    data = [(w, length(w)) for w in words]
    sort!(data, by=x -> x[2], rev=true)
    for i in 1:min(k, length(data))
        word, len = data[i]
        println(@sprintf("%-40s | %d", word, len))
    end
    return 0
end

function print_usage()
    C = (B=Crayon(bold=true), G=Crayon(foreground=:green), Y=Crayon(foreground=:yellow), CY=Crayon(foreground=:cyan))
    println(C.B(C.CY("Pantaludounboundiglossia")), "\nUsage: ./word_analyzer.jl ", C.Y("<command>"), " [args...]\n\n", C.B("COMMANDS:"))
    for (k, v) in [("deploy", "Run full build pipeline"), ("preprocess","Filter"), ("prefix","Depth analysis"), ("prefix_free","Pruning"), ("random","Sample"), ("play","CLI Game"), ("wplay", "Web Game"), ("wexport", "Export for Web"), ("zip", "Package for Web"), ("valid_words", "Export valid words JSON"), ("top_words","Top k of len l"), ("top","Top k overall"), ("longest", "Longest k prefix-free"), ("vlongest", "Longest k valid words"), ("wdownload", "Download Wiki data"), ("help", "Detailed command help")] println("  ", C.G(rpad(k, 12)), v) end
    println("\nRun './word_analyzer.jl help <command>' for detailed information.")
end

function print_detailed_help(cmd::String="")
    C = (B=Crayon(bold=true), G=Crayon(foreground=:green), Y=Crayon(foreground=:yellow), CY=Crayon(foreground=:cyan), W=Crayon(foreground=:white))
    
    help_data = Dict(
        "vlongest" => """
            List the top 'k' longest words in the valid words dataset.
            - Usage: ./word_analyzer.jl vlongest <k>
            - Example: ./word_analyzer.jl vlongest 5
            
            Reads from output/valid_words.json and sorts by character count.
            """,
        "deploy" => """
            Run the complete build and package pipeline.
            - Steps: preprocess -> prefix_free -> wexport -> zip
            
            This is the main command for generating a production-ready web 
            deployment from raw data. It ensures all dependencies and 
            intermediate files are correctly updated in sequence.
            """,
        "valid_words" => """
            Filter source words against dictionaries and export to JSON.
            - Input: data/count_1w.txt
            - Output: output/valid_words.json
            
            Similar to the validation stage of 'preprocess', but keeps all words 
            found in either the English dictionary or Wikipedia data (ignoring
            frequency cutoffs), and with a length <= 15 characters. The result 
            is saved as a simple JSON array of strings.
            """,
        "zip" => """
            Package the application for web deployment.
            - Input: index.html, output/web_data.json
            - Output: deploy.zip
            
            Creates a ZIP archive containing the interactive web interface and its 
            required data files. The resulting file can be unzipped and hosted on 
            any static web server.
            """,
        "wdownload" => """
            Download English Wikipedia word frequency data.
            - Output: data/wikipedia_counts.txt
            
            Fetches a comprehensive list of words and their occurrence counts from 
            English Wikipedia. This can be used as an alternative or additional 
            source for analysis.
            """,
        "preprocess" => """
            Filter the source word frequency file using multiple criteria.
            - Input: data/count_1w.txt
            - External: dwyl/english-words (downloaded to data/)
            - Output: output/count_1w_3.txt
            
            Operations:
            1. Ensures the 'dwyl/english-words' list is available.
            2. Removes the bottom 20% least frequent words.
            3. Removes the top 100 most frequent words.
            4. Removes words with length <= 2.
            5. Removes words not found in the English word list OR the Wikipedia list.
            6. Prints detailed statistics and the top 100 rejected words.
            """,
        "prefix" => """
            Perform depth analysis on the prefix tree (Trie).
            - Input: output/count_1w_3.txt
            
            This command builds a Trie from the preprocessed words and calculates the 
            aggregate frequency (weight) of words at each depth (length) of the tree.
            Useful for understanding word length distribution in the dataset.
            """,
        "prefix_free" => """
            Extract a prefix-free subset of words.
            - Input: output/count_1w_3.txt
            - Outputs: output/prefix_free_words.txt (alphabetical)
                      output/prefix_free_words_count.txt (frequency-sorted)
            
            A word is removed if its frequency is less than the sum of the frequencies 
            of all words that have it as a prefix. This ensures that the remaining 
            set is 'prefix-free' (no word in the set is a prefix of another) while 
            maximizing the retained frequency weight.
            """,
        "random" => """
            Select a weighted random word from the prefix-free list.
            - Input: output/prefix_free_words_count.txt
            
            Uses the stored frequencies to perform weighted sampling. Words with higher 
            frequencies are more likely to be chosen.
            """,
        "play" => """
            Start an interactive command-line word guessing game (Wordle-style).
            - Inputs: data/count_1w.txt (for validation), output/prefix_free_words_count.txt (for target selection)
            
            The game selects a random prefix-free word. You must guess words from the 
            dictionary. Feedback is provided:
            - Green: Correct letter in the correct position.
            - Yellow: Correct letter in the wrong position.
            - White/Grey: Letter not in the word.
            """,
        "wplay" => """
            Launch a web-based interface for the word guessing game.
            - Inputs: Same as 'play'.
            
            Starts a local HTTP server at http://127.0.0.1:8080. Provides a modern 
            UI with visual history, virtual keyboard tracking, and 'Give Up' functionality.
            """,
        "wexport" => """
            Export the dictionary and prefix-free targets for web deployment.
            - Inputs: output/count_1w_3.txt, output/prefix_free_words_count.txt
            - Output: output/web_data.json
            
            Creates a single JSON file containing the full valid dictionary and the 
            weighted target list. Optimized for size and use in static web pages.
            """,
        "top" => """
            List the top 'k' most frequent words in the original dataset.
            - Usage: ./word_analyzer.jl top <k>
            - Example: ./word_analyzer.jl top 10
            """,
        "top_words" => """
            List the top 'k' most frequent words of a specific length 'l'.
            - Usage: ./word_analyzer.jl top_words <l> <k>
            - Example: ./word_analyzer.jl top_words 5 10 (top 10 words of length 5)
            """,
        "longest" => """
            List the top 'k' longest words in the prefix-free dataset.
            - Usage: ./word_analyzer.jl longest <k>
            - Example: ./word_analyzer.jl longest 5
            
            Reads from output/prefix_free_words.txt and sorts by character count.
            """,
        "help" => """
            Show this detailed help information.
            - Usage: ./word_analyzer.jl help [command]
            """
    )

    if haskey(help_data, cmd)
        println(C.B(C.CY("COMMAND: " * cmd)))
        println(C.W(help_data[cmd]))
    else
        if !isempty(cmd)
            println(C.B(Crayon(foreground=:red)("Unknown command: $cmd\n")))
        end
        print_usage()
    end
    return 0
end

function (@main)(args)
    if isempty(args); print_usage(); return 1 end
    cmd = args[1]; input = "data/count_1w.txt"; filtered = "output/count_1w_3.txt"; pf_count = "output/prefix_free_words_count.txt"; pf = "output/prefix_free_words.txt"
    if cmd == "help"; return print_detailed_help(length(args) > 1 ? args[2] : "")
    elseif cmd == "deploy"; return deploy_pipeline(input, filtered)
    elseif cmd == "wdownload"; return download_wikipedia_data()
    elseif cmd == "zip"; return create_deploy_zip()
    elseif cmd == "valid_words"; return create_valid_words_json(input, "output/valid_words.json")
    elseif cmd == "vlongest"; return vlongest_words("output/valid_words.json", parse(Int, args[2]))
    elseif cmd == "preprocess"; preprocess(input, filtered)
    elseif cmd == "prefix"; analyze_prefix(filtered)
    elseif cmd == "prefix_free"; prefix_free_analysis(filtered)
    elseif cmd == "random"; random_word(pf_count)
    elseif cmd == "play"; play_game(input, pf_count)
    elseif cmd == "wplay"; return web_play_game(input, pf_count)
    elseif cmd == "wexport"; return web_export(filtered, pf_count, "output/web_data.json")
    elseif cmd == "top"; length(args) < 2 ? (println(Crayon(foreground=:red)("Missing k"))) : return top_k_words(input, parse(Int, args[2]))
    elseif cmd == "top_words"; length(args) < 3 ? (println(Crayon(foreground=:red)("Missing l k"))) : return top_words(input, parse(Int, args[2]), parse(Int, args[3]))
    elseif cmd == "longest"; length(args) < 2 ? (println(Crayon(foreground=:red)("Missing k"))) : return longest_words(pf, parse(Int, args[2]))
    else println(Crayon(foreground=:red)("Unknown command: $cmd")); print_usage() end
    return 0
end
