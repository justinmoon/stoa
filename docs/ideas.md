# initial prompt

i want to build a desktop app that is basically a tiling window manager targeted at
ai-driven software development.

the insight here is that i really enjoy a tiling wm environment *when coding* but not
otherwise.
- the problem with things like i3 is that you are forced to adopt linux to use it - which i
don't want to do for my daily driver environment - and you have to use i3 for non-code
computer use too which i also don't want to do.
- the problem with terminal multiplexers like tmux is that there are many coding usecases that
 can't be done in a terminal - like testing an app in a browser or reviewing prs on github or
using a proper desktop app like vscode or zed. tuis are nice but also suck. it would good to
be able to not be forced to use tuis for everything.

so i want a desktop app that is intended to be full-screened. it's like i3 basically but it
can be run on windows, mac, or linux (eventually). it should be portable to any os. so this is
 **portability**

you can tile windows or maybe have modal experiences or generally hack it to do whatever you
want in this department. **hackability** is also a really important characteristic

another thing i want is speed. every time i move from vs code to vim i'm so delighted by how
fast it is. so we should use code from zed and ghostty and whatever things are really fast.

but i also don't want to take a year to build this. so i want to build it in a very iterative
manner. so i think the best place to start would be with a tiling environment itself. the
contents could be very simple to start. maybe just randomly generated text greetings or
soemthing. or maybe terminals. or maybe webviews. something like this. i want something that's
 usable for my coding tasks soon. daily driver soon

and i think zig is a good langauge to build this in. so tactically i think we should start by
lookin at ~/code/prise which is a new tmux style tiling wm written in zig. please explore that
 and describe how to proceed.
- should we form it?
- should we initialize a new project and import some of their code?
- new project and copy some of their code?
- new project and just copy ideas? code from scratch?
- something else???

what i'm thinking would be a realy nice daily driver mvp is a desktop app that:
- works on my mac - i dont' care about other platrforms yet.
- can do basic tiling. ideally we could have named "window" and tiled "panes" like tmux has.
but only that.
- panes can be terminals or webviews

that would be a really nice setup imo. i imagine that ghostty and prise probably handle a
bunch of the terminal stuff and tiling in some way or another - at least in concept. so the
big question for me is how to make a light weight webview. so please include an exploration of
 this and provide an overview of options. make a recommendation of the best place to start for
 a quick mvp as well as the best approach long-term.

