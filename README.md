# defer.sh

`defer` in bash. kinda. mostly. with some footguns, but honestly, given the number
of footguns in bash itself, i think its fitting. to be clear, i've tried to polish
out the footguns really hard. they are *shiny*.

anyway...

`defer.sh` is a single-file, single-function library which you can source in your
other scripts and then use like this:

```bash
source defer.sh

output=""
defer 'echo $output' EXIT
defer "output+='world!'" EXIT
defer "output+='hello '" EXIT
```

this works exaclty as you'd (hopefully) expect, aka it echoes "hello world". note
that, unlike vanilla `trap` we can have multiple `defer`s on one signal. this is
indeed the main use-case of `defer` over `trap`.

`defer` was written based on a [post](https://stackoverflow.com/a/7287873/2531987)
by Richard Hansen (CC-BY-SA 3.0). 