using REPL
using REPL.LineEdit

term = REPL.Terminals.TTYTerminal("xterm", stdin, stdout, stderr)
hp = REPL.REPLHistoryProvider(Dict{Symbol,Any}())

prompt = LineEdit.Prompt("test: ";
    hist = hp,
    on_done = (s, buf, ok) -> begin
        if ok
            LineEdit.add_history(s)
            return true
        else
            return false
        end
    end)

mi = LineEdit.ModalInterface([prompt])
s = LineEdit.MIState(mi, term)

println("Type something and press enter:")
LineEdit.run_interface(term, mi, s)
res = String(take!(LineEdit.buffer(s)))
println("You typed: ", res)
