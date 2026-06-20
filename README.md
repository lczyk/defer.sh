# defer.sh

![GitHub Tag](https://img.shields.io/github/v/tag/lczyk/defer.sh?label=release)
![License](https://img.shields.io/github/license/lczyk/defer.sh)

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

## more details

note: i will skip the `source defer.sh` bit from now on.

you can defer on other signals ofc:

```bash
output=""
defer "output='hello'" USR1
echo "$output" # (empty)
kill -USR1 $$
echo "$output" # hello
```

defer in a function. note that `EXIT` fires when the *script* exits, not when
the function returns -- use `RETURN` for that:

```bash
test_var=0
f() { defer "test_var=1" RETURN; test_var=2; }
f
echo "$test_var" # 1, the RETURN trap ran on the way out of f
```

defer in a subshell. the deferred command fires when the subshell exits:

```bash
f() { printf "a"; defer 'printf "b"' EXIT; }
echo "$(f)" # ab
```

you can register one command on several signals in a single call -- it gets
deferred independently on each:

```bash
defer "echo bye" USR1 USR2 EXIT
kill -USR1 $$ # bye
kill -USR2 $$ # bye
# ...and again on EXIT
```

if any of the defered commands fails, it's status is saved in the
`$defer_status` variable:

```bash
(
    defer 'echo "exited with $defer_status"' EXIT
    exit 99
) # exited with 99
```

running with `-x` does *NOT* spam you:

```bash
bash -x example.sh
+ source defer.sh
+ work
+ local resource=db-handle
+ defer 'echo released db-handle' EXIT
+ return 0
+ defer 'echo cleanup-second' EXIT
+ return 0
+ defer 'echo cleanup-first' EXIT
+ return 0
+ echo 'acquired db-handle'
acquired db-handle
+ echo done
done
+ defer_status=0
+ : 'defer: running EXIT handlers'
+ echo cleanup-first
cleanup-first
+ echo cleanup-second
cleanup-second
+ echo released db-handle
released db-handle
```

unless you set `$DEFER_DEBUG`:

```bash
DEFER_DEBUG=1 bash -x example.sh 2>&1 | head
+ source defer.sh
++ [[ defer.sh == \e\x\a\m\p\l\e\.\s\h ]]
++ [[ -z '' ]]
++ __DEFER_SH_VERSION__=1.3.0
++ declare -f -t defer
++ [[ 2 -eq 1 ]]
++ __DEFER_SH__=1
++ case $_defer_src_x in
++ unset _defer_src_x
++ set -x
```



